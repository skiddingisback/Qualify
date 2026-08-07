local Tuning = require(script.Parent.Parent.Data.Tuning)
local Materials = require(script.Parent.Parent.Data.Materials)
local Enums = require(script.Parent.Parent.Data.Enums)
local Rig = require(script.Parent.Rig)

local SEGMENT_LENGTH = 48
local MAX_SEGMENTS = 40
local SURFACE_EPSILON = 0.02
local MAX_THICKNESS = 12
local FLESH_COST = 1.15

local Ballistics = {}

local function makeParams(ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = false
	return params
end

local function measureThickness(instance, entry, direction)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { instance }
	params.IgnoreWater = true

	local probeStart = entry + direction * MAX_THICKNESS
	local result = workspace:Raycast(probeStart, -direction * MAX_THICKNESS, params)
	if not result then
		return nil
	end

	local thickness = (result.Position - entry).Magnitude
	if thickness < 1e-3 then
		thickness = 1e-3
	end
	return thickness, result.Position
end

function Ballistics.spreadDirection(direction, degrees, rng)
	if degrees <= 0 then
		return direction
	end
	local radians = math.rad(degrees)
	local x, y = rng:UnitDisc()
	local tangent = math.tan(radians)
	local frame = CFrame.lookAt(Vector3.zero, direction)
	local offset = frame.RightVector * (x * tangent) + frame.UpVector * (y * tangent)
	return (direction + offset).Unit
end

function Ballistics.pelletFan(weapon, direction, spreadDegrees, rng)
	local count = weapon.Fire.Pellets or 1
	local fan = table.create(count)
	local cone = spreadDegrees + (weapon.Fire.PelletSpread or 0)

	for index = 1, count do
		if index == 1 and count > 1 then
			fan[index] = Ballistics.spreadDirection(direction, cone * 0.35, rng)
		else
			fan[index] = Ballistics.spreadDirection(direction, cone, rng)
		end
	end
	return fan
end

local function classify(instance)
	local character = Rig.characterOf(instance)
	if character then
		return character, Materials.Flesh
	end
	return nil, Materials.ForPart(instance)
end

function Ballistics.trace(request)
	local weapon = request.Weapon
	local ignore = table.clone(request.Ignore or {})
	local params = makeParams(ignore)

	local speed = math.max(weapon.Fire.Velocity or 700, 60)
	local gravity = Vector3.new(0, -workspace.Gravity * (request.GravityScale or 0.24), 0)
	local velocity = request.Direction.Unit * speed

	local cursor = request.Origin
	local remaining = math.min(request.MaxDistance or Tuning.Combat.MaxTraceDistance, Tuning.Combat.MaxTraceDistance)
	local budget = weapon.Damage.Penetration
	local energy = 1
	local travelled = 0
	local ricochets = 0

	local segments = {}
	local impacts = {}
	local victims = {}
	local segmentStart = cursor

	for _ = 1, MAX_SEGMENTS do
		if remaining <= 0.5 or energy <= 0.08 then
			break
		end

		local stepLength = math.min(SEGMENT_LENGTH, remaining)
		local dt = stepLength / speed
		local displacement = velocity * dt + gravity * (0.5 * dt * dt)
		local result = workspace:Raycast(cursor, displacement, params)

		if not result then
			cursor += displacement
			velocity += gravity * dt
			travelled += displacement.Magnitude
			remaining -= stepLength
			continue
		end

		local direction = displacement.Unit
		local hitDistance = (result.Position - cursor).Magnitude
		travelled += hitDistance
		remaining -= hitDistance

		local character, profile = classify(result.Instance)

		table.insert(segments, { From = segmentStart, To = result.Position, Energy = energy })

		local impact = {
			Position = result.Position,
			Normal = result.Normal,
			Instance = result.Instance,
			Material = result.Material,
			Profile = profile,
			Distance = travelled,
			Energy = energy,
			Direction = direction,
			Character = character,
			Kind = character and Enums.HitKind.Character or Enums.HitKind.World,
		}
		table.insert(impacts, impact)

		if character then
			if not victims[character] then
				victims[character] = impact
			end
			table.insert(ignore, character)
			params.FilterDescendantsInstances = ignore

			budget -= FLESH_COST
			energy *= 0.62
			if budget <= 0 or energy <= 0.15 then
				break
			end

			cursor = result.Position + direction * SURFACE_EPSILON
			segmentStart = cursor
			continue
		end

		local grazing = math.abs(direction:Dot(result.Normal))
		local shallow = grazing < math.sin(Tuning.Combat.RicochetAngle)

		if shallow and ricochets < 1 and request.AllowRicochet ~= false and math.random() < profile.RicochetChance then
			ricochets += 1
			energy *= 1 - Tuning.Combat.RicochetLoss
			impact.Kind = Enums.HitKind.Ricochet

			local reflected = direction - 2 * direction:Dot(result.Normal) * result.Normal
			velocity = reflected.Unit * speed * energy
			cursor = result.Position + result.Normal * 0.05
			segmentStart = cursor
			continue
		end

		local thickness, exit = measureThickness(result.Instance, result.Position, direction)
		local cost = thickness and thickness * profile.Density or math.huge

		if cost <= budget and exit then
			budget -= cost
			impact.Kind = Enums.HitKind.Penetrated
			impact.Exit = exit
			energy *= math.clamp(1 - weapon.Damage.PenetrationLoss * (cost / math.max(weapon.Damage.Penetration, 0.01)), 0.05, 1)

			table.insert(ignore, result.Instance)
			params.FilterDescendantsInstances = ignore

			cursor = exit + direction * SURFACE_EPSILON
			segmentStart = cursor
			velocity = direction * speed
			continue
		end

		break
	end

	if #segments == 0 or segments[#segments].To ~= cursor then
		if remaining > 0.5 and #impacts == 0 then
			table.insert(segments, { From = segmentStart, To = cursor, Energy = energy })
		end
	end

	return {
		Segments = segments,
		Impacts = impacts,
		Victims = victims,
		Terminal = cursor,
		Energy = energy,
		Distance = travelled,
	}
end

function Ballistics.firstVictim(trace)
	for _, impact in ipairs(trace.Impacts) do
		if impact.Character then
			return impact
		end
	end
	return nil
end

function Ballistics.visible(origin, target, ignore)
	local delta = target - origin
	local result = workspace:Raycast(origin, delta, makeParams(ignore))
	if not result then
		return true
	end
	return (result.Position - target).Magnitude < 2.5
end

return Ballistics
