local Players = game:GetService("Players")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Signal = require(Sable.Lib.Signal)
local Catalog = require(Sable.Data.Weapons)
local Enums = require(Sable.Data.Enums)
local WeaponRig = require(Sable.Shared.WeaponRig)

local Roster = require(script.Parent.Roster)
local Vitals = require(script.Parent.Vitals)

local TEMPLATES = Sable:WaitForChild("Weapons")
local DEFAULT_LOADOUT = { "M4A1", "R870", "Deagle" }

local Loadout = {}
Loadout.States = {}
Loadout.AmmoChanged = Signal.new("AmmoChanged")

local function newMagazine(weapon)
	return {
		Id = weapon.Id,
		Magazine = weapon.Ammo.Magazine,
		Reserve = weapon.Ammo.Reserve,
		Chambered = weapon.Ammo.Chambered,
		Mode = weapon.Fire.DefaultMode,
		Cycled = true,
	}
end

function Loadout.stateFor(player)
	local state = Loadout.States[player]
	if not state then
		state = { Slots = {}, Tools = {}, Active = nil, Reload = nil, LastFire = 0, Shots = 0 }
		Loadout.States[player] = state
	end
	return state
end

function Loadout.slotOf(player, weaponId)
	local state = Loadout.States[player]
	if not state then
		return nil
	end
	for _, slot in pairs(state.Slots) do
		if slot.Id == weaponId then
			return slot
		end
	end
	return nil
end

function Loadout.activeSlot(player)
	local state = Loadout.States[player]
	if not state or not state.Active then
		return nil
	end
	return state.Slots[state.Active]
end

local function syncSlot(player, slot)
	if not slot then
		return
	end
	Net.To(player, "AmmoSync", slot.Id, slot.Magazine, slot.Reserve, slot.Chambered, slot.Mode, slot.Cycled)
	Loadout.AmmoChanged:Fire(player, slot)
end

Loadout.sync = syncSlot

local function clearTools(player, state)
	for _, tool in pairs(state.Tools) do
		if tool.Parent then
			tool:Destroy()
		end
	end
	table.clear(state.Tools)
end

local function grant(player, weaponId, index)
	local weapon = Catalog.get(weaponId)
	local template = TEMPLATES:FindFirstChild(weapon.Model)
	if not template then
		warn("[Loadout] missing model for " .. weaponId)
		return nil
	end

	local tool = template:Clone()
	tool:SetAttribute("WeaponId", weaponId)
	tool:SetAttribute("Slot", index)
	tool.Parent = player.Backpack

	tool.Equipped:Connect(function()
		local state = Loadout.States[player]
		if not state then
			return
		end
		WeaponRig.bind(tool, player.Character)
		state.Active = index
		syncSlot(player, state.Slots[index])
	end)

	tool.Unequipped:Connect(function()
		local state = Loadout.States[player]
		if state and state.Active == index then
			state.Active = nil
			Loadout.abortReload(player)
		end
		WeaponRig.unbind(tool)
	end)

	return tool
end

function Loadout.equipDefault(player)
	local state = Loadout.stateFor(player)
	clearTools(player, state)
	table.clear(state.Slots)
	state.Active = nil
	state.Reload = nil

	for index, weaponId in ipairs(DEFAULT_LOADOUT) do
		local tool = grant(player, weaponId, index)
		if tool then
			state.Tools[index] = tool
			state.Slots[index] = newMagazine(Catalog.get(weaponId))
			syncSlot(player, state.Slots[index])
		end
	end
end

function Loadout.consume(player, weaponId, rounds)
	local slot = Loadout.slotOf(player, weaponId)
	if not slot then
		return false
	end

	if slot.Magazine < rounds then
		return false
	end

	slot.Magazine -= rounds
	local weapon = Catalog.get(weaponId)
	if weapon.Fire.RequiresCycle then
		slot.Cycled = false
	end
	syncSlot(player, slot)
	return true
end

function Loadout.markCycled(player, weaponId)
	local slot = Loadout.slotOf(player, weaponId)
	if slot then
		slot.Cycled = true
		syncSlot(player, slot)
	end
end

function Loadout.abortReload(player)
	local state = Loadout.States[player]
	if state and state.Reload then
		state.Reload.Cancelled = true
		state.Reload = nil
	end
end

local function commitMagazineReload(player, slot, weapon)
	local wanted = weapon.Ammo.Magazine - slot.Magazine
	local moved = math.min(wanted, slot.Reserve)
	slot.Magazine += moved
	slot.Reserve -= moved
	slot.Cycled = true
	syncSlot(player, slot)
end

local function runMagazineReload(player, state, slot, weapon)
	local wasEmpty = slot.Magazine <= 0
	local duration = wasEmpty and weapon.Reload.EmptyDuration or weapon.Reload.Duration
	local session = { Kind = "Magazine", Cancelled = false, WeaponId = slot.Id }
	state.Reload = session

	Net.To(player, "ReloadStage", "Begin", slot.Id, duration, wasEmpty)

	task.delay(duration, function()
		if session.Cancelled or state.Reload ~= session then
			return
		end
		state.Reload = nil
		commitMagazineReload(player, slot, weapon)
		Net.To(player, "ReloadStage", "Finish", slot.Id)
	end)
end

local function runShellReload(player, state, slot, weapon)
	local config = weapon.Reload
	local session = { Kind = "Shell", Cancelled = false, WeaponId = slot.Id, Fed = 0 }
	state.Reload = session

	Net.To(player, "ReloadStage", "Begin", slot.Id, config.StartDuration, slot.Magazine <= 0)

	task.spawn(function()
		task.wait(config.StartDuration)

		while not session.Cancelled and state.Reload == session do
			if slot.Magazine >= weapon.Ammo.Magazine or slot.Reserve <= 0 then
				break
			end

			task.wait(config.StepDuration)
			if session.Cancelled or state.Reload ~= session then
				return
			end

			local moved = math.min(config.ShellsPerStep, slot.Reserve, weapon.Ammo.Magazine - slot.Magazine)
			if moved <= 0 then
				break
			end

			slot.Magazine += moved
			slot.Reserve -= moved
			session.Fed += moved
			syncSlot(player, slot)
			Net.To(player, "ReloadStage", "Shell", slot.Id, session.Fed)
		end

		if session.Cancelled or state.Reload ~= session then
			return
		end

		task.wait(config.EndDuration)
		if state.Reload == session then
			state.Reload = nil
			slot.Cycled = true
			syncSlot(player, slot)
			Net.To(player, "ReloadStage", "Finish", slot.Id)
		end
	end)
end

function Loadout.requestReload(player)
	local state = Loadout.States[player]
	if not state or state.Reload then
		return
	end

	local slot = Loadout.activeSlot(player)
	if not slot then
		return
	end

	local vitals = Vitals.States[player]
	if vitals and (vitals.Downed or vitals.Dead) then
		return
	end

	local weapon = Catalog.get(slot.Id)
	if slot.Reserve <= 0 or slot.Magazine >= weapon.Ammo.Magazine then
		return
	end

	if weapon.Reload.Kind == "Shell" then
		runShellReload(player, state, slot, weapon)
	else
		runMagazineReload(player, state, slot, weapon)
	end
end

function Loadout.switchFiremode(player)
	local slot = Loadout.activeSlot(player)
	if not slot then
		return
	end

	local weapon = Catalog.get(slot.Id)
	local modes = weapon.Fire.Modes
	if #modes <= 1 then
		return
	end

	local index = table.find(modes, slot.Mode) or 1
	slot.Mode = modes[index % #modes + 1]
	syncSlot(player, slot)
	Net.BroadcastExcept(player, "WeaponAction", player, "Firemode", slot.Id)
end

function Loadout.start()
	Roster.CharacterReady:Connect(function(player)
		task.wait(0.2)
		Loadout.equipDefault(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Loadout.States[player] = nil
	end)

	Net.On("RequestReload", function(player)
		Loadout.requestReload(player)
	end)

	Net.On("SwitchFiremode", function(player)
		Loadout.switchFiremode(player)
	end)

	Net.On("WeaponAction", function(player, action, payload)
		if action == "CancelReload" then
			Loadout.abortReload(player)
		elseif action == "Cycled" then
			local slot = Loadout.activeSlot(player)
			if slot and slot.Id == payload then
				Loadout.markCycled(player, payload)
				Net.BroadcastExcept(player, "WeaponAction", player, "Cycle", payload)
			end
		elseif action == "Inspect" then
			Net.BroadcastExcept(player, "WeaponAction", player, "Inspect", payload)
		end
	end)

	Net.Handle("FetchLoadout", function(player)
		local state = Loadout.States[player]
		if not state then
			return nil
		end

		local payload = {}
		for index, slot in pairs(state.Slots) do
			payload[index] = {
				Id = slot.Id,
				Magazine = slot.Magazine,
				Reserve = slot.Reserve,
				Mode = slot.Mode,
				Cycled = slot.Cycled,
			}
		end
		return payload
	end)
end

return Loadout
