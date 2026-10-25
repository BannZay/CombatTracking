-- Combat state logic without any frames, so it can be tested outside the game.
CombatTracking = CombatTracking or {}
local Core = {}
CombatTracking.Core = Core

Core.COMBAT_DURATION = 5.5 -- a player leaves combat this long after the last hostile action
Core.LEAVE_GRACE = 0.3 -- combat flag must stay off this long before the unit counts as out of combat
Core.KEEP_DURATION = 86400 -- swipe length while a channel keeps the caster in combat
Core.SWIPE_TTL = 60 -- swipes of untracked units older than this are dropped

-- Spells are matched by name so that every rank is covered (names come from GetSpellInfo, so they
-- match the localized combat log).
local noCombatSpellIds = {
	6770, -- Sap
	453, -- Mind Soothe
	57934, -- Tricks of the Trade
}
-- spells whose SPELL_DAMAGE are periodic ticks reported as direct damage
local ignoredDamageSpellIds = {
	2944, -- Devouring Plague
}
-- channels that keep the caster in combat while their aura is up
local combatKeeperSpellIds = {
	605, -- Mind Control
	48045, -- Mind Sear
}

local function NameSet(ids)
	local set = {}
	for _, id in ipairs(ids) do
		local name = GetSpellInfo(id)
		if name then set[name] = true end
	end
	return set
end

function Core.BuildSpellSets()
	Core.noCombatSpells = NameSet(noCombatSpellIds)
	Core.ignoredDamageSpells = NameSet(ignoredDamageSpellIds)
	Core.combatKeepers = NameSet(combatKeeperSpellIds)
end
Core.BuildSpellSets()

local hostileEvents = {
	SWING_DAMAGE = true, SWING_MISSED = true,
	RANGE_DAMAGE = true, RANGE_MISSED = true,
	SPELL_DAMAGE = true, SPELL_MISSED = true,
}
local auraEvents = {
	SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REFRESH = true, SPELL_DISPEL = true,
}

-- Returns what a combat log event means for combat: "hostile", "heal", "aura" (hostile or friendly
-- depending on the units), "keepStart", "keepEnd" or nil (no effect).
function Core.Classify(eventType, spellName)
	if spellName and Core.noCombatSpells[spellName] then return nil end
	if hostileEvents[eventType] then
		if eventType == "SPELL_DAMAGE" and Core.ignoredDamageSpells[spellName] then return nil end
		return "hostile"
	elseif eventType == "SPELL_HEAL" then
		return "heal"
	elseif auraEvents[eventType] then
		if eventType == "SPELL_AURA_APPLIED" and Core.combatKeepers[spellName] then return "keepStart" end
		return "aura"
	elseif eventType == "SPELL_AURA_REMOVED" and Core.combatKeepers[spellName] then
		return "keepEnd"
	end
end

local REACTION_FRIENDLY = 0x10
local REACTION_HOSTILE = 0x40

local function Reaction(flags)
	if not flags then return nil end
	if bit.band(flags, REACTION_HOSTILE) ~= 0 then return "hostile" end
	if bit.band(flags, REACTION_FRIENDLY) ~= 0 then return "friendly" end
end

------------------------------------------------------------------------
-- Tracker: combat swipes per GUID, fed by the combat log
------------------------------------------------------------------------

local Tracker = {}
Tracker.__index = Tracker

-- env.UnitIsEnemy(unitA, unitB), env.UnitAffectingCombat(unit)
function Core.NewTracker(env)
	return setmetatable({ env = env, tokens = {}, swipes = {} }, Tracker)
end

-- GUIDs of the tracked units; anything else in the combat log is ignored.
function Tracker:SetTracked(guid, unit)
	if guid then self.tokens[guid] = unit end
end

function Tracker:ClearTracked()
	for k in pairs(self.tokens) do self.tokens[k] = nil end
end

function Tracker:IsTracked(guid)
	return guid ~= nil and self.tokens[guid] ~= nil
end

-- Starts (or restarts) the swipe of `guid`, unless a channel keeps it in combat.
function Tracker:Mark(guid, now)
	local s = self.swipes[guid]
	if not s then
		self.swipes[guid] = { start = now }
	elseif not s.keep then
		s.start = now
	end
end

function Tracker:SetKeep(guid, now, keep)
	local s = self.swipes[guid]
	if not s then
		s = {}
		self.swipes[guid] = s
	end
	s.keep = keep or nil
	s.start = now
end

-- start, keep of the current swipe of `guid`, or nil
function Tracker:GetSwipe(guid)
	local s = guid and self.swipes[guid]
	if s then return s.start, s.keep end
end

function Tracker:ClearSwipe(guid)
	if guid then self.swipes[guid] = nil end
end

-- Drops old swipes of units that are no longer tracked.
function Tracker:Prune(now)
	for guid, s in pairs(self.swipes) do
		if not s.keep and not self.tokens[guid] and now - s.start > Core.SWIPE_TTL then
			self.swipes[guid] = nil
		end
	end
end

function Tracker:IsHostilePair(srcGUID, srcFlags, dstGUID, dstFlags)
	local src, dst = self.tokens[srcGUID], self.tokens[dstGUID]
	if src and dst then
		return self.env.UnitIsEnemy(src, dst) and true or false
	end
	local a, b = Reaction(srcFlags), Reaction(dstFlags)
	return (a == "hostile" and b == "friendly") or (a == "friendly" and b == "hostile")
end

function Tracker:OnCombatLog(now, eventType, srcGUID, srcFlags, dstGUID, dstFlags, spellName)
	if srcGUID == dstGUID then return end
	local tokens = self.tokens
	local src = srcGUID and tokens[srcGUID]
	local dst = dstGUID and tokens[dstGUID]
	if not src and not dst then return end

	local kind = Core.Classify(eventType, spellName)
	if not kind then return end

	if kind == "aura" then
		kind = self:IsHostilePair(srcGUID, srcFlags, dstGUID, dstFlags) and "hostile" or "heal"
	end

	if kind == "hostile" then
		if src then self:Mark(srcGUID, now) end
		if dst then self:Mark(dstGUID, now) end
	elseif kind == "heal" then
		-- helping a unit that is in combat puts the helper in combat
		if src and dst and self.env.UnitAffectingCombat(dst) then self:Mark(srcGUID, now) end
	elseif kind == "keepStart" then
		if src then self:SetKeep(srcGUID, now, true) end
		if dst then self:Mark(dstGUID, now) end
	elseif kind == "keepEnd" then
		if src then self:SetKeep(srcGUID, now, false) end
		if dst then self:Mark(dstGUID, now) end
	end
end

------------------------------------------------------------------------
-- Per-icon combat state, fed by the unit's combat flag
------------------------------------------------------------------------

-- Updates `st` ({ guid, inCombat, leaveAt }) for the unit now shown by an icon.
-- Returns "enter" or "leave" on a real change of the same unit, else nil. A new unit, a unit that
-- disappears and a unit that dies never return a change (no sound for those).
function Core.UpdateCombatState(st, now, guid, inCombat, dead)
	if guid ~= st.guid then
		st.guid = guid
		st.inCombat = guid ~= nil and inCombat and not dead and true or false
		st.leaveAt = nil
		return nil
	end
	if not guid then return nil end

	if dead then
		st.inCombat = false
		st.leaveAt = nil
		return nil
	end

	if inCombat then
		st.leaveAt = nil
		if not st.inCombat then
			st.inCombat = true
			return "enter"
		end
	elseif st.inCombat then
		if not st.leaveAt then
			st.leaveAt = now
		elseif now - st.leaveAt >= Core.LEAVE_GRACE then
			st.inCombat = false
			st.leaveAt = nil
			return "leave"
		end
	end
	return nil
end

-- Remaining seconds of a swipe, or nil when it has run out or is endless.
function Core.SwipeRemaining(start, keep, now)
	if not start or keep then return nil end
	local left = start + Core.COMBAT_DURATION - now
	if left > 0 then return left end
end
