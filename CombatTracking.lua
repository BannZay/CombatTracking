-- Icons that show whether units are in combat, with a swipe estimating when they can leave it.
local CT = CombatTracking
local Core = CT.Core
local LSM = LibStub("LibSharedMedia-3.0")

local ICON_SIZE = 40
local TICK = 0.1 -- seconds between unit updates
local CHAT_PREFIX = "|cffFF0084Combat Tracking|r - "

CT.UNITS = {
	"Player", "Target", "Focus",
	"Party1", "Party2", "Party3", "Party4",
	"Arena1", "Arena2", "Arena3", "Arena4", "Arena5",
}

CT.TEXTURES = {
	{ path = "Interface\\Icons\\Ability_Sap", name = "Sap" },
	{ path = "Interface\\Icons\\Ability_DualWield", name = "Dual Wield" },
	{ path = "Interface\\Icons\\Ability_Ambush", name = "Ambush" },
	{ path = "Interface\\Icons\\Ability_Parry", name = "Parry" },
}

CT.SOUND_BELL = "CombatTracking Bell"
CT.SOUND_BEEP = "CombatTracking Beep"
LSM:Register("sound", CT.SOUND_BELL, "Interface\\AddOns\\CombatTracking\\bell.wav")
LSM:Register("sound", CT.SOUND_BEEP, "Interface\\AddOns\\CombatTracking\\beep.mp3")

local function UnitDefaults(enabled, sound, anchor, point, relativePoint, x, y)
	return { enabled = enabled, sound = sound, anchor = anchor, point = point, relativePoint = relativePoint, x = x, y = y }
end

local unitDefaults = {
	Player = UnitDefaults(false, false, "PlayerFrame", "LEFT", "RIGHT", -3, 5),
	Target = UnitDefaults(true, true, "TargetFrame", "LEFT", "RIGHT", -35, 5),
	Focus = UnitDefaults(true, true, "FocusFrame", "LEFT", "RIGHT", -25, 5),
}
for i = 1, 4 do
	unitDefaults["Party" .. i] = UnitDefaults(true, false, "PartyMemberFrame" .. i, "LEFT", "RIGHT", -5, 5)
end
for i = 1, 5 do
	unitDefaults["Arena" .. i] = UnitDefaults(true, true, "UIParent", "TOP", "TOP", (ICON_SIZE + 5) * (i - 3), -40)
end
CT.unitDefaults = unitDefaults

CT.defaults = {
	profile = {
		showText = false,
		scale = 1,
		texture = 1,
		inverted = false,
		inactiveAlpha = 0.2,
		showTimer = false,
		onlyPlayers = true, -- the addon is for PvP
		timerOverride = 0, -- seconds; 0 = measured on the realm
		hidePartyInRaid = true,
		attachToGladius = true,
		playSounds = true,
		enterSound = "None",
		leaveSound = CT.SOUND_BELL,
		playerLeaveSound = CT.SOUND_BEEP,
		units = unitDefaults,
	},
	global = {
		durations = { ["*"] = { samples = {} } }, -- realm -> measured combat timer samples
	},
}

CT.locked = true
CT.testMode = false
CT.icons = {}
CT.iconsByUnit = {}
CT.iconsByToken = {}
CT.playerState = {} -- the player's combat state for measuring, without a Player icon
CT.soundAt = {} -- guid -> time its last sound played
CT.tracker = Core.NewTracker({
	UnitIsEnemy = function(a, b) return UnitIsEnemy(a, b) end,
	UnitAffectingCombat = function(unit) return UnitAffectingCombat(unit) end,
})

function CT:Print(text)
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. text)
end

------------------------------------------------------------------------
-- Saved settings
------------------------------------------------------------------------

-- Copies settings saved by versions before 3.0 (no AceDB) into `profile`.
function CT.MigrateLegacy(old, profile)
	local s = old.Settings or {}
	local map = {
		showTextAlways = "showText", scale = "scale", textureId = "texture",
		inverted = "inverted", playSounds = "playSounds", attachedToGladius = "attachToGladius",
	}
	for oldKey, newKey in pairs(map) do
		if s[oldKey] ~= nil then profile[newKey] = s[oldKey] end
	end

	for _, unit in ipairs(CT.UNITS) do
		local info = old[unit]
		if type(info) == "table" then
			local u = profile.units[unit]
			if info.hidden ~= nil then u.enabled = not info.hidden end
			if info.useSound ~= nil then u.sound = info.useSound end
			local pos = info.position
			if type(pos) == "table" and pos.point and pos.xOfs and pos.yOfs then
				u.point = strupper(pos.point)
				if pos.relativePoint then
					u.relativePoint = strupper(pos.relativePoint) -- relative to the default anchor frame
				else
					u.anchor = "UIParent" -- was anchored to the screen
					u.relativePoint = u.point
				end
				u.x, u.y = pos.xOfs, pos.yOfs
			end
		end
	end
end

function CT:InitDB()
	local legacy = CombatTrackingDB
	if type(legacy) == "table" and legacy.profileKeys == nil and next(legacy) ~= nil then
		CombatTrackingDB = nil
	else
		legacy = nil
	end

	self.db = LibStub("AceDB-3.0"):New("CombatTrackingDB", CT.defaults, true)
	if legacy then
		CT.MigrateLegacy(legacy, self.db.profile)
	end

	self:ApplyDuration()

	local function OnProfileChanged()
		CT:ApplyDuration()
		CT:ApplySettings()
	end
	self.db.RegisterCallback(self, "OnProfileChanged", OnProfileChanged)
	self.db.RegisterCallback(self, "OnProfileCopied", OnProfileChanged)
	self.db.RegisterCallback(self, "OnProfileReset", OnProfileChanged)
end

------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------

-- Icons are not children of UIParent (that breaks addons such as MoveAnything), so they follow its
-- visibility through this container.
local container = CreateFrame("Frame", "CombatTrackingContainer")
container:SetFrameStrata("MEDIUM")
UIParent:HookScript("OnShow", function() container:Show() end)
UIParent:HookScript("OnHide", function() container:Hide() end)

local function Icon_OnMouseDown(icon, button)
	if button == "LeftButton" then
		if not CT:GetGladiusButton(icon) then
			icon:StartMoving()
			icon.moving = true
		end
	elseif button == "RightButton" then
		local u = CT.db.profile.units[icon.unit]
		if IsControlKeyDown() then
			u.sound = not u.sound
		else
			u.enabled = not u.enabled
		end
		CT:UpdateIconDisplay(icon)
		CT:NotifyOptionsChanged()
	end
end

local function Icon_OnMouseUp(icon, button)
	if button == "LeftButton" and icon.moving then
		icon:StopMovingOrSizing()
		icon.moving = nil
		CT:SavePosition(icon)
	end
end

local function Icon_OnEnter(icon)
	GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
	GameTooltip:AddLine(icon.unit)
	GameTooltip:AddLine("Left drag - move", 1, 1, 1)
	GameTooltip:AddLine("Right click - enable / disable", 1, 1, 1)
	GameTooltip:AddLine("Ctrl + right click - sound on / off", 1, 1, 1)
	GameTooltip:Show()
end

local function Icon_OnLeave()
	GameTooltip:Hide()
end

local function CreateText(parent, size)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont("Fonts\\ARIALN.TTF", size, "OUTLINE")
	return text
end

local function CreateIcon(unit, index)
	local icon = CreateFrame("Frame", "CombatTracking" .. unit .. "Frame", container)
	icon.unit = unit
	icon.token = strlower(unit)
	icon.index = index
	icon.arenaIndex = tonumber(unit:match("^Arena(%d)$"))
	icon.isParty = unit:find("^Party") ~= nil
	icon.state = {}

	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetFrameStrata("MEDIUM")
	icon:SetFrameLevel(30)
	icon:SetMovable(true)
	icon:SetClampedToScreen(true)
	icon:SetScript("OnMouseDown", Icon_OnMouseDown)
	icon:SetScript("OnMouseUp", Icon_OnMouseUp)
	icon:SetScript("OnEnter", Icon_OnEnter)
	icon:SetScript("OnLeave", Icon_OnLeave)

	icon.texture = icon:CreateTexture(nil, "BORDER")
	icon.texture:SetAllPoints()

	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints()

	-- texts above the swipe
	local overlay = CreateFrame("Frame", nil, icon)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
	icon.overlay = overlay

	icon.label = CreateText(overlay, 10)
	icon.label:SetPoint("CENTER", 0, 3)
	icon.label:SetText(unit)

	icon.status = CreateText(overlay, 10)
	icon.status:SetPoint("CENTER", 0, -6)

	icon.timer = CreateText(overlay, 16)
	icon.timer:SetPoint("BOTTOM", 0, 1)

	return icon
end

function CT:CreateIcons()
	for index, unit in ipairs(CT.UNITS) do
		local icon = CreateIcon(unit, index)
		self.icons[index] = icon
		self.iconsByUnit[unit] = icon
		self.iconsByToken[icon.token] = icon
	end
end

------------------------------------------------------------------------
-- Positions
------------------------------------------------------------------------

function CT:GetAnchorFrame(icon, name)
	local frame = name and _G[name]
	if type(frame) == "table" and type(frame.GetObjectType) == "function" and frame ~= icon and frame.GetCenter then
		return frame
	end
	return UIParent
end

function CT:ApplyPosition(icon)
	icon:ClearAllPoints()
	local button = self:GetGladiusButton(icon)
	if button then
		icon:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, 0)
		return
	end
	local u = self.db.profile.units[icon.unit]
	icon:SetPoint(u.point, self:GetAnchorFrame(icon, u.anchor), u.relativePoint, u.x, u.y)
end

-- Saves where the icon is now, as an offset from the center of its anchor frame, so it keeps
-- following that frame.
function CT:SavePosition(icon)
	local u = self.db.profile.units[icon.unit]
	local anchor = self:GetAnchorFrame(icon, u.anchor)
	local ix, iy = icon:GetCenter()
	local ax, ay = anchor:GetCenter()
	if not ax then
		anchor = UIParent
		ax, ay = anchor:GetCenter()
	end
	local ratio = anchor:GetEffectiveScale() / icon:GetEffectiveScale()
	u.point, u.relativePoint = "CENTER", "CENTER"
	u.x, u.y = ix - ax * ratio, iy - ay * ratio
	self:ApplyPosition(icon)
end

function CT:ResetPosition(unit)
	local u, d = self.db.profile.units[unit], unitDefaults[unit]
	u.anchor, u.point, u.relativePoint, u.x, u.y = d.anchor, d.point, d.relativePoint, d.x, d.y
	self:ApplyPosition(self.iconsByUnit[unit])
end

------------------------------------------------------------------------
-- Gladius
------------------------------------------------------------------------

function CT:GetGladiusButton(icon)
	return icon.arenaIndex and self.db.profile.attachToGladius and icon.gladiusButton or nil
end

-- Moves a Gladius part that is attached to the left of the button out of the icon's way, once.
local function ShiftGladiusPart(part, button, width)
	if not part or not part:IsVisible() then return end
	for i = 1, part:GetNumPoints() do
		local point, relativeTo, relativePoint, x, y = part:GetPoint(i)
		if relativeTo == button and relativePoint and relativePoint:find("LEFT") then
			if x ~= part.combatTrackingX then -- not shifted yet, or Gladius anchored it again
				local newX = x - width
				part:ClearAllPoints()
				part:SetPoint(point, relativeTo, relativePoint, newX, y)
				part.combatTrackingX = newX
			end
			return
		end
	end
end

function CT:OnGladiusUpdate()
	local bracket = Gladius.currentBracket or 0
	for i = 1, 5 do
		local icon = self.iconsByUnit["Arena" .. i]
		icon.gladiusButton = i <= bracket and _G["GladiusButtonFrame" .. i] or nil
		self:ApplyPosition(icon)
		local button = self:GetGladiusButton(icon)
		if button then
			local width = ICON_SIZE * icon:GetEffectiveScale() / button:GetEffectiveScale() + 5
			ShiftGladiusPart(button.castBar, button, width)
			ShiftGladiusPart(button.spellCooldownFrame, button, width)
			ShiftGladiusPart(button.drCooldownFrame, button, width)
		end
	end
end

function CT:HookGladius()
	if self.gladiusHooked or not (Gladius and Gladius.UpdateFrame) then return end
	self.gladiusHooked = true
	hooksecurefunc(Gladius, "UpdateFrame", function() CT:OnGladiusUpdate() end)
end

-- Shows the Gladius test frames while the icons are unlocked or in test mode, so arena icons can be
-- seen next to them.
function CT:UpdateGladiusVisibility()
	local show = not self.locked or self.testMode
	if not (Gladius and self.db.profile.attachToGladius) then return end
	if select(2, IsInInstance()) == "arena" then return end -- Gladius would not appear in the next match
	local visible = Gladius.frame ~= nil and Gladius.frame:IsShown()
	if show and not visible then
		Gladius:ToggleFrame(5)
	elseif not show and visible then
		Gladius:HideFrame()
	end
end

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------

function CT:PlaySound(name)
	if name and name ~= "None" then
		local path = LSM:Fetch("sound", name, true)
		if path then PlaySoundFile(path) end
	end
end

-- mode "timer" counts down Core.duration; "pve" and "keep" show a full swipe without an end
local function SetSwipe(icon, start, mode)
	local duration = mode == "timer" and Core.duration or Core.KEEP_DURATION
	if start == icon.shownStart and mode == icon.shownMode and duration == icon.shownDuration then return end
	icon.shownStart, icon.shownMode, icon.shownDuration = start, mode, duration
	if start then
		CooldownFrame_SetTimer(icon.cooldown, start, duration, 1)
	else
		CooldownFrame_SetTimer(icon.cooldown, 0, 0, 0)
	end
end

-- A unit still in combat well after its timer ran out had a contact we did not see (out of combat
-- log range): its timer is unknown.
local OVERDUE = 0.5

local function SetTimer(icon, start, mode, now)
	if not CT.db.profile.showTimer then
		icon.timer:SetText("")
		return
	end
	local left = Core.SwipeRemaining(start, mode, now)
	if left then
		icon.timer:SetText(format("%.0f", math.ceil(left)))
	elseif mode == "timer" and now > start + Core.duration + OVERDUE then
		icon.timer:SetText("?")
	else
		icon.timer:SetText("")
	end
end

------------------------------------------------------------------------
-- Combat timer duration, measured per realm
------------------------------------------------------------------------

function CT:GetDurationSamples()
	return self.db.global.durations[GetRealmName() or "?"].samples
end

-- Uses the manual duration, else the one measured on this realm, else the server default.
function CT:ApplyDuration()
	local override = self.db.profile.timerOverride
	if override and override > 0 then
		Core.SetDuration(override)
	else
		Core.SetDuration(Core.EstimateDuration(self:GetDurationSamples()))
	end
end

function CT:AddDurationSample(seconds)
	Core.AddSample(self:GetDurationSamples(), seconds)
	self:ApplyDuration()
end

function CT:ResetDurationSamples()
	local samples = self:GetDurationSamples()
	for i = #samples, 1, -1 do samples[i] = nil end
	self:ApplyDuration()
end

-- Texts, alpha and mouse handling that depend on the settings, not on the unit.
function CT:UpdateIconDisplay(icon)
	local p = self.db.profile
	local u = p.units[icon.unit]
	icon:SetScale(p.scale)
	local texture = CT.TEXTURES[p.texture] or CT.TEXTURES[1]
	icon.texture:SetTexture(texture.path)
	icon:EnableMouse(not self.locked)

	if self.locked then
		if p.showText then icon.label:Show() else icon.label:Hide() end
		icon.status:Hide()
	else
		icon.label:Show()
		icon.status:Show()
		icon.status:SetText(not u.enabled and "(disabled)" or not u.sound and "(no sound)" or "")
		icon.texture:SetAlpha(u.enabled and 1 or 0.2)
		icon.timer:SetText("")
		SetSwipe(icon, nil)
		icon:Show()
	end
end

-- Whether the icon tracks its unit right now; the unit's GUID if so.
function CT:GetTrackedGUID(icon)
	local p = self.db.profile
	local token = icon.token
	if not p.units[icon.unit].enabled
		or not UnitExists(token)
		or not UnitIsConnected(token)
		or (icon.isParty and p.hidePartyInRaid and GetNumRaidMembers() > 0)
		or (p.onlyPlayers and not UnitIsPlayer(token)) then
		return nil
	end
	return UnitGUID(token)
end

-- Bright when the icon's state is the one the user watches for: out of combat (for example "can be
-- sapped"), or in combat with the inverted setting.
local function SetActive(icon, active)
	icon.texture:SetAlpha(active and 1 or CT.db.profile.inactiveAlpha)
end

-- Feeds a unit's combat flag to its state and the tracker; returns "enter", "leave" or nil.
-- `precise`: called from UNIT_FLAGS, at the moment the combat flag changed.
function CT:TrackCombat(state, guid, token, dead, now, precise)
	local change = Core.UpdateCombatState(state, guid, guid and UnitAffectingCombat(token), dead)
	if change == "enter" then
		self.tracker:OnEnter(guid, now)
	elseif change == "leave" then
		local sample = self.tracker:OnLeave(guid, now)
		if sample and precise then self:AddDurationSample(sample) end
	end
	return change
end

-- One sound per unit and change, also when several icons show the unit (target and arena1): each
-- icon gets its own UNIT_FLAGS, a few milliseconds apart.
local SOUND_DEDUPE = 0.25

function CT:ClaimSound(guid, now)
	local last = self.soundAt[guid]
	if last and now - last < SOUND_DEDUPE then return false end
	self.soundAt[guid] = now
	return true
end

-- The player's own combat is the best measurement of the combat timer (all of its contacts are in
-- the combat log), so it is followed even without a Player icon.
function CT:MeasurePlayer(now, precise)
	if self.iconsByUnit.Player.state.guid then -- the Player icon follows it
		self.playerState.stale = true
		return
	end
	local guid = UnitGUID("player")
	self.tracker:SetTracked(guid, "player")
	self:TrackCombat(self.playerState, guid, "player", UnitHealth("player") == 0 or UnitIsGhost("player"), now, precise)
end

function CT:UpdateIcon(icon, now, precise)
	local p = self.db.profile
	local token = icon.token
	local tracker = self.tracker
	local guid = self:GetTrackedGUID(icon)
	if guid then tracker:SetTracked(guid, token) end

	-- A unit out of the client's range (a far party member) has no combat flag: keep its last state
	-- and pick up the current one silently when it is back.
	if guid and guid == icon.state.guid and not UnitIsVisible(token) then
		icon.state.stale = true
		icon:Show()
		SetActive(icon, false)
		SetSwipe(icon, nil)
		icon.timer:SetText("?")
		return
	end

	-- Health, not UnitIsDeadOrGhost: a hunter in Feign Death has the "dead" flag but is alive (and out
	-- of combat). UnitIsDead also fails at range.
	local dead = guid and (UnitHealth(token) == 0 or UnitIsGhost(token))
	local change = self:TrackCombat(icon.state, guid, token, dead, now, precise)
	if change and p.playSounds and p.units[icon.unit].sound and self:ClaimSound(guid, now) then
		if change == "enter" then
			self:PlaySound(p.enterSound)
		else
			self:PlaySound(icon.unit == "Player" and p.playerLeaveSound or p.leaveSound)
		end
	end

	if not guid then
		icon:Hide()
		return
	end
	icon:Show()
	SetActive(icon, not dead and (icon.state.inCombat == p.inverted))

	local start, mode
	if icon.state.inCombat then
		start, mode = tracker:GetSwipe(guid, now)
	end
	SetSwipe(icon, start, mode)
	SetTimer(icon, start, mode, now)
end

-- Test mode: every enabled icon is shown, every second one in combat with a running swipe.
function CT:UpdateTestIcon(icon, now)
	if not self.db.profile.units[icon.unit].enabled then
		icon:Hide()
		return
	end
	icon:Show()
	local inCombat = icon.index % 2 == 0
	SetActive(icon, inCombat == self.db.profile.inverted)
	local start
	if inCombat then
		local period = Core.duration + 1
		start = now - (now + icon.index) % period
	end
	SetSwipe(icon, start, start and "timer")
	SetTimer(icon, start, "timer", now)
end

-- Pet -> owner from the unit tokens; attacking a pet puts its owner in combat too.
local petTokens = { { "pet", "player" } }
for i = 1, 4 do petTokens[#petTokens + 1] = { "partypet" .. i, "party" .. i } end
for i = 1, 5 do petTokens[#petTokens + 1] = { "arenapet" .. i, "arena" .. i } end
for i = 1, 40 do petTokens[#petTokens + 1] = { "raidpet" .. i, "raid" .. i } end

function CT:UpdateOwners()
	local ownerOf = {}
	local raidMembers = GetNumRaidMembers()
	for i, pair in ipairs(petTokens) do
		if i > 10 + raidMembers then break end
		local pet = UnitGUID(pair[1])
		if pet then ownerOf[pet] = UnitGUID(pair[2]) end
	end
	self.tracker:SetOwners(ownerOf)
end

-- Updates all icons from their units. Runs every TICK and on unit changes.
function CT:Refresh()
	if not self.db or not self.icons[1] or not self.locked then return end
	local now = GetTime()
	if self.testMode then
		for _, icon in ipairs(self.icons) do self:UpdateTestIcon(icon, now) end
		return
	end
	self.tracker:ClearTracked()
	for _, icon in ipairs(self.icons) do
		self:UpdateIcon(icon, now)
	end
	self:MeasurePlayer(now)
	if now - (self.lastPrune or 0) >= 1 then
		self.lastPrune = now
		self.tracker:Prune(now)
		self:UpdateOwners()
		for guid, t in pairs(self.soundAt) do
			if now - t > 1 then self.soundAt[guid] = nil end
		end
	end
end

-- The combat flag of a unit changed: update its icon at once, so leaving combat is seen exactly.
function CT:OnUnitFlags(unit)
	if not self.db or not self.icons[1] or not self.locked or self.testMode then return end
	local icon = self.iconsByToken[unit]
	if icon then self:UpdateIcon(icon, GetTime(), true) end
	if unit == "player" then self:MeasurePlayer(GetTime(), true) end
end

-- Re-applies every setting to the icons (after an option or profile change).
function CT:ApplySettings()
	if not self.icons[1] then return end
	for _, icon in ipairs(self.icons) do
		icon.state = {} -- a fresh start: no sounds for what changed meanwhile
		self:ApplyPosition(icon)
		self:UpdateIconDisplay(icon)
	end
	self:Refresh()
end

function CT:SetLocked(locked)
	self.locked = locked and true or false
	if not self.locked then self.testMode = false end
	self:UpdateGladiusVisibility()
	self:ApplySettings()
	self:NotifyOptionsChanged()
end

function CT:SetTestMode(on)
	self.testMode = on and true or false
	if self.testMode then self.locked = true end
	self:UpdateGladiusVisibility()
	self:ApplySettings()
	self:NotifyOptionsChanged()
end

function CT:NotifyOptionsChanged()
	LibStub("AceConfigRegistry-3.0"):NotifyChange("CombatTracking")
end

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------

function CT:OpenOptions()
	-- the first call in a session only opens the frame on the wrong panel
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
end

function CT:HandleSlashCommand(cmd)
	cmd = strlower(strtrim(cmd or ""))
	if cmd == "lock" or cmd == "unlock" then
		self:SetLocked(not self.locked)
		self:Print(self.locked and "icons locked" or "icons unlocked: drag to move, right click to disable")
	elseif cmd == "test" then
		self:SetTestMode(not self.testMode)
		self:Print(self.testMode and "test mode on" or "test mode off")
	elseif cmd == "reset" then
		self.db:ResetProfile()
		self:Print("profile reset to defaults")
	elseif cmd == "" then
		self:OpenOptions()
	else
		self:Print("/ct - options, /ct lock - lock / unlock icons, /ct test - test mode, /ct reset - reset profile")
	end
end

SLASH_COMBATTRACKING1 = "/ct"
SLASH_COMBATTRACKING2 = "/combattracking"
SlashCmdList["COMBATTRACKING"] = function(cmd) CT:HandleSlashCommand(cmd) end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local NO_GUID = "0x0000000000000000" -- the combat log's GUID of "no unit"
local driver = CreateFrame("Frame")
local sinceTick = 0

local function OnUpdate(_, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		sinceTick = 0
		CT:Refresh()
	end
end

local function RefreshNow() CT:Refresh() end

local events = {
	ADDON_LOADED = function(name)
		if name == "CombatTracking" then
			CT:InitDB()
			CT:RegisterOptions()
		elseif name == "Gladius" and CT.icons[1] then
			CT:HookGladius()
		end
	end,
	PLAYER_LOGIN = function()
		Core.BuildSpellSets()
		CT:CreateIcons()
		CT:HookGladius()
		CT:ApplySettings()
		driver:SetScript("OnUpdate", OnUpdate)
	end,
	COMBAT_LOG_EVENT_UNFILTERED = function(timestamp, eventType, srcGUID, _, srcFlags, dstGUID, _, dstFlags, a9, a10, _, a12)
		if not Core.Classify(eventType) then return end
		local spellId, spellName, missType
		if eventType == "SWING_MISSED" then
			missType = a9
		elseif eventType ~= "SWING_DAMAGE" and type(a9) == "number" then
			spellId, spellName = a9, a10
			if eventType == "SPELL_MISSED" or eventType == "RANGE_MISSED" then missType = a12 end
		end
		if srcGUID == NO_GUID then srcGUID = nil end
		if dstGUID == NO_GUID then dstGUID = nil end
		CT.tracker:OnCombatLog(Core.EventTime(timestamp, GetTime()), eventType, srcGUID, srcFlags, dstGUID, dstFlags,
			spellId, spellName, missType)
	end,
	UNIT_FLAGS = function(unit) CT:OnUnitFlags(unit) end,
	PLAYER_TARGET_CHANGED = RefreshNow,
	PLAYER_FOCUS_CHANGED = RefreshNow,
	PARTY_MEMBERS_CHANGED = function()
		CT:UpdateOwners()
		CT:Refresh()
	end,
	ARENA_OPPONENT_UPDATE = function()
		CT:UpdateOwners()
		CT:Refresh()
	end,
	UNIT_PET = function() CT:UpdateOwners() end,
	PLAYER_ENTERING_WORLD = function()
		Core.ResetClock()
		CT:Refresh()
	end,
}

for event in pairs(events) do driver:RegisterEvent(event) end
driver:SetScript("OnEvent", function(_, event, ...) events[event](...) end)
