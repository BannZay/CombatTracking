local Setting_Lock 				= "lock"
local Setting_ShowTextAlways 	= "showTextAlways"
local Setting_Scale 			= "scale"
local Setting_TextureId 		= "textureId"
local Setting_Inverted 			= "inverted"
local Setting_PlaySounds 		= "playSounds"
local Setting_AttachedToGladius = "attachedToGladius"

CombatTrackingDB = nil
local Settings = nil

local ctFrames = {}
local textureSize = 40

local ctToolTipText =
{
	"Left click - drag frame",
	"Right click - toggle hide option",
	"Right click with control - toggle sound option",
}

local targetsDefaultSettings =
{
	["Player"] = 
	{
		position = {point = "Left", xOfs = -3, yOfs = 5, parentFrame = PlayerFrame, relativePoint = "Right"},
		useSound = false,
		hidden = true
	},
	["Target"] = 
	{
		position = {point = "Left", xOfs = -35, yOfs = 5, parentFrame = TargetFrame, relativePoint = "Right"},
		useSound = true
	},
	["Focus"] = 
	{
		position = {point = "Left", xOfs = -25, yOfs = 5, parentFrame = FocusFrame, relativePoint = "Right"},
		useSound = true
	},
	["Party1"] = 
	{
		position = {point = "Left", xOfs = -5, yOfs = 5, parentFrame = PartyMemberFrame1, relativePoint = "Right"},
		useSound = false
	},
	["Party2"] = 
	{
		position = {point = "Left", xOfs = -5, yOfs = 5, parentFrame = PartyMemberFrame2, relativePoint = "Right"},
		useSound = false
	},
	["Party3"] = 
	{
		position = {point = "Left", xOfs = -5, yOfs = 5, parentFrame = PartyMemberFrame3, relativePoint = "Right"},
		useSound = false
	},
	["Party4"] = 
	{
		position = {point = "Left", xOfs = -5, yOfs = 5, parentFrame = PartyMemberFrame4, relativePoint = "Right"},
		useSound = false
	},
	["Arena1"] = 
	{
		position = {point = "TOP", xOfs = (textureSize + 5) * -2, yOfs = 0},
		parentFrame = nil, useSound = true
	},
	["Arena2"] = 
	{
		position = {point = "TOP", xOfs = (textureSize + 5) * -1, yOfs = 0},
		parentFrame = nil, useSound = true
	},
	["Arena3"] = 
	{
		position = {point = "TOP", xOfs = (textureSize + 5) * 0, yOfs = 0},
		parentFrame = nil, useSound = true
		},
	["Arena4"] = 
	{
		position = {point = "TOP", xOfs = (textureSize + 5) * 1, yOfs = 0},
		parentFrame = nil, useSound = true
	},
	["Arena5"] = 
	{
		position = {point = "TOP", xOfs = (textureSize + 5) * 2, yOfs = 0},
		parentFrame = nil, useSound = true
	},
}

local textures =
{
	"Interface\\Icons\\ability_sap",
	"Interface\\Icons\\ABILITY_DUALWIELD",
	"Interface\\Icons\\ability_ambush",
	"Interface\\Icons\\ability_parry",
}


-------------------------------- General --------------------------------


function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function CompareIgnoreCase(str1, str2)
	return string.upper(str1) == string.upper(str2)
end

local function Find(tbl, filter)
	for index, value in pairs(tbl) do
		if (filter(value, index) == true) then
			return value, index
		end
	end
end

local function BooleanToString(bool)
	if bool then
		return "true"
	else 
		return "false"
	end
end

local function Switch(value, ifTrue, ifFalse)
	if (value) then
		return ifTrue
	else
		return ifFalse
	end
end


---------------------------------------------------------------- DB settings ----------------------------------------------------------------


local function SetSetting(settingName, value)
	Settings[settingName] = value
end

local function InitSetting(settingName, defaultValue)
	local setting2 = Settings[settingName]
	if (setting2 == nil) then
		SetSetting(settingName, defaultValue)
	end
	
	return Settings[settingName]
end


---------------------------------------------------------------- Printing ----------------------------------------------------------------


local function Print(text)
	ChatFrame1:AddMessage(string.format("%s", text), 10, 20, 0)
end

local function PrintMessage(text)
	Print(string.format("|cffFF0084Combat Tracking|r - %s", text))
end


---------------------------------------------------------------- Frame settings ----------------------------------------------------------------


local function GetFrameByTarget(targetType)
	return Find(ctFrames, function(x) return x.TargetType == targetType end)
end

local function SetFrameUseSound(frame, value)
	frame.useSound = value
	
	if (value) then
		frame.musicText:SetText(nil)
	else
		frame.musicText:SetText("(no sound)")
	end
end

local function GetFrameUseSound(frame)
	return frame.useSound
end

local function SetFrameHidden(frame, value)
	frame.CTHidden = value
	
	if value then
		frame.t:SetAlpha(0.2)
	else
		frame.t:SetAlpha(1)
	end
	
	SetFrameUseSound(frame, not value)
end

local function GetFrameHidden(frame)
	return frame.CTHidden == true
end

local function SetVisibility(target, value)
	if target ~= nil then
		if value then 
			target:Show()
		else
			target:Hide()
		end
	end
end

local function SetFramesTexture(textureId)
	local texture = textures[textureId]
	
	if (texture ~= nil) then
		for i = 1, #ctFrames do
			ctFrames[i].t:SetTexture(texture)
		end
	else
		SetFramesTexture(1)
	end
end


---------------------------------------------------------------- Gladius ----------------------------------------------------------------


local function ShowGladius(value)
	if Gladius ~= nil then
		local gladiusIsVisible = Gladius.frame ~= nil and Gladius.frame:IsShown()
		
		if value and not gladiusIsVisible then
			Gladius:ToggleFrame(5)
		elseif not value and gladiusIsVisible then
			Gladius:HideFrame()
		end
	end
end

local function GladiusFrameAppeared(arg1)
	for i=1,5 do
		local gladiusButtonFrame = _G["GladiusButtonFrame"..i]
		local f = GetFrameByTarget("Arena"..i)
		if (gladiusButtonFrame ~= nil) then
		
			-- Setup our frame
			f:ClearAllPoints()
			local size = gladiusButtonFrame.classIcon:GetHeight() 
			f:SetPoint("TopRight",gladiusButtonFrame , "TopLeft", -4, 0)
			f:SetWidth(size)
			f:SetHeight(size)
			f:SetScale(Gladius.frame:GetScale())
			f.t:SetAllPoints()
			
			-- move Gladius dr frame to prevent overlapping
			local drFrame = gladiusButtonFrame.drCooldownFrame
			if drFrame and drFrame:GetNumPoints() == 1 then -- if numpoints != 1 unknown gladius used, dont touch it then
				local point, relativeTo, relativePoint, xOfs, yOfs = gladiusButtonFrame.drCooldownFrame:GetPoint(1)
				if (string.sub(relativePoint,-4) == "LEFT") then
					drFrame:ClearAllPoints()
					drFrame:SetPoint("TopRight", f, "TopLeft")
				end
			end
			
			SetVisibility(f, arg1)
		end
	end
end

local function OnGladiusFrameAppeared(arg1)
	if Settings[Setting_AttachedToGladius] then
		local status, err = pcall(function() GladiusFrameAppeared(arg1) end)
		if not status then
			PrintMessage("This version of Gladius is not supported for integration yet")
		end
	end
end


---------------------------------------------------------------- Frames management ----------------------------------------------------------------


local function SaveFrame(item)
	if item ~= nil then
		local target = item.TargetType
		local point, relativeTo, relativePoint, xOfs, yOfs = item:GetPoint(n)
	
		local frameInfo = Settings[target] or {}
		
		frameInfo.position =
		{
			xOfs = xOfs,
			yOfs = yOfs,
			point = point,
			relativePoint = nil,
		}
		
		if (relativeTo ~= nil) then
			local parentFrameInfo = Find(targetsDefaultSettings, function(x) return x.position.parentFrame == relativeTo end)
			
			if parentFrameInfo ~= nil then
				frameInfo.position.point = "Left"
				frameInfo.position.relativePoint = relativePoint
			end
		end
		
		frameInfo.hidden = GetFrameHidden(item)
		frameInfo.useSound = GetFrameUseSound(item)
		
		CombatTrackingDB[target] = frameInfo
	end
end

local function OnMouseDown(self,button)
	if button == "LeftButton" then
		if (string.sub(self.TargetType, 0, 5) ~= "Arena" or not Settings[Setting_AttachedToGladius]) then
			self:StartMoving()
		end
	elseif button == "RightButton" then
		if (IsLeftControlKeyDown()) then
			if (not GetFrameHidden(self)) then
				SetFrameUseSound(self, not GetFrameUseSound(self))
				SaveFrame(self)
			end
		else
			local frame = GetFrameByTarget(self.TargetType)
			SetFrameHidden(frame, not GetFrameHidden(frame))
			SaveFrame(frame)
		end
	end
end

function OnEnterTippedButton(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	
	for k,v in pairs(self.tooltipTextLines) do
		GameTooltip:AddLine(v)
	end
	
	GameTooltip:Show()
end

function OnLeaveTippedButton()
	GameTooltip_Hide()
end

function SetTooltip(self, textLines)
	if textLines then
		self.tooltipTextLines = textLines
		self:SetScript("OnEnter", OnEnterTippedButton)
		self:SetScript("OnLeave", OnLeaveTippedButton)
	else
		self:SetScript("OnEnter", nil)
		self:SetScript("OnLeave", nil)
	end
end

local function CreateCTFrame(target)
	local frame = CreateFrame("Frame", "CombatTracking" .. target .. "frame")
	frame.New = true
	frame:SetSize(textureSize, textureSize)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(30)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnMouseDown", OnMouseDown)
	frame:SetScript("OnMouseUp",function(self,button) if button == "LeftButton" then self:StopMovingOrSizing() SaveFrame(self) end end)
	frame:Hide()
	
	frame.t=frame:CreateTexture(nil,BORDER)
	frame.t:SetTexture(textures[Settings[Setting_TextureId]])
	frame:SetScale(Settings[Setting_Scale])
	
	local targetText = frame:CreateFontString(nil,"ARTWORK")
	targetText:SetFont("Fonts\\ARIALN.ttf", 10, "OUTLINE")
	targetText:SetPoint("CENTER",0,3)
	targetText:SetText(target)
	targetText:Hide()
	frame.targetText = targetText
	
	local musicText = frame:CreateFontString(nil,"ARTWORK")
	musicText:SetFont("Fonts\\ARIALN.ttf", 10, "OUTLINE")
	musicText:SetPoint("CENTER",0, -6)
	musicText:SetText("(no sound)")
	musicText:Hide()
	frame.musicText = musicText
	
	SetTooltip(frame, ctToolTipText)
	
	local frameDefaultSettings = Find(targetsDefaultSettings, function(x, i) return i == target end)
	
	frame.TargetType = target
	
	return frame
end

local function ConfigureFrame(frame, useSound, hidden, position)
	frame:ClearAllPoints()
	frame:SetParent(nil)
	
	if (position.relativePoint ~= nil) then
		frame:SetPoint(position.point, position.parentFrame, position.relativePoint, position.xOfs, position.yOfs)
	else
		frame:SetPoint(position.point, position.xOfs, position.yOfs)
	end
	
	frame.t:SetAllPoints()
	
	SetFrameHidden(frame, hidden)
	SetFrameUseSound(frame, useSound and not GetFrameHidden(frame))
	
	return frame
end

local function ApplyDefaultSettingsToFrame(frame)
	local parentFrameInfo = Find(targetsDefaultSettings, function(value, index) return CompareIgnoreCase(index, frame.TargetType) end)
	ConfigureFrame(frame, parentFrameInfo.useSound, parentFrameInfo.hidden, parentFrameInfo.position)
	return frame
end

local function LoadFrame(itemName, existingFrame)
	local fi  = CombatTrackingDB[itemName]
	local frame = existingFrame or CreateCTFrame(itemName)
	
	
	if (fi ~= nil and fi.position ~= nil) then
		
		local position = fi.position
		if (position.relativePoint) then -- we need to provide struct with parent frame
			position = shallowcopy(fi.position)
			position.parentFrame = Find(targetsDefaultSettings, function(x, index) return index == frame.TargetType end).position.parentFrame
		end
		
		ConfigureFrame(frame, fi.useSound, fi.hidden, position)
	else
		ApplyDefaultSettingsToFrame(frame, true)
	end
	
	return frame
end

local function SetTextVisibility(targetVisibility, musicVisibility)
	for i = 1, #ctFrames do
		SetVisibility(ctFrames[i].targetText, targetVisibility)
		SetVisibility(ctFrames[i].musicText, musicVisibility)
	end
end

local function SetLock(value, doNotReloadGladius)
	
	if doNotReloadGladius ~= true then
		if Settings[Setting_AttachedToGladius] then
			ShowGladius(not value)
		end
	end
	
	for i = 1, #ctFrames do
		local frame = ctFrames[i]
		
		frame:EnableMouse(not value)
		
		SetVisibility(frame, not value)
	end
	
	if (value) then
		SetTextVisibility(Settings[Setting_ShowTextAlway], false)
	else
		SetTextVisibility(true, true)
	end
end


---------------------------------------------------------------- Initialization ----------------------------------------------------------------


local function UpdateItem(target)
	for i = 1, #ctFrames do 
		local itemToUpdate = ctFrames[i]
		if (itemToUpdate.TargetType == target) then
			table.remove(ctFrames, i)
			itemToUpdate:Hide()
			break
		end
	end

	table.insert(ctFrames, target)
end

local function Init()
	CombatTrackingDB = CombatTrackingDB or {Settings = {}}
	
	if CombatTrackingDB.Settings == nil then 
		CombatTrackingDB.Settings = {}
	end
	
	Settings = CombatTrackingDB.Settings
	
	SetSetting(Setting_Lock, true)
	InitSetting(Setting_ShowTextAlways, false)
	InitSetting(Setting_Scale, 1)
	InitSetting(Setting_TextureId, 1)
	InitSetting(Setting_Inverted, false)
	InitSetting(Setting_PlaySounds, true)
	InitSetting(Setting_AttachedToGladius, true)
	
	for targetName, frameInfo in pairs(targetsDefaultSettings) do
		local parentFrame = frameInfo.parentFrame
		local item = LoadFrame(targetName)
		UpdateItem(item)
	end
	
	if IsAddOnLoaded("Gladius") then
		hooksecurefunc(Gladius, "JoinedArena", OnGladiusFrameAppeared)
		hooksecurefunc(Gladius, "ToggleFrame", OnGladiusFrameAppeared) -- '/gladius test' triggers this method
	end
	
	SetLock(Settings[Setting_Lock], true)
end


---------------------------------------------------------------- Blizzard options menu ----------------------------------------------------------------


local function Reset()
	CombatTrackingDB = {}
	
	local oldFrames = ctFrames
	ctFrames = {}
	
	for i = 1, #oldFrames do
		SetFrameHidden(oldFrames[i], true)
		oldFrames[i]:Hide()
	end
	
	Init()
end

local function SetFramesScale(scale)
	for i = 1, #ctFrames do
		local ctFrame = ctFrames[i]
		ctFrame:SetScale(scale)
	end
end

local function AttachedToGladiusChanged(value)
	for i =1,5 do
		local f = GetFrameByTarget("Arena"..i)
		
		if (not value) then
			LoadFrame(f.TargetType, f)
		end
		
		f:EnableMouse(not value)
	end

	if (Settings[Setting_Lock] == false) then
		ShowGladius(false)
		
		if (Settings[Setting_AttachedToGladius]) then
			ShowGladius(true)
		end
	end
end

local function SuppressFirstSoundTrigger()
	for i=1,#ctFrames do
		ctFrames[i].New = true
	end
end

local onOptionChanged = 
{
	[Setting_Lock] = SetLock,
	[Setting_ShowTextAlways] = function(value) SetTextVisibility(not Settings[Setting_Lock] or value, not Settings[Setting_Lock]) end,
	[Setting_AttachedToGladius] = AttachedToGladiusChanged,
	[Setting_Inverted] = SuppressFirstSoundTrigger,
	[Setting_PlaySounds] = nil,
	[Setting_Scale] = SetFramesScale,
	[Setting_TextureId] = SetFramesTexture
}

local function ChangeSetting(SettingName, value)
	if (Settings[SettingName] ~= value) then
		SetSetting(SettingName, value)
		
		handler = Find(onOptionChanged, function(value, index) return index == SettingName end)
		if handler ~= nil then
			handler(value)
		end
	end
end

local function SetOption(info, value)
	local key = info.arg or info[#info]
	ChangeSetting(key, value)
end

local function GetOption(info)
	local key = info.arg or info[#info]
	return Settings[key]
end

local function BuildBlizzardOptions()

	local options = 
	{
		type = "group",
		name = "CombatTracking",
		plugins = {},
		get = GetOption,
		set = SetOption,
		args = {}
	}

	options.args[Setting_Lock] = -- probably we should never store lock option
	{
		type = "toggle",
		name = "Lock",
		desc = "lock frames",
		order = 1,
	}

	options.args[Setting_ShowTextAlways] = 
	{
		type = "toggle",
		name = "Show text",
		desc = "Show text on frames(lock frames to see difference)",
		order = 2,
	}

	options.args[Setting_Inverted] =
	{
		type = "toggle",
		name = "Inverted",
		desc = "Show frames if target is not in combat. Otherwise - show when target is not in combat",
		order = 3,
	}
	
	options.args[Setting_PlaySounds] =
	{
		type = "toggle",
		name = "Play sounds",
		desc = "Allow playing sounds",
		order = 4,
	}
	
	options.args[Setting_Scale] = 
	{
		type = "range",
		name = "Frames scale",
		desc = "Does not affect arenaframes integrated into gladius",
		min =.1,
		max = 5,
		step =.01,
		order = 5,
	}
	
	options.args[Setting_TextureId] = 
	{
		type = "range",
		name = "Frames texture",
		desc = "",
		min = 1,
		max = 4,
		step = 1,
		order = 6,
	}
	
	options.args.Reset = 
	{
		type = "execute",
		name = "Reset settings to defaults",
		order = 7,
		func = Reset 
	}
	
	options.args[Setting_AttachedToGladius] =
	{
		type = "toggle",
		name = "Integrate into gladius",
		desc = "Attach addon arenaframes to gladius arenaframes",
		order = 99,
	}

	return options
end


---------------------------------------------------------------- Main ----------------------------------------------------------------


local function FrameShouldBeUpdated(frame)
	if (GetFrameHidden(frame) == true) then
		return false
	end
	
	return true
end

local function FrameShouldBeVisible(frame)
	local frameTarget = frame.TargetType
	if not UIParent:IsVisible() -- we might use UIParent as parent of frames but it leads to problems with addons such as MoveAnything
	or GetFrameHidden(frame)
	or not UnitExists(frameTarget)
	or UnitHealth(frameTarget) == 0 --UnitIsDead(frameTarget) --not work if target far enough
	or UnitIsGhost(frameTarget)
	or UnitIsConnected(frameTarget) == nil
		then return false
	end
	
	local invertedLogic = Settings[Setting_Inverted]
	
	if UnitAffectingCombat(frameTarget) then
		return invertedLogic
	else
		return not invertedLogic
	end
end

local function UpdateFrameCombatStatus(frame)
	local newUnitInCombat = nil
	if UnitExists(frame.TargetType) then
		newUnitInCombat = UnitAffectingCombat(frame.TargetType)
	end
		
	if (not newUnitInCombat and frame.InCombat and Settings[Setting_PlaySounds] == true and GetFrameUseSound(frame) == true) then
		if (frame.TargetType ~= "Player") then
			PlaySoundFile("Interface\\AddOns\\CombatTracking\\bell.wav", "MASTER")
		else
			PlaySoundFile("Interface\\AddOns\\CombatTracking\\beep.mp3", "MASTER")
		end
	end
	
	frame.InCombat = newUnitInCombat
end

local function UpdateFrame(frame)
	UpdateFrameCombatStatus(frame)
	SetVisibility(frame, FrameShouldBeVisible(frame))
end

local function OnUpdate(self)
	if not Settings[Setting_Lock] then return end
	
	for i = 1, #ctFrames do
		local frame = ctFrames[i]
		if frame ~= nil and FrameShouldBeUpdated(frame) == true then
			UpdateFrame(frame)
		end
	end
end

local function HandleSlashCommand(cmd)
	cmd = string.upper(cmd)
	if cmd ~= nil then
		if (cmd == "LOCK") then Settings[Setting_Lock] = not Settings[Setting_Lock] SetLock(Settings[Setting_Lock]) return end
	end
	
	InterfaceOptionsFrame_OpenToCategory("CombatTracking")
end


SlashCmdList["CombatTracking"] = function(cmd) HandleSlashCommand(cmd) end
SLASH_CombatTracking1 = "/ct"
SLASH_CombatTracking2 = "/combatTracking"
SLASH_CombatTracking3 = "/cTracking"

local controlFrame = CreateFrame("Frame")
controlFrame:SetScript("OnUpdate", OnUpdate)

local eventHandlers =
{
	["VARIABLES_LOADED"] = Init,
	["PLAYER_FOCUS_CHANGED"] = function() GetFrameByTarget("Focus").InCombat = nil end,
	["PLAYER_TARGET_CHANGED"] = function() GetFrameByTarget("Target").InCombat = nil end,
}

for k,v in pairs(eventHandlers) do
	controlFrame:RegisterEvent(k)
end

controlFrame:SetScript("OnEvent", function(self,event) eventHandlers[event]() end)

LibStub("AceConfig-3.0"):RegisterOptionsTable("CombatTracking", BuildBlizzardOptions())
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("CombatTracking", "CombatTracking")
PrintMessage("Addon has been load. Type '/combatTracking' or '/ct' for options")