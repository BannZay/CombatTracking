local Settings =
{
	Setting_ShowTextAlways = "showTextAlways",
	Setting_Scale = "scale",
	Setting_TextureId = "textureId",
	Setting_Inverted = "inverted",
	Setting_PlayMusic = "playMusic",
	Setting_AttachedToGladius = "attachedToGladius"
}

CombatTrackingDB = CombatTrackingDB or {}
local ctFrames = {}
local textureSize = 40
local framesIsLocked = true
local isUpdateRequired = true
local frameNoSoundNote = "(no sound)"

local ctToolTipText =
{
	"Left click - drag frame",
	"Right click - toggle hide option",
	"Right click with control - toggle sound option",
}

local targetsDefaultSettings =
{
	["Player"] = {point = "Left", x = -3, y = 5, parentFrame = PlayerFrame, relativePoint = "Right", useSound = false, hidden = true},
	["Target"] = {point = "Left", x = -35, y = 5, parentFrame = TargetFrame, relativePoint = "Right", useSound = true},
	["Focus"] =  {point = "Left", x = -25, y = 5, parentFrame = FocusFrame, relativePoint = "Right", useSound = true},
	["Party1"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame1, relativePoint = "Right", useSound = false},
	["Party2"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame2, relativePoint = "Right", useSound = false},
	["Party3"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame3, relativePoint = "Right", useSound = false},
	["Party4"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame4, relativePoint = "Right", useSound = false},
	["Arena1"] = {point = "TOP", x = (textureSize + 5) * -2, y = 0, parentFrame = nil, useSound = true},
	["Arena2"] = {point = "TOP", x = (textureSize + 5) * -1, y = 0, parentFrame = nil, useSound = true},
	["Arena3"] = {point = "TOP", x = (textureSize + 5) * 0, y = 0, parentFrame = nil, useSound = true},
	["Arena4"] = {point = "TOP", x = (textureSize + 5) * 1, y = 0, parentFrame = nil, useSound = true},
	["Arena5"] = {point = "TOP", x = (textureSize + 5) * 2, y = 0, parentFrame = nil, useSound = true},
}

local textures =
{
	"Interface\\Icons\\ability_sap",
	"Interface\\Icons\\ABILITY_DUALWIELD",
	"Interface\\Icons\\ability_ambush",
	"Interface\\Icons\\ability_parry",
}


-------------------------------- General --------------------------------


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


local function GetSetting(settingName)
	return CombatTrackingDB.Settings[settingName]
end

local function SetSetting(settingName, value)
	CombatTrackingDB.Settings[settingName] = value
end

local function InitSetting(settingName, defaultValue)
	local setting = GetSetting(settingName)
	if (setting == nil) then
		SetSetting(settingName, defaultValue)
	end
	
	return GetSetting(settingName)
end

local function InvertSetting(settingName, defaultValue)
	local setting = GetSetting(settingName)
	local newSetting
	if setting ~= nil then 
		newSetting = not setting 
	else 
		newSetting = defaultValue 
	end
	
	SetSetting(settingName, newSetting)
	return newSetting
end


-------------------------------- Printing --------------------------------


local function Print(text)
	ChatFrame1:AddMessage(string.format("%s", text), 0, 1, 0)
end

local function PrintMessage(text)
	Print("CombatTracking - " .. text)
end

local function PrintHelp()
	Print("----------------------------------------------------------------------")
	Print("CombatTracking settings: Type '/combatTracking <option>' or '/ct <option>'")
	Print("Options list:")
	Print("lock - "..Switch(framesIsLocked, "unlock", "lock").." frames")
	Print("text - "..Switch(GetSetting(Settings.Setting_ShowTextAlways), "hide", "show").." frames text")
	Print("scale <scale> - change scale from ".. GetSetting(Settings.Setting_Scale) .." to <scale>")
	Print("music - "..Switch(GetSetting(Settings.Setting_PlayMusic), "mute", "unmute").." music")
	Print("texture <optionalTextureId> - use another texture. Current TextureId = "..GetSetting(Settings.Setting_TextureId))
	Print("invert - show frame when unit "..Switch(GetSetting(Settings.Setting_Inverted), "not in", "in").." combat")
	Print("gladius - "..Switch(GetSetting(Settings.Setting_AttachedToGladius), "do not", "do").." intergrate arena target frames into gladius")
	Print("reset - reset all settings to defaults")
	Print("----------------------------------------------------------------------")
end

local function PrintGreetings()
	Print("Combat Tracking has been load. Type '/combatTracking' or '/ct' for options")
end


---------------------------------------------------------------- Frame settings ----------------------------------------------------------------


local function SetFrameUseSound(frame, value)
	frame.useSound = value
	
	if (value) then
		frame.musicText:SetText(nil)
	else
		frame.musicText:SetText(frameNoSoundNote)
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

local function SetVisible(target, value)
	if target ~= nil then
		if value then 
			target:Show()
		else
			target:Hide()
		end
	end
end

local function SetFramesScale(scale)
	SetSetting(Settings.Setting_Scale, scale)

	for i = 1, #ctFrames do
		local ctFrame = ctFrames[i]
		ctFrame:SetScale(scale)
	end
end

local function SetFramesTexture(textureId)
	local texture = textures[textureId]
	
	if (texture ~= nil) then
		for i = 1, #ctFrames do
			ctFrames[i].t:SetTexture(texture)
		end
		
		SetSetting(Settings.Setting_TextureId, textureId)
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
		local f = Find(ctFrames, function(x) return x.TargetType == "Arena"..i end)
		
		if (gladiusButtonFrame ~= nil) then
			-- Setup our frame
			f:ClearAllPoints()
			f:SetPoint("TopRight",gladiusButtonFrame , "TopLeft", -4, 0)
			f:SetWidth(gladiusButtonFrame.classIcon:GetWidth())
			f:SetHeight(gladiusButtonFrame.classIcon:GetHeight())
			f.t:SetAllPoints()
			
			-- Modify gladius frames
			gladiusButtonFrame.drCooldownFrame:ClearAllPoints()
			gladiusButtonFrame.drCooldownFrame:SetPoint("TopRight", f, "TopLeft")
			
			f:EnableMouse(false)
			SetVisible(f, arg1)
		end
	end
end

local function OnGladiusFrameAppeared(arg1)
	if GetSetting(Settings.Setting_AttachedToGladius) then
		GladiusFrameAppeared(arg1)
	end
end


---------------------------------------------------------------- Frames management ----------------------------------------------------------------


local function SetFrameAsNew(frameTarget)
	local frame = Find(ctFrames, function(x) return x.TargetType == frameTarget end)
	frame.New = true
end

local function SaveFrame(item)
	if item ~= nil then
		local target = item.TargetType
		local point, relativeTo, relativePoint, xOfs, yOfs = item:GetPoint(n)
	
		local frameInfo = CombatTrackingDB[target] or {}
		frameInfo.xOfs = xOfs
		frameInfo.yOfs = yOfs
		frameInfo.point = point
		frameInfo.relativePoint = nil
		frameInfo.hidden = GetFrameHidden(item)
		frameInfo.useSound = GetFrameUseSound(item)
		
		if (relativeTo ~= nil) then
			local parentFrameInfo = Find(targetsDefaultSettings, function(x) return x.parentFrame == relativeTo end)
			
			if parentFrameInfo ~= nil then
				frameInfo.point = "Left"
				frameInfo.relativePoint = relativePoint
			end
		end
		
		CombatTrackingDB[target] = frameInfo
	end
end

local function OnMouseDown(self,button)
	if button == "LeftButton" then
		self:StartMoving()
	elseif button == "RightButton" then
		if (IsLeftControlKeyDown()) then
			if (not GetFrameHidden(self)) then
				SetFrameUseSound(self, not GetFrameUseSound(self))
				SaveFrame(self)
			end
		else
			local frame = Find(ctFrames, function(item) return CompareIgnoreCase(item.TargetType, self.TargetType) end)
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

local function CreateCTFrame(parentFrameInfo, target)
	local frame = CreateFrame("Frame", "CombatTracking" .. target .. "frame")
	frame:SetSize(textureSize, textureSize)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(30)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnMouseDown", OnMouseDown)
	frame:SetScript("OnMouseUp",function(self,button) if button == "LeftButton" then self:StopMovingOrSizing() SaveFrame(self) end end)
	frame.t=frame:CreateTexture(nil,BORDER)
	frame:Hide()
	
	frame.t:SetTexture(textures[GetSetting(Settings.Setting_TextureId)])
	frame:SetScale(GetSetting(Settings.Setting_Scale))
	
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

local function CreateDefaultFrame(itemName, setPoints)
	local parentFrameInfo = Find(targetsDefaultSettings, function(value, index) return CompareIgnoreCase(index, itemName) end)
	
	local frame = CreateCTFrame(parentFrameInfo, itemName)
	
	SetFrameUseSound(frame, parentFrameInfo.useSound)
	
	if setPoints == true then
		if (parentFrameInfo.parentFrame ~= nil) then
			frame:SetPoint(parentFrameInfo.point, parentFrameInfo.parentFrame, parentFrameInfo.relativePoint, parentFrameInfo.x, parentFrameInfo.y) 
		else
			frame:SetPoint(parentFrameInfo.point, parentFrameInfo.x, parentFrameInfo.y)
		end
		frame.t:SetAllPoints()
	end
	
	SetFrameHidden(frame, parentFrameInfo.hidden)
	
	if (not GetFrameHidden(frame)) then
		SetFrameUseSound(frame, parentFrameInfo.useSound)
	end
	
	return frame
end

local function LoadFrame(itemName)
	local fi  = CombatTrackingDB[itemName]
	if (fi ~= nil) then
		local frame = CreateDefaultFrame(itemName)
		SetFrameHidden(frame, fi.hidden)
		SetFrameUseSound(frame, fi.useSound)
		
		if fi.relativePoint ~= nil then 
			frame:SetPoint(fi.point, targetsDefaultSettings[itemName].parentFrame, fi.relativePoint, fi.xOfs, fi.yOfs)
		else
			frame:SetPoint(fi.point, fi.xOfs, fi.yOfs)
		end
		
		frame.t:SetAllPoints()
		return frame
	end
end

local function SetTextVisibility(targetVisibility, musicVisibility)
	for i = 1, #ctFrames do
		SetVisible(ctFrames[i].targetText, targetVisibility)
		SetVisible(ctFrames[i].musicText, musicVisibility)
	end
end

local function SetLock(value)
	
	if GetSetting(Settings.Setting_AttachedToGladius) then
		ShowGladius(not value)
	end
	
	for i = 1, #ctFrames do
		local frame = ctFrames[i]
		
		frame:EnableMouse(not value and frame.allowDrag ~= false)
		
		SetVisible(frame, not value)
	end
	
	if (value) then
		SetTextVisibility(GetSetting(Settings.Setting_ShowTextAlways), false)
	else
		SetTextVisibility(true, true)
	end
	
	isUpdateRequired = value
	framesIsLocked = value
end

local function UpdateLock()
	local locked = framesIsLocked
	SetLock(not locked)
	SetLock(locked)
end

local function SetAttachedToGladius(value)
	SetSetting(Settings.Setting_AttachedToGladius, value)
	
	if IsAddOnLoaded("Gladius") then
		 if value then
			hooksecurefunc(Gladius, "JoinedArena", OnGladiusFrameAppeared)
			hooksecurefunc(Gladius, "ToggleFrame", OnGladiusFrameAppeared) -- '/gladius test' triggers this method
			
			for i=1,5 do
				f = Find(ctFrames, function(x) return x.TargetType == "Arena"..i  end)
				f.allowDrag = false
			end
		else
			ReloadUI()
		end
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
	if CombatTrackingDB.Settings == nil then 
		CombatTrackingDB.Settings = {}
	end
	
	InitSetting(Settings.Setting_ShowTextAlways, false)
	InitSetting(Settings.Setting_Scale, 1)
	InitSetting(Settings.Setting_TextureId, 1)
	InitSetting(Settings.Setting_Inverted, false)
	InitSetting(Settings.Setting_PlayMusic, true)
	InitSetting(Settings.Setting_AttachedToGladius, true)
	
	for targetName, frameInfo in pairs(targetsDefaultSettings) do
		local parentFrame = frameInfo.parentFrame
		local item = LoadFrame(targetName)
		if item == nil then item = CreateDefaultFrame(targetName, true) end
		UpdateItem(item)
	end
	
	SetTextVisibility(GetSetting(Settings.Setting_ShowTextAlways))
	
	SetAttachedToGladius(GetSetting(Settings.Setting_AttachedToGladius))
	
	SetLock(true)
end


---------------------------------------------------------------- User Command Handlers ----------------------------------------------------------------


local function UserAttemptsToSetScale(scale)
	local number = tonumber(scale)
	
	if (number ~= nil and number >= 0) then
		SetFramesScale(number)
	else
		PrintMessage("Scale must be greater then zero")
	end
end

local function UseNextTexture(optionalId)
	if (optionalId == nil) then
		optionalId = GetSetting(Settings.Setting_TextureId) + 1
	end
	
	SetFramesTexture(optionalId)
end

local function ToggleShowText()
	InvertSetting(Settings.Setting_ShowTextAlways, true)
	UpdateLock()
end

local function Reset()
	CombatTrackingDB = {}
	
	local oldFrames = ctFrames
	ctFrames = {}
	
	for i = 1, #oldFrames do
		SetFrameHidden(oldFrames[i], true)
		oldFrames[i]:Hide()
	end
	
	Init()
	SetLock(false)
end

local function HandleSlashCommand(cmd)
	cmd = string.upper(cmd)
	
	local cmdTable = {}
	
	for cmdItem in gmatch(cmd, "[^ ]+") do
		tinsert(cmdTable, cmdItem)
	end
	
	local command = cmdTable[1]
	if command ~= nil then
		if (command == "LOCK") then SetLock(not framesIsLocked)
		elseif (command == "RESET") then Reset()
		elseif (command == "TEXT") then ToggleShowText()
		elseif (command == "SCALE" and tonumber(cmdTable[2]) ~= nil) then UserAttemptsToSetScale(cmdTable[2])
		elseif (command == "TEXTURE" and (cmdTable[2] == nil or tonumber(cmdTable[2]) ~= nil)) then UseNextTexture(tonumber(cmdTable[2]))
		elseif (command == "INVERT") then InvertSetting(Settings.Setting_Inverted)
		elseif (command == "MUSIC") then InvertSetting(Settings.Setting_PlayMusic)
		elseif (command == "GLADIUS") then SetAttachedToGladius(not GetSetting(Settings.Setting_AttachedToGladius)) UpdateLock()
		else PrintHelp() end
	else
		PrintHelp()
	end
end


---------------------------------------------------------------- Main ----------------------------------------------------------------


local function FrameShouldBeVisible(frame, frameTarget)
	
	if not UIParent:IsVisible() -- we might use UIParent as parent of frames but it leads to problems with addons such as MoveAnything
	or GetFrameHidden(frame)
	or not UnitExists(frameTarget)
	or UnitHealth(frameTarget) == 0 --UnitIsDead(frameTarget) --not work if target far enough
	or UnitIsGhost(frameTarget)
	or UnitIsConnected(frameTarget) == nil
		then return false
	end
	
	local invertedLogic = GetSetting(Settings.Setting_Inverted)
	
	if UnitAffectingCombat(frameTarget) then
		return invertedLogic
	else
		return not invertedLogic
	end
end

local function OnUpdate(self)
	if not isUpdateRequired then return end
	
	for i = 1, #ctFrames do
		local frame = ctFrames[i]
		if frame ~= nil then
			if (not GetFrameHidden(frame)) then
				if (FrameShouldBeVisible(frame, frame.TargetType)) then
					if (not frame:IsVisible()) then
						frame:Show()
						
						if (frame.New == false) then
							if GetFrameUseSound(frame) and GetSetting(Settings.Setting_PlayMusic) then
								PlaySoundFile("Interface\\AddOns\\CombatTracking\\bell.wav")
							end
						end
					end
				else
					frame:Hide()
				end
				
				if (UnitExists(frame.TargetType)) then
					frame.New = false
				end
			end
		end
	end
end


local eventHandlers =
{
	["VARIABLES_LOADED"] = Init,
	["PLAYER_FOCUS_CHANGED"] = function() SetFrameAsNew("Focus") end,
	["PLAYER_TARGET_CHANGED"] = function() SetFrameAsNew("Target") end,
}

SlashCmdList["CombatTracking"] = function(cmd) HandleSlashCommand(cmd) end
SLASH_CombatTracking1 = "/ct"
SLASH_CombatTracking2 = "/combatTracking"
SLASH_CombatTracking2 = "/cTracking"
local controlFrame = CreateFrame("Frame")
controlFrame:SetScript("OnUpdate", OnUpdate)
controlFrame:RegisterEvent("VARIABLES_LOADED")
controlFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
controlFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

controlFrame:SetScript("OnEvent", function(self,event) eventHandlers[event]() end)
PrintGreetings()