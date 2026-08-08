local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Signal = require(Sable.Lib.Signal)
local Trove = require(Sable.Lib.Trove)
local Tuning = require(Sable.Data.Tuning)
local Enums = require(Sable.Data.Enums)
local Rig = require(Sable.Shared.Rig)

local Roster = {}
Roster.Entries = {}
Roster.CharacterReady = Signal.new("CharacterReady")
Roster.CharacterGone = Signal.new("CharacterGone")

local SNAPSHOT_INTERVAL = 1 / Tuning.Combat.HistoryRate
local WINDOW = Tuning.Combat.LagCompensationWindow

local function registerCollisionGroups()
	for _, name in pairs(Enums.CollisionGroup) do
		pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, name)
	end
	pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, Enums.CollisionGroup.Character, Enums.CollisionGroup.Character, false)
	pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, Enums.CollisionGroup.Weapon, Enums.CollisionGroup.Character, false)
	pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, Enums.CollisionGroup.Debris, Enums.CollisionGroup.Character, false)
	pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, Enums.CollisionGroup.Debris, Enums.CollisionGroup.Debris, false)
end

function Roster.get(player)
	return Roster.Entries[player]
end

function Roster.rigOf(player)
	local entry = Roster.Entries[player]
	return entry and entry.Rig or nil
end

function Roster.each(callback)
	for player, entry in pairs(Roster.Entries) do
		callback(player, entry)
	end
end

local function trackedParts(character)
	local parts = {}
	for _, descendant in ipairs(character:GetChildren()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function snapshot(entry)
	local frame = { Stamp = os.clock(), Positions = {} }
	for _, part in ipairs(entry.Tracked) do
		if part.Parent then
			frame.Positions[part] = part.Position
		end
	end

	table.insert(entry.History, frame)
	while #entry.History > 2 and frame.Stamp - entry.History[1].Stamp > WINDOW do
		table.remove(entry.History, 1)
	end
end

function Roster.rewind(player, latency)
	local entry = Roster.Entries[player]
	if not entry or #entry.History == 0 then
		return nil
	end

	local target = os.clock() - math.clamp(latency or 0, 0, WINDOW)
	local history = entry.History

	for index = #history, 1, -1 do
		if history[index].Stamp <= target then
			return history[index], history[math.min(index + 1, #history)]
		end
	end
	return history[1], history[math.min(2, #history)]
end

function Roster.rewoundPosition(player, part, latency)
	local older, newer = Roster.rewind(player, latency)
	if not older then
		return part.Position
	end

	local a = older.Positions[part]
	if not a then
		return part.Position
	end

	local b = newer and newer.Positions[part]
	if not b or newer == older then
		return a
	end

	local span = newer.Stamp - older.Stamp
	if span <= 0 then
		return a
	end

	local target = os.clock() - math.clamp(latency or 0, 0, WINDOW)
	local alpha = math.clamp((target - older.Stamp) / span, 0, 1)
	return a:Lerp(b, alpha)
end

local function bindCharacter(player, character)
	local entry = Roster.Entries[player]
	if not entry then
		return
	end

	entry.Trove:Clean()

	local rig = Rig.await(character, 10)
	if not rig then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			pcall(function()
				descendant.CollisionGroup = Enums.CollisionGroup.Character
			end)
		end
	end

	rig.Humanoid.BreakJointsOnDeath = false
	rig.Humanoid.MaxHealth = Tuning.Vitals.MaxHealth
	rig.Humanoid.Health = Tuning.Vitals.MaxHealth
	rig.Humanoid.WalkSpeed = Tuning.Speed.StandWalk
	rig.Humanoid.JumpPower = Tuning.Jump.Power
	rig.Humanoid.UseJumpPower = true

	entry.Character = character
	entry.Rig = rig
	entry.Tracked = trackedParts(character)
	entry.History = {}
	entry.SpawnedAt = os.clock()

	entry.Trove:Connect(character.DescendantAdded, function(descendant)
		if descendant:IsA("BasePart") and descendant.Parent == character then
			table.insert(entry.Tracked, descendant)
			pcall(function()
				descendant.CollisionGroup = Enums.CollisionGroup.Character
			end)
		end
	end)

	entry.Trove:Connect(rig.Humanoid.Died, function()
		Roster.CharacterGone:Fire(player, entry)
	end)

	Roster.CharacterReady:Fire(player, entry)
end

local function addPlayer(player)
	local entry = {
		Player = player,
		Trove = Trove.new(),
		History = {},
		Tracked = {},
		Latency = 0.06,
		State = {},
	}
	Roster.Entries[player] = entry

	player.CharacterAdded:Connect(function(character)
		task.defer(bindCharacter, player, character)
	end)

	if player.Character then
		task.defer(bindCharacter, player, player.Character)
	end
end

local function removePlayer(player)
	local entry = Roster.Entries[player]
	if entry then
		entry.Trove:Clean()
		Roster.Entries[player] = nil
	end
end

function Roster.reportLatency(player, latency)
	local entry = Roster.Entries[player]
	if entry then
		entry.Latency = math.clamp(latency, 0, WINDOW)
	end
end

function Roster.start()
	registerCollisionGroups()

	for _, player in ipairs(Players:GetPlayers()) do
		addPlayer(player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < SNAPSHOT_INTERVAL then
			return
		end
		accumulator = 0

		for _, entry in pairs(Roster.Entries) do
			if entry.Character and entry.Character.Parent then
				snapshot(entry)
			end
		end
	end)
end

return Roster
