local Util = require(script.Parent.Parent.Lib.Util)
local Enums = require(script.Parent.Enums)

local Damage = {}

Damage.LimbMultiplier = {
	[Enums.Limb.Head] = 1.45,
	[Enums.Limb.Torso] = 1,
	[Enums.Limb.RightArm] = 0.75,
	[Enums.Limb.LeftArm] = 0.75,
	[Enums.Limb.RightLeg] = 0.75,
	[Enums.Limb.LeftLeg] = 0.75,
}

Damage.LimbAlias = {
	Head = Enums.Limb.Head,
	Torso = Enums.Limb.Torso,
	HumanoidRootPart = Enums.Limb.Torso,
	UpperTorso = Enums.Limb.Torso,
	LowerTorso = Enums.Limb.Torso,
	["Right Arm"] = Enums.Limb.RightArm,
	["Left Arm"] = Enums.Limb.LeftArm,
	["Right Leg"] = Enums.Limb.RightLeg,
	["Left Leg"] = Enums.Limb.LeftLeg,
	RightUpperArm = Enums.Limb.RightArm,
	RightLowerArm = Enums.Limb.RightArm,
	RightHand = Enums.Limb.RightArm,
	LeftUpperArm = Enums.Limb.LeftArm,
	LeftLowerArm = Enums.Limb.LeftArm,
	LeftHand = Enums.Limb.LeftArm,
	RightUpperLeg = Enums.Limb.RightLeg,
	RightLowerLeg = Enums.Limb.RightLeg,
	RightFoot = Enums.Limb.RightLeg,
	LeftUpperLeg = Enums.Limb.LeftLeg,
	LeftLowerLeg = Enums.Limb.LeftLeg,
	LeftFoot = Enums.Limb.LeftLeg,
}

Damage.BleedChance = {
	[Enums.Limb.Head] = 0.9,
	[Enums.Limb.Torso] = 0.55,
	[Enums.Limb.RightArm] = 0.4,
	[Enums.Limb.LeftArm] = 0.4,
	[Enums.Limb.RightLeg] = 0.45,
	[Enums.Limb.LeftLeg] = 0.45,
}

Damage.ArmorCoverage = {
	[Enums.Limb.Head] = 0,
	[Enums.Limb.Torso] = 1,
	[Enums.Limb.RightArm] = 0.35,
	[Enums.Limb.LeftArm] = 0.35,
	[Enums.Limb.RightLeg] = 0,
	[Enums.Limb.LeftLeg] = 0,
}

function Damage.limbFor(partName)
	return Damage.LimbAlias[partName]
end

function Damage.falloff(profile, distance)
	if not profile or #profile == 0 then
		return 1
	end
	return Util.curve(profile, distance)
end

function Damage.resolve(request)
	local weapon = request.Weapon
	local limb = request.Limb or Enums.Limb.Torso
	local profile = weapon.Damage

	local base = profile.Base
	local ranged = base * Damage.falloff(profile.Falloff, request.Distance or 0)
	local limbScaled = ranged * (Damage.LimbMultiplier[limb] or 1)
	local afterMedium = limbScaled * math.clamp(request.MediumScale or 1, 0, 1)

	local armor = request.Armor or 0
	local coverage = Damage.ArmorCoverage[limb] or 0
	local absorbed = 0

	if armor > 0 and coverage > 0 then
		local pierce = math.clamp(profile.ArmorPierce or 0.5, 0, 1)
		local blocked = afterMedium * coverage * (1 - pierce)
		absorbed = math.min(armor, blocked)
	end

	local final = math.max(afterMedium - absorbed, afterMedium * 0.08)

	return {
		Amount = final,
		ArmorLost = absorbed,
		Limb = limb,
		LethalBias = limb == Enums.Limb.Head and 1 or 0,
		Fracture = final >= (profile.FractureThreshold or 34) and limb ~= Enums.Limb.Torso,
		Bleed = (request.Roll or math.random()) < (Damage.BleedChance[limb] or 0) * (profile.BleedScale or 1),
	}
end

function Damage.stagger(amount, limb)
	local base = math.clamp(amount / 45, 0, 1)
	if limb == Enums.Limb.Head then
		base *= 1.6
	end
	return math.clamp(base, 0, 1.4)
end

return Damage
