local Settings =
{
	Setting_ShowTextAlways = "showTextAlways",
	Setting_Scale = "scale",
	Setting_Texture = "texture",
	Setting_Inverted = "inverted",
	Setting_Music = "playMusic"
}

CombatTrackingDB = CombatTrackingDB or {}
local ctFrames = {}

local textureSize = 40
local framesIsLocked = true
local isUpdateRequired = true
local frameNoSoundNote = "(no sound)"

local targetsDefaultSettings =
{
	["Player"] = {point = "Left", x = -3, y = 5, parentFrame = PlayerFrame, relativePoint = "Right", useSound = false},
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
	Print("lock - [lock/unclock] frames")
	Print("showtext - [show/hide] frames text")
	Print("scale <scale> - set scale to <scale>")
	Print("music - [not] play music")
	Print("texture - use another texture")
	Print("invert - show frame when unit [not] in combat")
	Print("reset - reset all settings to defaults")
	Print("----------------------------------------------------------------------")
end

local function PrintGreetings()
	Print("Combat Tracking has been load. Type '/combatTracking' or '/ct' for options")
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

local function SetFramesTexture(texture)
	for i = 1, #ctFrames do
		ctFrames[i].t:SetTexture(texture)
	end
	
	SetSetting(Settings.Setting_Texture, texture)
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
				SaveFrame(frame)
			end
		else
			local frame = Find(ctFrames, function(item) return CompareIgnoreCase(item.TargetType, self.TargetType) end)
			SetFrameHidden(frame, not GetFrameHidden(frame))
			SaveFrame(frame)
		end
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
	
	frame.t:SetTexture(GetSetting(Settings.Setting_Texture))
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
	
	SetFrameHidden(frame, false)
	
	return frame
end

local function CreateDefaultFrame(itemName, setPoints)
	local parentFrameInfo = Find(targetsDefaultSettings, function(value, index) return CompareIgnoreCase(index, itemName) end)
	
	local frame = CreateCTFrame(parentFrameInfo, itemName)
	frame.TargetType = itemName
	SetFrameUseSound(frame, parentFrameInfo.useSound)
	
	if setPoints == true then
		if (parentFrameInfo.parentFrame ~= nil) then
			frame:SetPoint(parentFrameInfo.point, parentFrameInfo.parentFrame, parentFrameInfo.relativePoint, parentFrameInfo.x, parentFrameInfo.y) 
		else
			frame:SetPoint(parentFrameInfo.point, parentFrameInfo.x, parentFrameInfo.y)
		end
		frame.t:SetAllPoints()
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
	for i = 1, #ctFrames do
		local frame = ctFrames[i]
		frame:EnableMouse(not value)
		if (not value) then 
			frame:Show()
		elseif GetFrameHidden(frame) then
			frame:Hide()
		end
	end
	
	if (value) then
		SetTextVisibility(GetSetting(Settings.Setting_ShowTextAlways), false)
	else
		SetTextVisibility(true, true)
	end
	
	isUpdateRequired = value
	framesIsLocked = value
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
	InitSetting(Settings.Setting_Texture, textures[1])
	InitSetting(Settings.Setting_Inverted, false)
	InitSetting(Settings.Setting_Music, true)
	
	for targetName, frameInfo in pairs(targetsDefaultSettings) do
		local parentFrame = frameInfo.parentFrame
		local item = LoadFrame(targetName)
		if item == nil then item = CreateDefaultFrame(targetName, true) end
		UpdateItem(item)
	end
	
	SetTextVisibility(GetSetting(Settings.Setting_ShowTextAlways))
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

local function UseNextTexture()
	local currentTexture = GetSetting(Settings.Setting_Texture)
	
	local value, currentIndex = Find(textures, function(x) return x == currentTexture end)
	local nextIndex
	
	if (currentIndex == nil or currentIndex == #textures) then
		nextIndex = 1
	else
		nextIndex = currentIndex + 1
	end
	
	SetFramesTexture(textures[nextIndex])
end

local function ToggleShowText()
	local newSettingValue = InvertSetting(Settings.Setting_ShowTextAlways, true)
	
	if (framesIsLocked) then
		SetTextVisibility(newSettingValue)
	end
end

local function ToggleLock()
	SetLock(not framesIsLocked)
	if (framesIsLocked) then
		PrintMessage("Frames locked")
	else
		PrintMessage("Frames unlocked. Drag them to change location or right click on them to hide or ctrl + right click to toggle sound setting")
	end
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
end

local function HandleSlashCommand(cmd)
	cmd = string.upper(cmd)
	
	local cmdTable = {}
	
	for cmdItem in gmatch(cmd, "[^ ]+") do
		tinsert(cmdTable, cmdItem)
	end
	
	local command = cmdTable[1]
	if command ~= nil then
		if (command == "LOCK") then ToggleLock()
		elseif (command == "RESET") then Reset()
		elseif (command == "SHOWTEXT") then ToggleShowText()
		elseif (command == "SCALE" and tonumber(cmdTable[2]) ~= nil) then UserAttemptsToSetScale(cmdTable[2])
		elseif (command == "TEXTURE") then UseNextTexture()
		elseif (command == "INVERT") then InvertSetting(Settings.Setting_Inverted)
		elseif (command == "MUSIC") then InvertSetting(Settings.Setting_Music)
		
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
	or UnitIsDead(frameTarget)
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
							if GetFrameUseSound(frame) and GetSetting(Settings.Setting_Music) then
								PlaySoundFile("Interface\\AddOns\\CombatTracking\\bell.wav")
							end
						end
					end
				else
					frame:Hide()
				end
				
				frame.New = false
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