local STEP_HARD = "rbxasset://sounds/action_footsteps_plastic.mp3"
local STEP_WATER = "rbxasset://sounds/action_swim.mp3"
local IMPACT_METAL = "rbxasset://sounds/metal.ogg"
local IMPACT_STONE = "rbxasset://sounds/snap.wav"
local IMPACT_SOFT = "rbxasset://sounds/splat.wav"
local IMPACT_GLASS = "rbxasset://sounds/glassbreak.wav"
local IMPACT_WOOD = "rbxasset://sounds/clickfast.wav"
local IMPACT_WATER = "rbxasset://sounds/impact_water.mp3"
local IMPACT_FLESH = "rbxasset://sounds/hit.wav"

local Materials = {}

Materials.Default = {
	Name = "Generic",
	Density = 1,
	Sparks = false,
	Dust = Color3.fromRGB(168, 164, 155),
	Impact = IMPACT_STONE,
	Step = STEP_HARD,
	StepPitch = 1,
	Decal = true,
	RicochetChance = 0.12,
}

local function profile(overrides)
	local entry = table.clone(Materials.Default)
	for key, value in pairs(overrides) do
		entry[key] = value
	end
	return entry
end

Materials.Profiles = {
	[Enum.Material.Plastic] = profile({ Name = "Plastic", Density = 0.85, Dust = Color3.fromRGB(210, 210, 210), Impact = IMPACT_WOOD }),
	[Enum.Material.SmoothPlastic] = profile({ Name = "Plastic", Density = 0.85, Dust = Color3.fromRGB(210, 210, 210), Impact = IMPACT_WOOD }),
	[Enum.Material.Wood] = profile({ Name = "Wood", Density = 0.7, Dust = Color3.fromRGB(126, 92, 56), Impact = IMPACT_WOOD, StepPitch = 1.08, RicochetChance = 0.03 }),
	[Enum.Material.WoodPlanks] = profile({ Name = "Wood", Density = 0.65, Dust = Color3.fromRGB(146, 108, 66), Impact = IMPACT_WOOD, StepPitch = 1.12, RicochetChance = 0.03 }),
	[Enum.Material.Metal] = profile({ Name = "Metal", Density = 2.6, Sparks = true, Dust = Color3.fromRGB(228, 214, 178), Impact = IMPACT_METAL, StepPitch = 1.24, RicochetChance = 0.34 }),
	[Enum.Material.DiamondPlate] = profile({ Name = "Metal", Density = 2.9, Sparks = true, Dust = Color3.fromRGB(228, 214, 178), Impact = IMPACT_METAL, StepPitch = 1.2, RicochetChance = 0.38 }),
	[Enum.Material.CorrodedMetal] = profile({ Name = "Metal", Density = 2.1, Sparks = true, Dust = Color3.fromRGB(176, 118, 78), Impact = IMPACT_METAL, RicochetChance = 0.26 }),
	[Enum.Material.Concrete] = profile({ Name = "Concrete", Density = 2.2, Dust = Color3.fromRGB(186, 182, 174), Impact = IMPACT_STONE, RicochetChance = 0.18 }),
	[Enum.Material.Brick] = profile({ Name = "Brick", Density = 2, Dust = Color3.fromRGB(158, 96, 76), Impact = IMPACT_STONE, RicochetChance = 0.16 }),
	[Enum.Material.Slate] = profile({ Name = "Stone", Density = 2.4, Dust = Color3.fromRGB(120, 122, 128), Impact = IMPACT_STONE, RicochetChance = 0.22 }),
	[Enum.Material.Cobblestone] = profile({ Name = "Stone", Density = 2.3, Dust = Color3.fromRGB(140, 138, 132), Impact = IMPACT_STONE, RicochetChance = 0.2 }),
	[Enum.Material.Rock] = profile({ Name = "Stone", Density = 2.5, Dust = Color3.fromRGB(132, 130, 126), Impact = IMPACT_STONE, RicochetChance = 0.24 }),
	[Enum.Material.Basalt] = profile({ Name = "Stone", Density = 2.7, Dust = Color3.fromRGB(96, 94, 92), Impact = IMPACT_STONE, RicochetChance = 0.24 }),
	[Enum.Material.Glass] = profile({ Name = "Glass", Density = 0.3, Dust = Color3.fromRGB(222, 240, 248), Impact = IMPACT_GLASS, StepPitch = 1.3, RicochetChance = 0 }),
	[Enum.Material.Ice] = profile({ Name = "Ice", Density = 0.9, Dust = Color3.fromRGB(214, 236, 248), Impact = IMPACT_STONE, StepPitch = 1.26, RicochetChance = 0.1 }),
	[Enum.Material.Sand] = profile({ Name = "Sand", Density = 1.2, Dust = Color3.fromRGB(214, 196, 148), Impact = IMPACT_SOFT, StepPitch = 0.86, Decal = false, RicochetChance = 0.02 }),
	[Enum.Material.Grass] = profile({ Name = "Grass", Density = 0.9, Dust = Color3.fromRGB(112, 142, 76), Impact = IMPACT_SOFT, StepPitch = 0.9, Decal = false, RicochetChance = 0.02 }),
	[Enum.Material.LeafyGrass] = profile({ Name = "Grass", Density = 0.8, Dust = Color3.fromRGB(96, 132, 68), Impact = IMPACT_SOFT, StepPitch = 0.88, Decal = false, RicochetChance = 0.02 }),
	[Enum.Material.Ground] = profile({ Name = "Dirt", Density = 1.4, Dust = Color3.fromRGB(122, 100, 74), Impact = IMPACT_SOFT, StepPitch = 0.84, Decal = false, RicochetChance = 0.04 }),
	[Enum.Material.Mud] = profile({ Name = "Mud", Density = 1.1, Dust = Color3.fromRGB(88, 70, 52), Impact = IMPACT_SOFT, StepPitch = 0.78, Decal = false, RicochetChance = 0 }),
	[Enum.Material.Snow] = profile({ Name = "Snow", Density = 0.6, Dust = Color3.fromRGB(240, 244, 250), Impact = IMPACT_SOFT, StepPitch = 0.94, Decal = false, RicochetChance = 0 }),
	[Enum.Material.Sandstone] = profile({ Name = "Sandstone", Density = 1.8, Dust = Color3.fromRGB(198, 170, 128), Impact = IMPACT_STONE, RicochetChance = 0.14 }),
	[Enum.Material.Fabric] = profile({ Name = "Fabric", Density = 0.35, Dust = Color3.fromRGB(180, 172, 164), Impact = IMPACT_SOFT, StepPitch = 0.8, Decal = false, RicochetChance = 0 }),
	[Enum.Material.Foil] = profile({ Name = "Foil", Density = 0.5, Sparks = true, Dust = Color3.fromRGB(226, 226, 230), Impact = IMPACT_METAL, RicochetChance = 0.12 }),
	[Enum.Material.Water] = profile({ Name = "Water", Density = 1.6, Dust = Color3.fromRGB(150, 196, 224), Impact = IMPACT_WATER, Step = STEP_WATER, Decal = false, RicochetChance = 0.45 }),
}

Materials.Flesh = profile({
	Name = "Flesh",
	Density = 1.3,
	Dust = Color3.fromRGB(142, 24, 26),
	Impact = IMPACT_FLESH,
	Decal = false,
	RicochetChance = 0,
})

function Materials.For(material)
	return Materials.Profiles[material] or Materials.Default
end

function Materials.ForPart(part)
	if not part then
		return Materials.Default
	end
	local override = part:GetAttribute("SurfaceProfile")
	if override and Materials[override] then
		return Materials[override]
	end
	return Materials.For(part.Material)
end

function Materials.StepFor(part)
	local entry = Materials.ForPart(part)
	return entry.Step, entry.StepPitch
end

return Materials
