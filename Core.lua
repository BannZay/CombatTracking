-- Combat state logic without any frames, so it can be tested outside the game.
--
-- It follows how the server keeps combat (TrinityCore src/server/game/Combat/CombatManager.cpp):
-- * Combat is a set of references between two units; a unit is in combat while it has one.
-- * A reference between two player-controlled units (players, their pets) is PvP: it ends 5 seconds
--   (PVP_COMBAT_TIMEOUT) after the last hostile contact between the two. Other references (PvE)
--   have no timer.
-- * Melee swings, hostile spells that hit or miss (not evade) and hostile casts refresh a reference.
--   Periodic damage and periodic healing do not.
-- * Helping a unit that is in combat (heal, buff, ...) copies its references to the helper.
-- * Spells without initial aggro (Sap, Hunter's Mark, ...) only count on a target already in combat.
-- * Death and "unattackable" auras end all references of a unit on both sides. Vanish and Feign
--   Death only drop the unit's own combat state; its opponents stay in combat with it.
-- * Attacking a pet also puts its owner in combat with the attacker (Unit::AtTargetAttacked): melee
--   swings, and spells that land (not misses).
-- * Some hits are not in the combat log (Mass Dispel on an enemy without buffs); the caster's cast
--   finishing stands for them.
CombatTracking = CombatTracking or {}
local CT = CombatTracking
local Core = {}
CT.Core = Core

Core.DEFAULT_DURATION = 5.0 -- PVP_COMBAT_TIMEOUT; replaced by the duration measured on the realm
Core.duration = Core.DEFAULT_DURATION
Core.KEEP_DURATION = 86400 -- swipe length while a channel keeps the caster in combat
Core.KEEP_MAX = 65 -- a kept state without its aura removal is dropped after this long
Core.PVE_TTL = 10 -- a PvE contact without a new one is forgotten after this long
Core.FORGET_AFTER = 2 -- expired PvP contacts are dropped this long after expiring
Core.SUPPRESS_WINDOW = 1 -- leaving combat this soon after Vanish & co. is not a timer expiry
-- Feign Death also logs UNIT_DIED (the client logs a death when the "dead" flag is set). A death is
-- final once no Feign Death aura came within this time.
Core.DEATH_CONFIRM = 1

-- duration measurement: gaps between the last contact and the combat flag dropping
Core.SAMPLE_MIN, Core.SAMPLE_MAX = 4, 7
Core.MAX_SAMPLES = 25
Core.MIN_SAMPLES = 5
-- Missed contacts (out of combat log range) only make a gap longer, so a low quantile is used.
Core.SAMPLE_QUANTILE = 0.3

local NO_AGGRO = CT.NoInitialAggro or {}
local SUPPRESS = CT.SuppressCombat or {}
local END_COMBAT = CT.EndCombat or {}

local COMBATLOG_CONTROL_PLAYER = 0x100
local REACTION_FRIENDLY = 0x10
local REACTION_HOSTILE = 0x40

-- Matched by name (all ranks).
local ignoredDamageSpellIds = {
	2944, -- Devouring Plague: some servers log its ticks as direct damage
}
local combatKeeperSpellIds = {
	605, -- Mind Control
	48045, -- Mind Sear
}
-- Spells whose hits on enemies are not in the combat log. Mass Dispel hits enemies with a hidden
-- triggered spell (32592), so an enemy without buffs gets no event, and a spell with a cast time
-- logs no SPELL_CAST_SUCCESS (the client only logs it for instant spells). The cast finishing
-- (UNIT_SPELLCAST_SUCCEEDED) stands for those hits.
local hiddenHitSpellIds = {
	32375, -- Mass Dispel
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
	Core.ignoredDamageSpells = NameSet(ignoredDamageSpellIds)
	Core.combatKeepers = NameSet(combatKeeperSpellIds)
	Core.hiddenHitSpells = NameSet(hiddenHitSpellIds)
end
Core.BuildSpellSets()

local eventKinds = {
	SWING_DAMAGE = "hostile", SWING_MISSED = "hostile",
	RANGE_DAMAGE = "hostile", RANGE_MISSED = "hostile",
	SPELL_DAMAGE = "hostile", SPELL_MISSED = "hostile",
	SPELL_DRAIN = "hostile", SPELL_LEECH = "hostile",
	SPELL_INTERRUPT = "hostile", SPELL_STOLEN = "hostile", SPELL_DISPEL_FAILED = "hostile",
	SPELL_HEAL = "help", SPELL_ENERGIZE = "help",
	SPELL_CAST_SUCCESS = "either", SPELL_DISPEL = "either",
	SPELL_AURA_APPLIED = "either", SPELL_AURA_REFRESH = "either", SPELL_AURA_APPLIED_DOSE = "either",
	SPELL_AURA_REMOVED = "auraRemoved",
	UNIT_DIED = "death", UNIT_DESTROYED = "death",
}

-- What a combat log event can mean: "hostile", "help", "either" (decided by the units), "death",
-- "auraRemoved" or nil (no effect on combat).
function Core.Classify(eventType)
	return eventKinds[eventType]
end

-- Hostile events after which the server engages the owner of the target (Unit::AtTargetAttacked).
local engagesOwner = {
	SWING_DAMAGE = true, SWING_MISSED = true, RANGE_DAMAGE = true,
	SPELL_DAMAGE = true, SPELL_DRAIN = true, SPELL_LEECH = true, SPELL_INTERRUPT = true, SPELL_STOLEN = true,
	SPELL_DISPEL = true, SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_APPLIED_DOSE = true,
}

local function Reaction(flags)
	if not flags then return nil end
	if bit.band(flags, REACTION_HOSTILE) ~= 0 then return "hostile" end
	if bit.band(flags, REACTION_FRIENDLY) ~= 0 then return "friendly" end
end

local function PlayerControlled(flags)
	return flags ~= nil and bit.band(flags, COMBATLOG_CONTROL_PLAYER) ~= 0
end

------------------------------------------------------------------------
-- Tracker: combat references seen in the combat log
------------------------------------------------------------------------

local Tracker = {}
Tracker.__index = Tracker

-- env.UnitIsEnemy(unitA, unitB), env.UnitAffectingCombat(unit)
function Core.NewTracker(env)
	return setmetatable({
		env = env,
		tokens = {}, -- guid -> unit token of a tracked unit
		contacts = {}, -- guid -> partner -> { t = last contact, first = first contact, pvp, est = estimated }
		keep = {}, -- guid -> time a combat keeper channel started
		suppressedAt = {}, -- guid -> time of Vanish, Feign Death, ...
		deadAt = {}, -- guid -> time of UNIT_DIED, until confirmed (not a Feign Death)
		ownerOf = {}, -- pet guid -> owner guid
	}, Tracker)
end

function Tracker:SetTracked(guid, unit)
	if guid then self.tokens[guid] = unit end
end

function Tracker:ClearTracked()
	for k in pairs(self.tokens) do self.tokens[k] = nil end
end

-- Pets with a known owner (from unit tokens such as arenapet1 / arena1).
function Tracker:SetOwners(ownerOf)
	self.ownerOf = ownerOf
end

function Tracker:IsTracked(guid)
	return guid ~= nil and self.tokens[guid] ~= nil
end

local function Link(contacts, a, b, t, pvp, est)
	local list = contacts[a]
	if not list then
		list = {}
		contacts[a] = list
	end
	local entry = list[b]
	if not entry then
		list[b] = { t = t, first = t, pvp = pvp, est = est }
	elseif t >= entry.t then
		entry.t, entry.pvp, entry.est = t, pvp, est
	end
end

local function Unlink(contacts, a, b)
	local list = contacts[a]
	if list then
		list[b] = nil
		if next(list) == nil then contacts[a] = nil end
	end
end

-- A hostile contact between a and b at time t refreshes their reference.
function Tracker:Contact(a, b, t, pvp)
	Link(self.contacts, a, b, t, pvp)
	Link(self.contacts, b, a, t, pvp)
end

local function Live(entry, now)
	if entry.pvp then return now - entry.t <= Core.duration end
	return now - entry.t <= Core.PVE_TTL
end

function Tracker:HasLiveContacts(guid, now)
	local list = self.contacts[guid]
	if list then
		for partner, entry in pairs(list) do
			if Live(entry, now) and not self.deadAt[partner] then return true end
		end
	end
	return self.keep[guid] ~= nil
end

-- Whether the server would treat the unit as engaged (in combat).
function Tracker:IsEngaged(guid, now)
	local token = self.tokens[guid]
	if token then return self.env.UnitAffectingCombat(token) and true or false end
	return self:HasLiveContacts(guid, now)
end

-- The helper gets the references of the unit it helps.
function Tracker:Inherit(helper, helped, now)
	local copied = false
	local list = self.contacts[helped]
	if list then
		for partner, entry in pairs(list) do
			if partner ~= helper and not entry.est and Live(entry, now) then
				self:Contact(helper, partner, now, entry.pvp)
				copied = true
			end
		end
	end
	if not copied then
		-- the helped unit's opponents are unknown: a reference with the helped unit stands for them
		Link(self.contacts, helper, "help:" .. helped, now, true)
	end
end

-- A unit died: its references stop counting at once and end when the death is confirmed.
function Tracker:OnDeath(guid, now)
	local suppressed = self.suppressedAt[guid]
	if suppressed and now - suppressed <= Core.DEATH_CONFIRM then return end -- Feign Death
	self.deadAt[guid] = now
end

-- Ends every reference of the unit, on both sides (death, unattackable).
function Tracker:EndAll(guid)
	local list = self.contacts[guid]
	if list then
		for partner in pairs(list) do Unlink(self.contacts, partner, guid) end
		self.contacts[guid] = nil
	end
	self.keep[guid] = nil
end

-- The unit entered combat without a contact we saw: start an estimated swipe.
function Tracker:OnEnter(guid, now)
	if not self:HasLiveContacts(guid, now) then
		Link(self.contacts, guid, "flag", now, true, true)
	end
end

-- The unit finished casting a spell whose enemy hits are not logged (Core.hiddenHitSpells): it
-- refreshes the unit's combat with the enemies it hit, which are unknown. Estimated: the spell may
-- have hit no enemy.
function Tracker:OnHiddenHit(guid, now)
	Link(self.contacts, guid, "hidden", now, true, true)
end

-- The unit left combat. Returns the measured combat duration when the leave was a plain timer
-- expiry of known contacts.
function Tracker:OnLeave(guid, now)
	local start, mode, est = self:GetSwipe(guid, now)
	local suppressed = self.suppressedAt[guid] and now - self.suppressedAt[guid] <= Core.SUPPRESS_WINDOW
	local sample
	if mode == "timer" and not est and not suppressed then
		local gap = now - start
		if gap >= Core.SAMPLE_MIN and gap <= Core.SAMPLE_MAX then sample = gap end
	end
	if suppressed then
		self.contacts[guid] = nil -- the opponents keep their references with this unit
		self.keep[guid] = nil
	else
		self:EndAll(guid)
	end
	return sample
end

-- start, mode, estimated of the unit's combat:
--   mode "timer": PvP only, combat ends at start + Core.duration (estimated: start not seen)
--   mode "pve": fighting NPCs, no timer; start is when that fight was first seen
--   mode "keep": a channel keeps it in combat
function Tracker:GetSwipe(guid, now)
	if not guid then return nil end
	if self.keep[guid] then return self.keep[guid], "keep" end
	local list = self.contacts[guid]
	if not list then return nil end
	local deadAt = self.deadAt
	local start, est, pveStart
	for partner, entry in pairs(list) do
		if deadAt[partner] then
			-- a dead opponent no longer counts
		elseif entry.pvp then
			if not start or entry.t > start then start, est = entry.t, entry.est end
		elseif now - entry.t <= Core.PVE_TTL and (not pveStart or entry.first < pveStart) then
			pveStart = entry.first
		end
	end
	if pveStart then return pveStart, "pve" end
	if start then return start, "timer", est end
end

function Tracker:Prune(now)
	local expired = Core.duration + Core.FORGET_AFTER
	for guid, list in pairs(self.contacts) do
		for partner, entry in pairs(list) do
			if now - entry.t > (entry.pvp and expired or Core.PVE_TTL) then list[partner] = nil end
		end
		if next(list) == nil then self.contacts[guid] = nil end
	end
	for guid, t in pairs(self.suppressedAt) do
		if now - t > Core.SUPPRESS_WINDOW then self.suppressedAt[guid] = nil end
	end
	for guid, t in pairs(self.keep) do
		if now - t > Core.KEEP_MAX then self.keep[guid] = nil end
	end
	for guid, t in pairs(self.deadAt) do
		if now - t > Core.DEATH_CONFIRM then
			self.deadAt[guid] = nil
			self:EndAll(guid)
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

-- `now` is the event's time; missType is the miss type of *_MISSED events.
function Tracker:OnCombatLog(now, eventType, srcGUID, srcFlags, dstGUID, dstFlags, spellId, spellName, missType)
	local kind = eventKinds[eventType]
	if not kind then return end

	if kind == "death" then
		if dstGUID then self:OnDeath(dstGUID, now) end
		return
	end
	if spellId then
		if SUPPRESS[spellId] then
			local who = eventType == "SPELL_CAST_SUCCESS" and srcGUID or dstGUID
			if who and (eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_AURA_APPLIED") then
				self.suppressedAt[who] = now
				self.deadAt[who] = nil -- its UNIT_DIED was a Feign Death
			end
		elseif END_COMBAT[spellId] and eventType == "SPELL_AURA_APPLIED" and dstGUID then
			self:EndAll(dstGUID)
			return
		end
	end

	if not srcGUID or not dstGUID or srcGUID == dstGUID or missType == "EVADE" then return end
	local srcPlayer, dstPlayer = PlayerControlled(srcFlags), PlayerControlled(dstFlags)
	if not srcPlayer and not dstPlayer then return end -- NPCs among themselves

	if kind == "auraRemoved" then
		if Core.combatKeepers[spellName] and self.keep[srcGUID] then
			self.keep[srcGUID] = nil
			self:Contact(srcGUID, dstGUID, now, srcPlayer and dstPlayer)
		end
		return
	end
	if kind == "either" then
		kind = self:IsHostilePair(srcGUID, srcFlags, dstGUID, dstFlags) and "hostile" or "help"
	end

	if kind == "hostile" then
		if eventType == "SPELL_DAMAGE" and Core.ignoredDamageSpells[spellName] then return end
		if NO_AGGRO[spellId] and not self:IsEngaged(dstGUID, now) then return end
		self:Contact(srcGUID, dstGUID, now, srcPlayer and dstPlayer)
		local owner = self.ownerOf[dstGUID]
		if owner and owner ~= srcGUID and engagesOwner[eventType] then
			self:Contact(srcGUID, owner, now, srcPlayer)
		end
		if eventType == "SPELL_AURA_APPLIED" and Core.combatKeepers[spellName] then
			self.keep[srcGUID] = now
		end
	elseif kind == "help" then
		if NO_AGGRO[spellId] or not srcPlayer then return end
		if self:IsEngaged(dstGUID, now) then self:Inherit(srcGUID, dstGUID, now) end
	end
end

------------------------------------------------------------------------
-- Per-icon combat state, fed by the unit's combat flag
------------------------------------------------------------------------

-- Updates `st` ({ guid, inCombat, stale }) for the unit now shown by an icon.
-- Returns "enter" or "leave" on a real change of the same unit, else nil. A new unit, a unit that
-- disappears, a unit that dies and a unit seen again after being out of range (stale) never return
-- a change (no sound for those).
function Core.UpdateCombatState(st, guid, inCombat, dead)
	if guid ~= st.guid or st.stale then
		st.stale = nil
		st.guid = guid
		st.inCombat = guid ~= nil and inCombat and not dead and true or false
		return nil
	end
	if not guid then return nil end

	if dead then
		st.inCombat = false
		return nil
	end
	if inCombat and not st.inCombat then
		st.inCombat = true
		return "enter"
	elseif not inCombat and st.inCombat then
		st.inCombat = false
		return "leave"
	end
	return nil
end

-- Remaining seconds of a timer swipe, or nil.
function Core.SwipeRemaining(start, mode, now)
	if mode ~= "timer" or not start then return nil end
	local left = start + Core.duration - now
	if left > 0 then return left end
end

------------------------------------------------------------------------
-- Duration measurement
------------------------------------------------------------------------

function Core.AddSample(samples, value)
	samples[#samples + 1] = value
	while #samples > Core.MAX_SAMPLES do table.remove(samples, 1) end
end

-- The measured duration, or nil without enough samples.
function Core.EstimateDuration(samples)
	local n = #samples
	if n < Core.MIN_SAMPLES then return nil end
	local sorted = {}
	for i = 1, n do sorted[i] = samples[i] end
	table.sort(sorted)
	return sorted[math.max(1, math.ceil(n * Core.SAMPLE_QUANTILE))]
end

function Core.SetDuration(duration)
	Core.duration = duration or Core.DEFAULT_DURATION
end

------------------------------------------------------------------------
-- Combat log time
------------------------------------------------------------------------

-- The combat log timestamp has millisecond precision and keeps the time an entry was queued, also
-- when the client held it back (it waits for unknown names). Maps it to GetTime(): the largest
-- (timestamp - now) seen is the offset of an event that was not held back.
local clockOffset

function Core.EventTime(timestamp, now)
	if type(timestamp) ~= "number" then return now end
	local offset = timestamp - now
	-- a much smaller offset means the clock was set back
	if not clockOffset or offset > clockOffset or offset < clockOffset - 5 then clockOffset = offset end
	local t = timestamp - clockOffset
	return t < now and t or now
end

function Core.ResetClock()
	clockOffset = nil
end
