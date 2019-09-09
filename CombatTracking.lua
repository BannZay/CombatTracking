local Settings =
{
	Setting_ShowTextAlways = "showTextAlways",
	Setting_Scale = "scale",
	Setting_Texture = "texture",
	Setting_Inverted = "inverted",
}

CombatTrackingDB = CombatTrackingDB or {}
local textureSize = 40
local framesLocked = true
local ctFrames = {}
local isUpdateRequired = true

local itemsDefaultLocations =
{
	["Player"] = {point = "Left", x = -3, y = 5, parentFrame = PlayerFrame, relativePoint = "Right"},
	["Target"] = {point = "Left", x = -35, y = 5, parentFrame = TargetFrame, relativePoint = "Right"},
	["Focus"] =  {point = "Left", x = -25, y = 5, parentFrame = FocusFrame, relativePoint = "Right"},
	["Party1"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame1, relativePoint = "Right"},
	["Party2"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame2, relativePoint = "Right"},
	["Party3"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame3, relativePoint = "Right"},
	["Party4"] = {point = "Left", x = -5, y = 5, parentFrame = PartyMemberFrame4, relativePoint = "Right"},
	["Arena1"] = {point = "TOP", x = (textureSize + 5) * -2, y = 0, parentFrame = nil},
	["Arena2"] = {point = "TOP", x = (textureSize + 5) * -1, y = 0, parentFrame = nil},
	["Arena3"] = {point = "TOP", x = (textureSize + 5) * 0, y = 0, parentFrame = nil},
	["Arena4"] = {point = "TOP", x = (textureSize + 5) * 1, y = 0, parentFrame = nil},
	["Arena5"] = {point = "TOP", x = (textureSize + 5) * 2, y = 0, parentFrame = nil},
}

local textureList = 
{
	"Interface\\Icons\\ability_sap",
	"Interface\\Icons\\ABILITY_DUALWIELD",
}

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

local function Print(text)
	ChatFrame1:AddMessage(string.format("%s", text), 0, 1, 0)
end

local function PrintMessage(text)
	Print("CombatTracking - " .. text)
end

local function BoolToString(bool)
	if (bool == nil) then
		return "nil"
	elseif (bool == true) then
		return "true"
	else
		return "false"
	end
end

local function SetFrameHidden(frame, value)
	frame.CTHidden = value
	
	if value then
		frame.t:SetAlpha(0.2)
	else
		frame.t:SetAlpha(1)
	end
end

local function GetFrameHidden(frame)
	return frame.CTHidden == true
end

local function PrintHelp()
	Print("----------------------------------------------------------------------")
	Print("CombatTracking settings: Type '/ct <option>'")
	Print("Options list:")
	Print("lock - [lock/unclock] frames")
	Print("showtext - [show/hide] frames text")
	Print("scale <scale> - set scale to <scale>")
	Print("texture - use another texture")
	Print("invert - show frame when unit [in/not in] combat")
	Print("reset - reset all settings to defaults")
	Print("----------------------------------------------------------------------")
end

local function PrintGreetings()
	Print("Combat Tracking has been load. Type '/ct' for options")
end

local function GetSetting(settingName)
	if (CombatTrackingDB.Settings ~= nil and CombatTrackingDB.Settings[settingName] ~= nil) then 
		return CombatTrackingDB.Settings[settingName]
	end
end

local function SetSetting(settingName, value)
	if (CombatTrackingDB.Settings == nil) then 
		CombatTrackingDB.Settings = {}
	end
	
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

local function SetVisible(target, value)
	if target ~= nil then
		if value then 
			target:Show()
		else
			target:Hide()
		end
	end
end

local function FrameShouldBeVisible(frame, frameTarget)
	if GetFrameHidden(frame) then 
		return false 
	end
	
	if (not UnitExists(frameTarget)) then
		return false
	end
	
	local invertedLogic = GetSetting(Settings.Setting_Inverted)
	
	if UnitAffectingCombat(frameTarget) then
		return invertedLogic
	else
		return not invertedLogic
	end
end

local function SaveFrame(item)
	if item ~= nil then
		local target = item.ParentTargetFrame
		local point, relativeTo, relativePoint, xOfs, yOfs = item:GetPoint(n)
	
		local frameInfo = CombatTrackingDB[target] or {}
		frameInfo.xOfs = xOfs
		frameInfo.yOfs = yOfs
		frameInfo.point = point
		frameInfo.relativePoint = nil
		frameInfo.hidden = GetFrameHidden(item)
		
		if (relativeTo ~= nil) then
			local parentFrameInfo = Find(itemsDefaultLocations, function(x) return x.parentFrame == relativeTo end)
			
			if parentFrameInfo ~= nil then
				frameInfo.point = "Left"
				frameInfo.relativePoint = relativePoint
			end
		end
		
		CombatTrackingDB[target] = frameInfo
	end
end

local function SetScale(scale)
	SetSetting(Settings.Setting_Scale, scale)

	for i = 1, #ctFrames do
		local ctFrame = ctFrames[i]
		ctFrame:SetScale(scale)
	end
end

local function UserAttemptsToSetScale(scale)
	local number = tonumber(scale)
	
	if (number ~= nil and number >= 0) then
		SetScale(number)
	else
		PrintMessage("Scale must be greater then zero")
	end
end

local function ToggleHideFrame(frameTargetName)
	local frame = Find(ctFrames, function(item) if CompareIgnoreCase(item.ParentTargetFrame, frameTargetName) then return true end end)
	if frame ~= nil then 
		SetFrameHidden(frame, not GetFrameHidden(frame))
		SaveFrame(frame)
	else
		Print("No such frame. Type /ct showtext to see framenames")
	end
end

local function OnMouseDown(self,button)
	if button == "LeftButton" then 
		self:StartMoving()
	elseif button == "RightButton" then
		ToggleHideFrame(self.ParentTargetFrame)
	end
end

local function SetFramesTexture(texture)
	for i = 1, #ctFrames do
		ctFrames[i].t:SetTexture(texture)
	end
	
	SetSetting(Settings.Setting_Texture, texture)
end

local function UseNextTexture()
	local currentTexture = GetSetting(Settings.Setting_Texture)
	
	local value, currentIndex = Find(textureList, function(x) return x == currentTexture end)
	local nextIndex
	
	if (currentIndex == nil or currentIndex == #textureList) then
		nextIndex = 1
	else
		nextIndex = currentIndex + 1
	end
	
	SetFramesTexture(textureList[nextIndex])
end

local function CreateCTFrame(parentFrameInfo, target)
	local frame = CreateFrame("Frame", "CombatTracking" .. target .. "frame", UIParent)
	frame:SetSize(textureSize, textureSize)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnMouseDown", OnMouseDown)
	frame:SetScript("OnMouseUp",function(self,button) if button == "LeftButton" then self:StopMovingOrSizing() SaveFrame(self) end end)
	frame.t=frame:CreateTexture(nil,BORDER)
	frame:Hide()
	
	-- custom
	SetFrameHidden(frame, false)
	
	frame.t:SetTexture(GetSetting(Settings.Setting_Texture))
	frame:SetScale(GetSetting(Settings.Setting_Scale))
	
	if target ~= nil then
		local fontString = frame:CreateFontString(nil,"ARTWORK")
		fontString:SetFont("Fonts\\ARIALN.ttf", 13, "OUTLINE")
		fontString:SetPoint("CENTER",0,0)
		fontString:SetText(target)
		fontString:Hide()
		frame.text = fontString
	end
	
	return frame
end

local function UpdateItem(target)
	for i = 1, #ctFrames do 
		local itemToUpdate = ctFrames[i]
		if (itemToUpdate.ParentTargetFrame == target) then
			table.remove(ctFrames, i)
			itemToUpdate:Hide()
			break
		end
	end

	table.insert(ctFrames, target)
end

local function SetTextVisibility(value)
	for i = 1, #ctFrames do
		SetVisible(ctFrames[i].text, value)
	end
end

local function CreateDefault(itemName, setPoints)
	local parentFrameInfo = Find(itemsDefaultLocations, function(value, index) return CompareIgnoreCase(index, itemName) end)
	
	local frame = CreateCTFrame(parentFrameInfo, itemName)
	frame.ParentTargetFrame = itemName
	
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
		local frame = CreateDefault(itemName)
		SetFrameHidden(frame, fi.hidden)
		
		if fi.relativePoint ~= nil then 
			frame:SetPoint(fi.point, itemsDefaultLocations[itemName].parentFrame, fi.relativePoint, fi.xOfs, fi.yOfs)
		else
			frame:SetPoint(fi.point, fi.xOfs, fi.yOfs)
		end
		frame.t:SetAllPoints()
		
		return frame
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
	
	local showText = not value or GetSetting(Settings.Setting_ShowTextAlways) == true
	SetTextVisibility(showText)
	isUpdateRequired = value
	framesLocked = value
end

local function Init()
	if CombatTrackingDB.Settings == nil then 
		CombatTrackingDB.Settings = {}
	end
	
	InitSetting(Settings.Setting_ShowTextAlways, false)
	InitSetting(Settings.Setting_Scale, 1)
	InitSetting(Settings.Setting_Texture, textureList[1])
	local s = InitSetting(Settings.Setting_Inverted, false)
	
	for targetName, frameInfo in pairs(itemsDefaultLocations) do
		local parentFrame = frameInfo.parentFrame
		local item = LoadFrame(targetName)
		if item == nil then item = CreateDefault(targetName, true) end
		UpdateItem(item)
	end
	
	SetTextVisibility(GetSetting(Settings.Setting_ShowTextAlways))
	SetLock(true)
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

local function ToggleShowText()
	local newSettingValue = InvertSetting(Settings.Setting_ShowTextAlways, true)
	SetTextVisibility(newSettingValue)
end

local function ToggleLock()
	SetLock(not framesLocked)
	if (framesLocked) then
		PrintMessage("Frames locked")
	else
		PrintMessage("Frames unlocked. Drag them to change location or right click on them to hide")
	end
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
		elseif (command == "HIDE" and cmdTable[2] ~= nil) then ToggleHideFrame(cmdTable[2])
		elseif (command == "SCALE" and tonumber(cmdTable[2]) ~= nil) then UserAttemptsToSetScale(cmdTable[2])
		elseif (command == "TEXTURE") then UseNextTexture()
		elseif (command == "INVERT") then InvertSetting(Settings.Setting_Inverted)
		else PrintHelp() end
	else
		PrintHelp()
	end
end

local function OnUpdate(self)
	if isUpdateRequired then
		 for i = 1, #ctFrames do
			local frame = ctFrames[i]
			if frame ~= nil then
				SetVisible(frame, FrameShouldBeVisible(frame, frame.ParentTargetFrame))
			end
		end
	end
end

SlashCmdList["CombatTracking"] = function(cmd) HandleSlashCommand(cmd) end
SLASH_CombatTracking1 = "/ct"
local controlFrame = CreateFrame("Frame")
controlFrame:SetScript("OnUpdate", OnUpdate)
controlFrame:RegisterEvent("VARIABLES_LOADED")
controlFrame:SetScript("OnEvent", function(self,event) if event == "VARIABLES_LOADED" then Init() end end)
PrintGreetings()