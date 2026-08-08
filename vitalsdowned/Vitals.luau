local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Signal = require(Sable.Lib.Signal)
local Enums = require(Sable.Data.Enums)
local Tuning = require(Sable.Data.Tuning)
local Damage = require(Sable.Data.Damage)

local Roster = require(script.Parent.Roster)

local legacyEvents = game:GetService("ReplicatedStorage"):WaitForChild("Events")
local flinchEvent = legacyEvents:WaitForChild("OnFlinched")
local limbEvent = legacyEvents:WaitForChild("OHNRGEE")

local Vitals = {}
Vitals.States = {}
Vitals.Downed = Signal.new("Downed")
Vitals.Killed = Signal.new("Killed")
Vitals.Revived = Signal.new("Revived")

local function freshLimbs()
	local limbs = {}
	for _, limb in ipairs(Enums.LimbList) do
		limbs[limb] = {
			Health = Tuning.Vitals.LimbHealth,
			Max = Tuning.Vitals.LimbHealth,
			Broken = false,
			Bleeding = 0,
		}
	end
	return limbs
end

local function freshState(player)
	return {
		Player = player,
		Health = Tuning.Vitals.MaxHealth,
		MaxHealth = Tuning.Vitals.MaxHealth,
		Armor = 0,
		MaxArmor = 60,
		Limbs = freshLimbs(),
		Downed = false,
		Dead = false,
		LastDamageAt = 0,
		DownedAt = 0,
		ReviveProgress = 0,
	}
end

function Vitals.stateFor(player)
	local state = Vitals.States[player]
	if not state then
		state = freshState(player)
		Vitals.States[player] = state
	end
	return state
end

local function packet(state)
	local limbs = {}
	for limb, data in pairs(state.Limbs) do
		limbs[limb] = { data.Health, data.Broken and 1 or 0, data.Bleeding }
	end
	return {
		Health = state.Health,
		MaxHealth = state.MaxHealth,
		Armor = state.Armor,
		Downed = state.Downed,
		Dead = state.Dead,
		Limbs = limbs,
	}
end

function Vitals.push(player)
	local state = Vitals.States[player]
	if state then
		Net.To(player, "VitalsChanged", packet(state))
	end
end

local function brokenLegCount(state)
	local count = 0
	if state.Limbs[Enums.Limb.RightLeg].Broken then count += 1 end
	if state.Limbs[Enums.Limb.LeftLeg].Broken then count += 1 end
	return count
end

function Vitals.mobilityScale(player)
	local state = Vitals.States[player]
	if not state then
		return 1
	end
	if state.Downed then
		return 0
	end
	return math.max(1 - brokenLegCount(state) * Tuning.Vitals.BrokenLimbSpeedPenalty, 0.3)
end

function Vitals.armInjury(player)
	local state = Vitals.States[player]
	if not state then
		return 0
	end
	local injury = 0
	if state.Limbs[Enums.Limb.RightArm].Broken then injury += 0.6 end
	if state.Limbs[Enums.Limb.LeftArm].Broken then injury += 0.4 end
	return injury
end

local function syncHumanoid(player, state)
	local rig = Roster.rigOf(player)
	if not rig or not rig.Humanoid.Parent then
		return
	end

	local humanoid = rig.Humanoid
	if state.Dead then
		humanoid.Health = 0
		return
	end

	local display = state.Downed and math.max(state.Health, 1) or state.Health
	humanoid.Health = math.clamp(display, 1, humanoid.MaxHealth)
end

function Vitals.enterDowned(player, state, killer)
	if state.Downed or state.Dead then
		return
	end
	state.Downed = true
	state.DownedAt = os.clock()
	state.Health = Tuning.Vitals.DownedHealth
	state.ReviveProgress = 0

	Vitals.Downed:Fire(player, killer)
	Net.Broadcast("Downed", player, true)
	Vitals.push(player)
end

function Vitals.kill(player, state, killer)
	if state.Dead then
		return
	end
	state.Dead = true
	state.Downed = false
	state.Health = 0

	Vitals.Killed:Fire(player, killer)
	Net.Broadcast("Downed", player, false)
	Vitals.push(player)

	local rig = Roster.rigOf(player)
	if rig and rig.Humanoid.Parent then
		rig.Humanoid.Health = 0
	end
end

function Vitals.revive(player, medic)
	local state = Vitals.States[player]
	if not state or not state.Downed then
		return false
	end

	state.Downed = false
	state.Health = 35
	state.ReviveProgress = 0

	for _, limb in pairs(state.Limbs) do
		limb.Bleeding = 0
		limb.Health = math.max(limb.Health, limb.Max * 0.4)
		limb.Broken = limb.Health <= 0
	end

	Vitals.Revived:Fire(player, medic)
	Net.Broadcast("Downed", player, false)
	Vitals.push(player)
	syncHumanoid(player, state)
	return true
end

function Vitals.apply(victim, attacker, resolved, context)
	local state = Vitals.stateFor(victim)
	if state.Dead then
		return nil
	end

	local limb = state.Limbs[resolved.Limb]
	local amount = resolved.Amount

	state.LastDamageAt = os.clock()
	state.Armor = math.max(state.Armor - resolved.ArmorLost, 0)

	if limb then
		limb.Health = math.max(limb.Health - amount * 0.85, 0)
		if limb.Health <= 0 and not limb.Broken and resolved.Fracture then
			limb.Broken = true
		end
		if resolved.Bleed then
			limb.Bleeding = math.min(limb.Bleeding + 1, 3)
		end
	end

	if state.Downed then
		state.Health = math.max(state.Health - amount * 1.6, 0)
		if state.Health <= 0 then
			Vitals.kill(victim, state, attacker)
		end
	else
		state.Health = math.max(state.Health - amount, 0)
		if state.Health <= 0 then
			local lethal = resolved.Limb == Enums.Limb.Head or amount >= 65
			if lethal then
				Vitals.kill(victim, state, attacker)
			else
				Vitals.enterDowned(victim, state, attacker)
			end
		end
	end

	syncHumanoid(victim, state)
	Vitals.push(victim)
	flinchEvent:FireClient(victim)

	if resolved.Fracture then
		limbEvent:FireClient(victim, resolved.Limb)
	end

	if attacker and attacker ~= victim then
		Net.To(attacker, "DamageDealt", {
			Amount = amount,
			Limb = resolved.Limb,
			Lethal = state.Dead,
			Downed = state.Downed,
			Position = context and context.Position or nil,
		})
	end

	return state
end

local function tick(dt)
	for player, state in pairs(Vitals.States) do
		if state.Dead then
			continue
		end

		local bleeding = 0
		for _, limb in pairs(state.Limbs) do
			bleeding += limb.Bleeding
		end

		local changed = false

		if bleeding > 0 then
			state.Health = math.max(state.Health - Tuning.Vitals.BleedDamage * bleeding * dt, state.Downed and 0 or 1)
			changed = true
		end

		if state.Downed then
			state.Health = math.max(state.Health - Tuning.Vitals.DownedDecay * dt, 0)
			changed = true
			if state.Health <= 0 then
				Vitals.kill(player, state, nil)
				continue
			end
		elseif bleeding == 0 and os.clock() - state.LastDamageAt > Tuning.Vitals.RegenDelay then
			local ceiling = math.min(state.MaxHealth, Tuning.Vitals.RegenCeiling)
			if state.Health < ceiling then
				state.Health = math.min(state.Health + Tuning.Vitals.RegenRate * dt, ceiling)
				changed = true
			end
		end

		if changed then
			syncHumanoid(player, state)
		end
	end
end

local function pushLoop()
	while true do
		task.wait(0.4)
		for player in pairs(Vitals.States) do
			Vitals.push(player)
		end
	end
end

function Vitals.start()
	Roster.CharacterReady:Connect(function(player)
		Vitals.States[player] = freshState(player)
		Vitals.push(player)
		Net.Broadcast("Downed", player, false)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Vitals.States[player] = nil
	end)

	Net.On("Revive", function(medic, target)
		if typeof(target) ~= "Instance" or not target:IsA("Player") then
			return
		end

		local medicRig = Roster.rigOf(medic)
		local targetRig = Roster.rigOf(target)
		local state = Vitals.States[target]
		if not medicRig or not targetRig or not state or not state.Downed then
			return
		end

		local medicState = Vitals.States[medic]
		if not medicState or medicState.Downed or medicState.Dead then
			return
		end

		if (medicRig.Root.Position - targetRig.Root.Position).Magnitude > 9 then
			return
		end

		state.ReviveProgress += 0.25
		if state.ReviveProgress >= Tuning.Vitals.ReviveDuration then
			Vitals.revive(target, medic)
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Tuning.Vitals.BleedTickRate * 0.25 then
			return
		end
		tick(accumulator)
		accumulator = 0
	end)

	task.spawn(pushLoop)
end

return Vitals
