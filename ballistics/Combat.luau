local Players = game:GetService("Players")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Catalog = require(Sable.Data.Weapons)
local Enums = require(Sable.Data.Enums)
local Tuning = require(Sable.Data.Tuning)
local DamageModel = require(Sable.Data.Damage)
local Ballistics = require(Sable.Shared.Ballistics)

local Roster = require(script.Parent.Roster)
local Vitals = require(script.Parent.Vitals)
local Loadout = require(script.Parent.Loadout)

local HIT_TOLERANCE = 5.5
local MAX_CLAIMS = 12

local Combat = {}
Combat.Rejections = {}

local fireBudget = Net.Budget.new(18, 16)
local claimBudget = Net.Budget.new(90, 70)

local function reject(player, reason)
	local bucket = Combat.Rejections[player]
	if not bucket then
		bucket = {}
		Combat.Rejections[player] = bucket
	end
	bucket[reason] = (bucket[reason] or 0) + 1
	return false
end

local function validShape(payload)
	return type(payload) == "table"
		and type(payload.W) == "string"
		and typeof(payload.O) == "Vector3"
		and typeof(payload.D) == "Vector3"
		and payload.D.Magnitude > 0.1
		and Catalog.exists(payload.W)
end

local function latencyOf(player)
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and type(ping) == "number" then
		return math.clamp(ping, 0, Tuning.Combat.LagCompensationWindow)
	end
	return 0.06
end

local function partRadius(part)
	return part.Size.Magnitude * 0.5 + 0.6
end

local function verifyClaim(shooter, origin, claim, latency)
	if typeof(claim) ~= "table" then
		return nil
	end

	local part = claim.P
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil
	end

	local character = part:FindFirstAncestorOfClass("Model")
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return nil
	end

	local victim = Players:GetPlayerFromCharacter(character)
	if not victim or victim == shooter then
		return nil
	end

	local state = Vitals.States[victim]
	if not state or state.Dead then
		return nil
	end

	local limb = DamageModel.limbFor(part.Name)
	if not limb then
		return nil
	end

	local rewound = Roster.rewoundPosition(victim, part, latency)
	local claimed = typeof(claim.X) == "Vector3" and claim.X or rewound

	if (claimed - rewound).Magnitude > partRadius(part) + HIT_TOLERANCE then
		return nil
	end

	local distance = (rewound - origin).Magnitude
	if distance > Tuning.Combat.MaxTraceDistance then
		return nil
	end

	if not Ballistics.visible(origin, rewound, { shooter.Character, character }) then
		return nil
	end

	return {
		Victim = victim,
		Character = character,
		Part = part,
		Limb = limb,
		Distance = distance,
		Position = rewound,
		Energy = math.clamp(tonumber(claim.E) or 1, 0.05, 1),
	}
end

function Combat.handleFire(shooter, payload)
	if not validShape(payload) then
		return reject(shooter, Enums.Reject.Unknown)
	end

	if not fireBudget:Consume(shooter) then
		return reject(shooter, Enums.Reject.Cadence)
	end

	local rig = Roster.rigOf(shooter)
	local vitals = Vitals.States[shooter]
	if not rig or not rig:IsAlive() or not vitals or vitals.Dead or vitals.Downed then
		return reject(shooter, Enums.Reject.Dead)
	end

	local slot = Loadout.activeSlot(shooter)
	if not slot or slot.Id ~= payload.W then
		return reject(shooter, Enums.Reject.Ammo)
	end

	local weapon = Catalog.get(slot.Id)
	local state = Loadout.stateFor(shooter)
	local now = os.clock()

	if now - state.LastFire < weapon.Fire.Interval * Tuning.Combat.CadenceTolerance then
		return reject(shooter, Enums.Reject.Cadence)
	end

	if weapon.Fire.RequiresCycle and not slot.Cycled then
		return reject(shooter, Enums.Reject.Ammo)
	end

	if state.Reload then
		Loadout.abortReload(shooter)
	end

	if not Loadout.consume(shooter, slot.Id, 1) then
		return reject(shooter, Enums.Reject.Ammo)
	end

	local eye = rig:EyeCFrame().Position
	if (payload.O - eye).Magnitude > Tuning.Combat.OriginTolerance then
		return reject(shooter, Enums.Reject.Origin)
	end

	state.LastFire = now
	state.Shots += 1

	local terminal = payload.O + payload.D.Unit * math.min(tonumber(payload.L) or 300, Tuning.Combat.MaxTraceDistance)
	Net.BroadcastExcept(shooter, "BroadcastShot", shooter, slot.Id, payload.O, terminal)

	local claims = payload.H
	if type(claims) ~= "table" then
		return true
	end

	local latency = latencyOf(shooter)
	local armInjury = Vitals.armInjury(shooter)
	local counted = {}
	local applied = 0

	for index = 1, math.min(#claims, MAX_CLAIMS) do
		if not claimBudget:Consume(shooter) then
			break
		end

		local verified = verifyClaim(shooter, payload.O, claims[index], latency)
		if verified then
			local seen = counted[verified.Victim] or 0
			if seen < (weapon.Fire.Pellets or 1) then
				counted[verified.Victim] = seen + 1

				local victimState = Vitals.stateFor(verified.Victim)
				local resolved = DamageModel.resolve({
					Weapon = weapon,
					Limb = verified.Limb,
					Distance = verified.Distance,
					MediumScale = verified.Energy,
					Armor = victimState.Armor,
					Roll = math.random(),
				})

				Vitals.apply(verified.Victim, shooter, resolved, { Position = verified.Position })
				applied += 1
			end
		end
	end

	if armInjury > 0 and applied > 0 then
		state.Shots += 0
	end

	return true
end

function Combat.start()
	Net.On("FireShot", function(player, payload)
		local ok, err = pcall(Combat.handleFire, player, payload)
		if not ok then
			warn("[Combat] fire handler error: " .. tostring(err))
		end
	end)

	Net.On("SetAimState", function(player, aiming, pitch)
		if typeof(aiming) ~= "boolean" then
			return
		end
		local entry = Roster.get(player)
		if not entry then
			return
		end
		entry.State.Aiming = aiming
		entry.State.Pitch = math.clamp(tonumber(pitch) or 0, -1.6, 1.6)
		Net.BroadcastExcept(player, "SetAimState", player, aiming, entry.State.Pitch)
	end)

	Net.On("SetStance", function(player, stance, motion)
		if typeof(stance) ~= "string" or not Enums.Stance[stance] then
			return
		end

		local entry = Roster.get(player)
		if not entry then
			return
		end

		entry.State.Stance = stance
		entry.State.Motion = motion

		local rig = entry.Rig
		if rig and rig.Humanoid.Parent then
			rig.Character:SetAttribute("Stance", stance)
			rig.Character:SetAttribute("Motion", motion)
		end
	end)

	Net.On("SetLook", function(player, pitch)
		local entry = Roster.get(player)
		if not entry then
			return
		end
		local clamped = math.clamp(tonumber(pitch) or 0, -1.6, 1.6)
		entry.State.Pitch = clamped
		if entry.Character then
			entry.Character:SetAttribute("LookPitch", clamped)
		end
		Net.BroadcastExcept(player, "SetLook", player, clamped)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Combat.Rejections[player] = nil
		fireBudget:Forget(player)
		claimBudget:Forget(player)
	end)
end

return Combat
