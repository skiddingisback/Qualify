local Util = require(script.Parent.Parent.Lib.Util)
local Enums = require(script.Parent.Enums)

local Catalog = {}

local Archetype = {}

Archetype.Base = {
	Slot = Enums.Slot.Primary,
	Ammo = { Magazine = 30, Reserve = 180, Chambered = true, Caliber = "5.56" },
	Fire = {
		Modes = { Enums.FireMode.Auto },
		DefaultMode = Enums.FireMode.Auto,
		Rpm = 600,
		BurstCount = 3,
		BurstCooldown = 0.16,
		Pellets = 1,
		PelletSpread = 0,
		Velocity = 780,
		RequiresCycle = false,
		CycleTime = 0,
	},
	Damage = {
		Base = 24,
		Falloff = { { 0, 1 }, { 70, 1 }, { 180, 0.66 }, { 320, 0.48 } },
		ArmorPierce = 0.5,
		Penetration = 2,
		PenetrationLoss = 0.34,
		FractureThreshold = 34,
		BleedScale = 1,
	},
	Spread = {
		Hip = 1.9,
		Ads = 0.12,
		Move = 1.4,
		Air = 3.2,
		Crouch = -0.42,
		Prone = -0.7,
		PerShot = 0.24,
		Max = 5.5,
		Recovery = 4.4,
		RecoveryDelay = 0.09,
	},
	Recoil = {
		Vertical = 1,
		Horizontal = 0.42,
		Pattern = { { 1, 0 } },
		CameraScale = 1,
		ViewScale = 1,
		Recovery = 0.72,
		AdsScale = 0.62,
		AdsVisualScale = 0.7,
		AdsModelDamp = 0.45,
		Jitter = 0.12,
		Punch = 0.16,
		Rise = 0.34,
		Spray = { Pitch = 1.2, Yaw = 0.4, Roll = 1.2 },
	},
	Handling = {
		Draw = 0.55,
		Stow = 0.35,
		AdsIn = 0.2,
		AdsOut = 0.16,
		Inspect = 2.4,
		Weight = 0.94,
		AdsSpeed = 0.6,
		SprintBlocked = false,
		SwayWeight = 1,
	},
	Reload = {
		Kind = "Magazine",
		Duration = 2.3,
		EmptyDuration = 2.9,
		ChamberDuration = 0.35,
		Cues = {},
		EmptyCues = {},
	},
	Sights = {
		Attachment = "ADS_FirePos",
		Fov = 58,
		Offset = CFrame.new(0, 0, 0),
		EyeRelief = 0.2,
		Snap = 0.86,
	},
	Hip = {
		Position = Vector3.new(0.265, -0.151, -0.039),
		Rotation = Vector3.new(-4.1, -4, -3.4),
	},
	Crouch = {
		Position = Vector3.new(0.15, -0.25, 0),
		Rotation = Vector3.new(0, 0, 25),
	},
	Anim = {
		Idle = "Idle",
		Fire = "Fire",
		AimFire = "AimFire",
		Reload = "Reload",
		Equip = "Equip",
		Holster = "Holster",
		Run = "Run",
		Inspect = "Inspect",
	},
	Shell = {
		Enabled = true,
		Size = Vector3.new(0.08, 0.08, 0.22),
		Color = Color3.fromRGB(196, 158, 74),
		Material = Enum.Material.Metal,
		Force = 9,
		Spin = 22,
		Life = 3.5,
		Delay = 0,
	},
	Fx = {
		TracerWidth = 0.055,
		TracerColor = Color3.fromRGB(255, 226, 150),
		TracerLife = 0.055,
		TracerChance = 0.4,
		LightRange = 13,
		LightBrightness = 3.4,
		FlashDuration = 0.045,
		Shake = 0.6,
		AudibleRadius = 420,
	},
}

local function define(id, overrides)
	local entry = Util.merge(Archetype.Base, overrides)
	entry.Id = id
	entry.Fire.Interval = 60 / entry.Fire.Rpm
	Catalog[id] = entry
	return entry
end

define("M4A1", {
	DisplayName = "M4A1",
	Class = "Assault Rifle",
	Model = "M4A1",
	Slot = Enums.Slot.Primary,
	Ammo = { Magazine = 30, Reserve = 90, Chambered = true, Caliber = "5.56x45" },
	Fire = {
		Modes = { Enums.FireMode.Auto, Enums.FireMode.Burst, Enums.FireMode.Semi },
		DefaultMode = Enums.FireMode.Auto,
		Rpm = 510,
		BurstCount = 3,
		BurstCooldown = 0.19,
		Velocity = 910,
	},
	Damage = {
		Base = 21,
		Falloff = { { 0, 1 }, { 120, 1 }, { 400, 0.86 }, { 1000, 0.7 } },
		ArmorPierce = 0.7,
		Penetration = 3.4,
		PenetrationLoss = 0.22,
		FractureThreshold = 30,
	},
	Spread = {
		Hip = 1.75,
		Ads = 0.09,
		Move = 1.25,
		Air = 3,
		Crouch = -0.38,
		Prone = -0.62,
		PerShot = 0.2,
		Max = 5.2,
		Recovery = 4.6,
	},
	Recoil = {
		Vertical = 0.82,
		Horizontal = 1,
		CameraScale = 1,
		ViewScale = 1,
		Recovery = 0.92,
		AdsScale = 0.4,
		AdsVisualScale = 1.85,
		AdsModelDamp = 0.45,
		Jitter = 0.05,
		Punch = 0.26,
		Rise = 0.5,
		Spray = { Pitch = 1.3, Yaw = 0.45, Roll = 1.75 },
		Pattern = {
			{ 1, 0 }, { 2.1, 0.1 }, { 3.3, 0.3 }, { 4.5, 0.6 }, { 5.6, 0.9 },
			{ 6.6, 1.3 }, { 7.5, 1.7 }, { 8.3, 2 }, { 9, 2.2 }, { 9.6, 2.3 },
			{ 10.1, 2.2 }, { 10.6, 1.9 }, { 11, 1.5 }, { 11.4, 1 }, { 11.7, 0.4 },
			{ 12, -0.2 }, { 12.3, -0.8 }, { 12.5, -1.4 }, { 12.7, -1.9 }, { 12.9, -2.2 },
			{ 13.1, -2.4 }, { 13.3, -2.4 }, { 13.4, -2.2 }, { 13.5, -1.9 }, { 13.6, -1.5 },
			{ 13.7, -1 }, { 13.8, -0.5 }, { 13.9, 0 }, { 14, 0.5 }, { 14.1, 1 },
		},
	},
	Handling = {
		Draw = 1.73,
		Stow = 0.55,
		AdsIn = 0.45,
		AdsOut = 0.32,
		Inspect = 5.66,
		Weight = 0.92,
		AdsSpeed = 0.65,
		SwayWeight = 1.1,
	},
	Reload = {
		Kind = "Magazine",
		Duration = 3.45,
		EmptyDuration = 4.03,
		Cues = {
			{ 0.2, "MagOut" },
			{ 0.5, "MagIn" },
			{ 0.6, "MagHit" },
		},
		EmptyCues = {
			{ 0.2, "MagOut" },
			{ 0.5, "MagIn" },
			{ 0.6, "MagHit" },
			{ 0.78, "BoltBack" },
			{ 0.87, "BoltRelease" },
		},
	},
	Sights = { Fov = 55, Snap = 0.9, EyeRelief = -0.4, Offset = CFrame.new(0.054, -0.29, 0) },
	Hip = { Position = Vector3.new(0.265, -0.151, -0.039), Rotation = Vector3.new(-4.1, -4, -3.4) },
	Crouch = { Position = Vector3.new(0.16, -0.26, 0.02), Rotation = Vector3.new(0, 0, 24) },
	Anim = { ModeSwitch = "FiremodeChange", RunIn = "IdleToRun" },
	Shell = { Size = Vector3.new(0.08, 0.08, 0.24), Force = 11, Life = 4 },
	Fx = {
		TracerChance = 1,
		TracerColor = Color3.fromRGB(255, 89, 89),
		TracerLife = 0.125,
		LightRange = 7,
		LightBrightness = 3,
		FlashDuration = 0.075,
		Shake = 0.62,
	},
})

define("Deagle", {
	DisplayName = "Desert Eagle",
	Class = "Hand Cannon",
	Model = "Deagle",
	Slot = Enums.Slot.Secondary,
	Ammo = { Magazine = 7, Reserve = 49, Chambered = true, Caliber = ".50 AE" },
	Fire = {
		Modes = { Enums.FireMode.Semi },
		DefaultMode = Enums.FireMode.Semi,
		Rpm = 260,
		Velocity = 470,
	},
	Damage = {
		Base = 58,
		Falloff = { { 0, 1 }, { 40, 1 }, { 110, 0.7 }, { 200, 0.44 } },
		ArmorPierce = 0.66,
		Penetration = 2.2,
		PenetrationLoss = 0.42,
		FractureThreshold = 26,
		BleedScale = 1.25,
	},
	Spread = {
		Hip = 2.6,
		Ads = 0.1,
		Move = 1.9,
		Air = 4.1,
		Crouch = -0.55,
		Prone = -0.8,
		PerShot = 1.35,
		Max = 7,
		Recovery = 5.4,
		RecoveryDelay = 0.14,
	},
	Recoil = {
		Vertical = 2.65,
		Horizontal = 0.85,
		CameraScale = 1.35,
		ViewScale = 1.35,
		Recovery = 0.9,
		AdsScale = 0.78,
		AdsVisualScale = 1.35,
		AdsModelDamp = 0.4,
		Jitter = 0.07,
		Punch = 0.42,
		Rise = 0.55,
		Spray = { Pitch = 5.4, Yaw = 1.3, Roll = 4.2 },
		Pattern = {
			{ 1, -0.3 }, { 2.05, 0.1 }, { 3.15, -0.4 }, { 4.3, 0.2 },
			{ 5.5, -0.5 }, { 6.7, 0.25 }, { 7.9, -0.55 },
		},
	},
	Handling = {
		Draw = 1.43,
		Stow = 0.3,
		AdsIn = 0.16,
		AdsOut = 0.13,
		Inspect = 5.63,
		Weight = 0.99,
		AdsSpeed = 0.72,
		SwayWeight = 0.78,
	},
	Reload = {
		Kind = "Magazine",
		Duration = 2.65,
		EmptyDuration = 3.53,
		ChamberAnim = "SlideBack",
		ChamberDuration = 0.35,
		Cues = {
			{ 0.18, "MagOut" },
			{ 0.52, "MagIn" },
		},
		EmptyCues = {
			{ 0.18, "MagOut" },
			{ 0.5, "MagIn" },
			{ 0.84, "SlideBack" },
			{ 0.92, "SlideIn" },
		},
	},
	Sights = { Fov = 71, Snap = 0.94, EyeRelief = -1.619, Offset = CFrame.new(-0.014, 0.161, 0) },
	Hip = { Position = Vector3.new(0.265, -0.151, -0.039), Rotation = Vector3.new(-4.1, -4, -3.4) },
	Crouch = { Position = Vector3.new(0.11, -0.2, 0), Rotation = Vector3.new(0, 0, 18) },
	Shell = { Size = Vector3.new(0.11, 0.11, 0.26), Color = Color3.fromRGB(214, 176, 92), Force = 13, Spin = 30, Life = 4 },
	Fx = { TracerChance = 0.7, TracerWidth = 0.07, LightRange = 19, LightBrightness = 4.6, Shake = 1.6, FlashDuration = 0.06 },
})

define("R870", {
	DisplayName = "Remington 870",
	Class = "Pump Shotgun",
	Model = "R870",
	Slot = Enums.Slot.Primary,
	Ammo = { Magazine = 6, Reserve = 42, Chambered = false, Caliber = "12 Gauge" },
	Fire = {
		Modes = { Enums.FireMode.Pump },
		DefaultMode = Enums.FireMode.Pump,
		Rpm = 78,
		Pellets = 9,
		PelletSpread = 2.6,
		Velocity = 380,
		RequiresCycle = true,
		CycleTime = 0.6,
	},
	Damage = {
		Base = 15,
		Falloff = { { 0, 1 }, { 18, 1 }, { 45, 0.55 }, { 90, 0.2 }, { 140, 0.08 } },
		ArmorPierce = 0.3,
		Penetration = 1.1,
		PenetrationLoss = 0.7,
		FractureThreshold = 22,
		BleedScale = 1.6,
	},
	Spread = {
		Hip = 1.1,
		Ads = 0.5,
		Move = 0.8,
		Air = 1.9,
		Crouch = -0.3,
		Prone = -0.5,
		PerShot = 0.6,
		Max = 4,
		Recovery = 3,
		RecoveryDelay = 0.2,
	},
	Recoil = {
		Vertical = 3.4,
		Horizontal = 0.7,
		CameraScale = 1.55,
		ViewScale = 1.5,
		Recovery = 1.05,
		AdsScale = 0.85,
		AdsVisualScale = 1.4,
		AdsModelDamp = 0.35,
		Jitter = 0.08,
		Punch = 0.55,
		Rise = 0.7,
		Spray = { Pitch = 7, Yaw = 1.5, Roll = 5.5 },
		Pattern = { { 1, -0.2 }, { 2.05, 0.1 }, { 3.15, -0.25 }, { 4.25, 0.15 } },
	},
	Handling = {
		Draw = 1.3,
		Stow = 0.35,
		AdsIn = 0.24,
		AdsOut = 0.19,
		Inspect = 4.56,
		Weight = 0.9,
		AdsSpeed = 0.52,
		SwayWeight = 1.2,
	},
	Reload = {
		Kind = "Shell",
		StartDuration = 0.3,
		StepDuration = 0.76,
		EndDuration = 0.53,
		ShellsPerStep = 1,
		Interruptible = true,
		StepCues = { { 0.3, "ShellIn" } },
		EndCues = { { 0.2, "PumpBack" }, { 0.6, "PumpForward" } },
	},
	Sights = { Fov = 49, Snap = 0.82, EyeRelief = -0.95, Offset = CFrame.new(-0.022, -0.036, 0) },
	Hip = { Position = Vector3.new(0.265, -0.151, -0.039), Rotation = Vector3.new(-4.1, -4, -3.4) },
	Crouch = { Position = Vector3.new(0.18, -0.28, 0.03), Rotation = Vector3.new(0, 0, 27) },
	Anim = {
		Cycle = "Pump",
		ReloadStart = "ReloadStart",
		ReloadStep = "Shell_in",
		ReloadEnd = "ReloadEnd",
	},
	CycleCues = { { 0.22, "PumpBack" }, { 0.62, "PumpForward" } },
	Shell = { Size = Vector3.new(0.16, 0.16, 0.42), Color = Color3.fromRGB(158, 32, 34), Force = 8, Spin = 14, Life = 5, Delay = 0.24 },
	Fx = { TracerChance = 0.12, TracerWidth = 0.04, LightRange = 22, LightBrightness = 5.2, Shake = 2, FlashDuration = 0.07 },
})

local function poseFrame(pose)
	return CFrame.new(pose.Position)
		* CFrame.Angles(math.rad(pose.Rotation.X), math.rad(pose.Rotation.Y), math.rad(pose.Rotation.Z))
end

function Catalog.hipFrame(weapon)
	return poseFrame(weapon.Hip)
end

function Catalog.crouchFrame(weapon)
	return poseFrame(weapon.Crouch)
end

function Catalog.get(id)
	local entry = Catalog[id]
	if not entry then
		error("[Weapons] unknown weapon id: " .. tostring(id), 2)
	end
	return entry
end

function Catalog.exists(id)
	return type(id) == "string" and rawget(Catalog, id) ~= nil and type(rawget(Catalog, id)) == "table"
end

function Catalog.list()
	local ids = {}
	for id, value in pairs(Catalog) do
		if type(value) == "table" and value.Id then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local ORIGIN_STEP = { 0, 0 }

function Catalog.recoilStep(weapon, shotIndex)
	local recoil = weapon.Recoil
	local pattern = recoil.Pattern
	local index = (math.max(shotIndex, 1) - 1) % #pattern + 1
	local current = pattern[index]
	local previous = index > 1 and pattern[index - 1] or ORIGIN_STEP

	return (current[1] - previous[1]) * recoil.Vertical,
		(current[2] - previous[2]) * recoil.Horizontal
end

return Catalog
