local Setting_ShowTextAlways = "showTextAlways"

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
	if (text) then
		ChatFrame1:AddMessage(text, 0, 1, 0)
	else
		ChatFrame1:AddMessage("nil passed!", 0, 1, 0)
	end
end

local function PrintMessage(text)
	Print("CombatTracking - " .. text)
end

local function PrintBool(bool)
	if bool == nil then
		Print("Unknown")
	elseif bool == true then
		Print("TRUE")
	elseif bool == false then
		Print("FALSE")
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
	Print("lock - lock/unclock frames")
	Print("showtext --- show/hide frames text")
	Print("reset --- reset all settings to defaults")
	Print("----------------------------------------------------------------------")
end

local function PrintGreetings()
	Print("Combat Tracking has been load. Type '/ct' for options")
end

local function GetSetting(settingName)
	if (CombatTrackingDB.Settings and CombatTrackingDB.Settings[settingName]) then 
		return CombatTrackingDB.Settings[settingName]
	end
end

local function SetSetting(settingName, value)
	if (not CombatTrackingDB.Settings) then CombatTrackingDB.Settings = {} return false end
	
	CombatTrackingDB.Settings[settingName] = value
	return true
end

local function InitSetting(settingName, defaultValue)
	local setting = GetSetting(settingName)
	if not setting then
		SetSetting(settingName, defaultValue)
	end
	
	return GetSetting(settingName)
end

local function InvertSetting(settingName, defaultValue)
	local setting = GetSetting(settingName)
	local newSetting
	if setting then 
		newSetting = not setting 
	else 
		newSetting = defaultValue 
	end
	
	SetSetting(settingName, newSetting)
	return newSetting
end

local function SetVisible(target, value)
	if target then
		if value then 
			target:Show()
		else
			 target:Hide()
		end
	end
end

local function FrameOnUpdate(self, target) 
	if not GetFrameHidden(self) then
		SetVisible(self, UnitExists(target) and not UnitAffectingCombat(target))
	end
end

local function SaveFrame(item)
	if item then
		local target = item.ParentTargetFrame
		local point, relativeTo, relativePoint, xOfs, yOfs = item:GetPoint(n)
	
		local frameInfo = CombatTrackingDB[target] or {}
		frameInfo.xOfs = xOfs
		frameInfo.yOfs = yOfs
		frameInfo.point = point
		frameInfo.relativePoint = nil
		frameInfo.hidden = GetFrameHidden(item)
		
		if (relativeTo) then 
			for target, parentFrameInfo in pairs(itemsDefaultLocations) do
				local parentFrame = parentFrameInfo.parentFrame
				if (relativeTo == parentFrame) then
					frameInfo.point = "Left"
					frameInfo.relativePoint = relativePoint
				end
			end
		end
		
		CombatTrackingDB[target] = frameInfo
	end
end

local function ToggleHideFrame(frameTargetName)
	local frame = Find(ctFrames, function(item) if CompareIgnoreCase(item.ParentTargetFrame, frameTargetName) then return true end end)
	if frame then 
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

local function CreateCTFrame(parentFrameInfo, target)
	local frame = CreateFrame("Frame")
	frame:SetParent(nil)
	frame:SetSize(textureSize, textureSize)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnMouseDown", OnMouseDown)
	frame:SetScript("OnMouseUp",function(self,button) if button == "LeftButton" then self:StopMovingOrSizing() SaveFrame(self) end end)
	frame.t=frame:CreateTexture(nil,BORDER)
	frame:Hide()
	
	-- custom
	SetFrameHidden(frame, false)
	
	frame.t:SetTexture("Interface\\Icons\\ability_sap")
	
	if target then
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
	local parentFrameInfo = Find(itemsDefaultLocations, function(value, index) if CompareIgnoreCase(index, itemName) then return true end end)
	
	local frame = CreateCTFrame(parentFrameInfo, itemName)
	frame.ParentTargetFrame = itemName
	
	if setPoints == true then
		if (parentFrameInfo.parentFrame) then
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
	if (fi) then
		local frame = CreateDefault(itemName)
		SetFrameHidden(frame, fi.hidden)
		
		if fi.relativePoint then 
			frame:SetPoint(fi.point, itemsDefaultLocations[itemName].parentFrame, fi.relativePoint, fi.xOfs, fi.yOfs)
		else
			frame:SetPoint(fi.point, fi.xOfs, fi.yOfs)
		end
		frame.t:SetAllPoints()
		
		return frame
	end
end


local function SaveAllFrames(itemsCollection)
	for i = 1, #itemsCollection do
		local frame = itemsCollection[i]
		SaveFrame(frame)
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
	
	local showText = not value or GetSetting(Setting_ShowTextAlways) == true
	SetTextVisibility(showText)
	SaveAllFrames(ctFrames)
	isUpdateRequired = value
	framesLocked = value
end

local function Init()
	if not CombatTrackingDB.Settings then 
		CombatTrackingDB.Settings = {}
	end
	
	InitSetting(Setting_ShowTextAlways, false)

	for targetName, frameInfo in pairs(itemsDefaultLocations) do
		local parentFrame = frameInfo.parentFrame
		local item = LoadFrame(targetName)
		if (not item) then item = CreateDefault(targetName, true) end
		UpdateItem(item)
	end
	
	SetTextVisibility(GetSetting(Setting_ShowTextAlways))
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
	local newSettingValue = InvertSetting(Setting_ShowTextAlways, true)
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

local function HandleSlashCommand(cmd, ctFrames)
	cmd = string.upper(cmd)
	
	local cmdTable = {}
	
	for cmdItem in gmatch(cmd, "[^ ]+") do
		tinsert(cmdTable, cmdItem)
	end
	
	local command = cmdTable[1]
	if command then
		if (command == "LOCK") then ToggleLock()
		elseif (command == "RESET") then Reset()
		elseif (command == "SHOWTEXT") then ToggleShowText()
		elseif (command == "HIDE" and cmdTable[2]) then ToggleHideFrame(cmdTable[2])
		else PrintHelp() end
	else
		PrintHelp()
	end
end

local function OnUpdate(self)
	if isUpdateRequired then
		 for i = 1, #ctFrames do
			local itemToUpdate = ctFrames[i]
			if itemToUpdate and not GetFrameHidden(itemToUpdate) then
				FrameOnUpdate(itemToUpdate, itemToUpdate.ParentTargetFrame)
			end
		end
	end
end

SlashCmdList["CombatTracking"] = function(cmd) HandleSlashCommand(cmd, ctFrames) end
SLASH_CombatTracking1 = "/ct"
local controlFrame = CreateFrame("Frame")
controlFrame:SetScript("OnUpdate", OnUpdate)
controlFrame:RegisterEvent("VARIABLES_LOADED")
controlFrame:SetScript("OnEvent", function(self,event) if event == "VARIABLES_LOADED" then Init() end end)
PrintGreetings()