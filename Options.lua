-- Interface options panels (AceConfig): general, sounds, units, profiles.
local CT = CombatTracking

local function Get(info)
	return CT.db.profile[info[#info]]
end

local function Set(info, value)
	CT.db.profile[info[#info]] = value
	CT:ApplySettings()
end

local function UnitGet(info)
	return CT.db.profile.units[info[#info - 1]][info[#info]]
end

local function UnitSet(info, value)
	CT.db.profile.units[info[#info - 1]][info[#info]] = value
	CT:ApplySettings()
end

local function TextureValues()
	local values = {}
	for i, texture in ipairs(CT.TEXTURES) do
		values[i] = format("|T%s:18|t %s", texture.path, texture.name)
	end
	return values
end

local function UnitOptions(unit, order)
	return {
		type = "group",
		name = unit,
		order = order,
		get = UnitGet,
		set = UnitSet,
		args = {
			enabled = { type = "toggle", name = "Enabled", desc = "Track this unit", order = 1 },
			sound = { type = "toggle", name = "Sound", desc = "Play sounds for this unit", order = 2 },
			anchor = {
				type = "input",
				name = "Anchor frame",
				desc = "Name of the frame the icon is attached to (for example TargetFrame or the frame of "
					.. "your unit frames addon). The icon moves with it. Unknown names attach to the screen.",
				order = 3,
				width = "full",
				set = function(info, value)
					local u = CT.db.profile.units[unit]
					u.anchor = strtrim(value)
					-- keep the icon where it is, relative to the new anchor
					CT:SavePosition(CT.iconsByUnit[unit])
					CT:ApplySettings()
				end,
			},
			anchorStatus = {
				type = "description",
				name = function()
					local name = CT.db.profile.units[unit].anchor
					if name ~= "UIParent" and CT:GetAnchorFrame(CT.iconsByUnit[unit], name) == UIParent then
						return "|cffff5555Frame " .. name .. " not found, the icon is attached to the screen.|r"
					end
					return ""
				end,
				order = 4,
			},
			resetPosition = {
				type = "execute",
				name = "Reset position",
				order = 5,
				func = function() CT:ResetPosition(unit) end,
			},
		},
	}
end

function CT:BuildOptions()
	local options = {
		type = "group",
		name = "CombatTracking",
		childGroups = "tab",
		get = Get,
		set = Set,
		args = {},
	}

	options.args.general = {
		type = "group",
		name = "General",
		order = 1,
		args = {
			usage = {
				type = "description",
				name = "Shows whether your target, focus, party and arena enemies are in combat. The swipe shows "
					.. "how long until the unit can leave combat.\n/ct - options, /ct lock - move icons, "
					.. "/ct test - test mode, /ct reset - reset profile",
				order = 0,
			},
			lock = {
				type = "toggle",
				name = "Lock icons",
				desc = "Unlock to drag the icons. Right click an unlocked icon to disable it, Ctrl + right click "
					.. "to turn its sound off.",
				order = 1,
				get = function() return CT.locked end,
				set = function(_, value) CT:SetLocked(value) end,
			},
			testMode = {
				type = "toggle",
				name = "Test mode",
				desc = "Show all enabled icons with sample combat states",
				order = 2,
				get = function() return CT.testMode end,
				set = function(_, value) CT:SetTestMode(value) end,
			},
			display = { type = "header", name = "Display", order = 10 },
			inverted = {
				type = "toggle",
				name = "Inverted",
				desc = "Off: the icon is bright while the unit is OUT of combat (for example: it can be sapped) "
					.. "and dimmed in combat.\nOn: the icon is bright while the unit is IN combat.",
				order = 11,
			},
			showText = {
				type = "toggle",
				name = "Show unit names",
				desc = "Show the unit name on locked icons",
				order = 12,
			},
			showTimer = {
				type = "toggle",
				name = "Show timer",
				desc = "Show the seconds left on the combat swipe",
				order = 13,
			},
			onlyPlayers = {
				type = "toggle",
				name = "Only players",
				desc = "Do not track NPCs",
				order = 14,
			},
			hidePartyInRaid = {
				type = "toggle",
				name = "Hide party in raid",
				desc = "Hide the party icons while in a raid, where the party frames are hidden",
				order = 15,
			},
			attachToGladius = {
				type = "toggle",
				name = "Attach to Gladius",
				desc = "Attach the arena icons to the Gladius arena frames",
				order = 16,
				disabled = function() return Gladius == nil end,
			},
			inactiveAlpha = {
				type = "range",
				name = "Dimmed opacity",
				desc = "Opacity of a dimmed icon. 0 hides it.",
				min = 0, max = 1, step = 0.05, isPercent = true,
				order = 20,
			},
			scale = {
				type = "range",
				name = "Icon scale",
				min = 0.3, max = 3, step = 0.05,
				order = 21,
			},
			texture = {
				type = "select",
				name = "Icon",
				values = TextureValues,
				order = 22,
			},
			timerHeader = { type = "header", name = "Combat timer", order = 30 },
			timerInfo = {
				type = "description",
				name = function()
					local samples = CT:GetDurationSamples()
					local measured = CT.Core.EstimateDuration(samples)
					return format("A player leaves PvP combat %.2f s after the last hostile action. %s",
						CT.Core.duration,
						measured and format("Measured on this realm from %d combats.", #samples)
							or format("Not measured on this realm yet (%d of %d combats).", #samples, CT.Core.MIN_SAMPLES))
				end,
				order = 31,
			},
			timerOverride = {
				type = "range",
				name = "Manual duration",
				desc = "Seconds until a player leaves PvP combat. 0 uses the duration measured on the realm.",
				min = 0, max = 8, step = 0.05,
				order = 32,
				set = function(_, value)
					CT.db.profile.timerOverride = value
					CT:ApplyDuration()
					CT:ApplySettings()
				end,
			},
			timerReset = {
				type = "execute",
				name = "Measure again",
				desc = "Forget the durations measured on this realm",
				order = 33,
				func = function() CT:ResetDurationSamples() end,
			},
		},
	}

	options.args.sounds = {
		type = "group",
		name = "Sounds",
		order = 2,
		args = {
			playSounds = { type = "toggle", name = "Play sounds", width = "full", order = 1 },
			enterSound = {
				type = "select", dialogControl = "LSM30_Sound", values = AceGUIWidgetLSMlists.sound,
				name = "Unit enters combat", order = 2,
				disabled = function() return not CT.db.profile.playSounds end,
			},
			leaveSound = {
				type = "select", dialogControl = "LSM30_Sound", values = AceGUIWidgetLSMlists.sound,
				name = "Unit leaves combat", order = 3,
				disabled = function() return not CT.db.profile.playSounds end,
			},
			playerLeaveSound = {
				type = "select", dialogControl = "LSM30_Sound", values = AceGUIWidgetLSMlists.sound,
				name = "You leave combat", order = 4,
				disabled = function() return not CT.db.profile.playSounds end,
			},
		},
	}

	local units = { type = "group", name = "Units", order = 3, childGroups = "select", args = {} }
	for index, unit in ipairs(CT.UNITS) do
		units.args[unit] = UnitOptions(unit, index)
	end
	options.args.units = units

	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 4

	return options
end

function CT:RegisterOptions()
	LibStub("AceConfig-3.0"):RegisterOptionsTable("CombatTracking", self:BuildOptions())
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("CombatTracking", "CombatTracking")
end
