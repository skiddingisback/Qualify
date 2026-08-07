local Rig = require(script.Parent.Rig)

local ROOT_JOINTS = { "Tool6D_Torso", "Mag6D_Torso" }
local ARM_JOINTS = { "Right Shoulder", "Left Shoulder" }
local FALLBACK_UP = Vector3.new(0, 0, -1)

local WeaponRig = {}
WeaponRig.__index = WeaponRig

function WeaponRig.bind(tool, character)
	local rig = Rig.wrap(character)
	local torso = rig and rig.Torso
	if not torso then
		return false
	end

	local bound = 0
	for _, name in ipairs(ROOT_JOINTS) do
		local joint = tool:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") and joint.Part1 then
			joint.Part0 = torso
			joint.Enabled = true
			bound += 1
		end
	end
	return bound > 0
end

function WeaponRig.unbind(tool)
	for _, name in ipairs(ROOT_JOINTS) do
		local joint = tool:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			joint.Part0 = nil
		end
	end
end

local function orthogonalize(vector, axis)
	local projected = vector - axis * vector:Dot(axis)
	if projected.Magnitude < 1e-4 then
		return FALLBACK_UP
	end
	return projected.Unit
end

function WeaponRig.new(tool)
	local handle = tool:FindFirstChild("WeaponHandle")
	if not handle then
		return nil
	end

	local self = setmetatable({
		Tool = tool,
		Handle = handle,
		Muzzle = handle:FindFirstChild("Muzzle"),
		FirePos = handle:FindFirstChild("FirePos"),
		EndPos = handle:FindFirstChild("EndPos"),
		ShellOut = handle:FindFirstChild("ShellOutPos"),
		ReloadNode = handle:FindFirstChild("ReloadA"),
		TriggerNode = handle:FindFirstChild("TriggerA"),
		Joints = {},
	}, WeaponRig)

	for _, name in ipairs(ROOT_JOINTS) do
		local joint = tool:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			local entry = { Joint = joint, C0 = joint.C0, C1 = joint.C1 }
			table.insert(self.Joints, entry)
			if name == "Tool6D_Torso" then
				self.Primary = entry
			end
		end
	end

	self:_buildSightFrame()
	return self
end

function WeaponRig:LinkArms(character)
	local torso = character and (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"))
	if not torso then
		return 0
	end

	local linked = 0
	for _, name in ipairs(ARM_JOINTS) do
		local joint = torso:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			table.insert(self.Joints, { Joint = joint, C0 = joint.C0, C1 = joint.C1 })
			linked += 1
		end
	end
	return linked
end

function WeaponRig:_buildSightFrame()
	local fire = self.FirePos
	local tail = self.EndPos
	local sight = self.Handle:FindFirstChild("ADS_FirePos") or fire

	if not fire or not tail or not sight then
		self.SightFrame = CFrame.identity
		self.PivotFrame = CFrame.identity
		self.BoreAxis = Vector3.new(0, -1, 0)
		return
	end

	local forward = (fire.Position - tail.Position)
	if forward.Magnitude < 1e-4 then
		forward = Vector3.new(0, -1, 0)
	end
	forward = forward.Unit

	local up = orthogonalize(sight.Position - fire.Position, forward)

	self.BoreAxis = forward
	self.SightFrame = CFrame.lookAt(sight.Position, sight.Position + forward, up)
	self.BoreFrame = CFrame.lookAt(fire.Position, fire.Position + forward, up)
	self.PivotFrame = self.SightFrame.Rotation
end

function WeaponRig:IsBound()
	local primary = self.Primary
	return primary ~= nil and primary.Joint.Part0 ~= nil and primary.Joint.Parent ~= nil
end

function WeaponRig:JointBase(entry)
	local joint = entry.Joint
	local part0 = joint.Part0
	if not part0 or not joint.Part1 then
		return nil
	end

	return part0.CFrame * joint.C0 * joint.Transform * entry.C1:Inverse()
end

function WeaponRig:BaseCFrame()
	local primary = self.Primary
	if not primary then
		return self.Handle.CFrame
	end

	return self:JointBase(primary) or self.Handle.CFrame
end

function WeaponRig:LocalFrame(offset)
	local pivot = self.PivotFrame
	return pivot * offset * pivot:Inverse()
end

function WeaponRig:Apply(delta)
	local primary = self.Primary
	if not primary then
		return
	end

	primary.Joint.C1 = delta:Inverse() * primary.C1

	local anchor = self:JointBase(primary)
	if anchor then
		local anchorInverse = anchor:Inverse()
		for _, entry in ipairs(self.Joints) do
			if entry ~= primary then
				local base = self:JointBase(entry)
				if base then
					local relative = anchorInverse * base
					local conjugated = relative:Inverse() * delta * relative
					entry.Joint.C1 = conjugated:Inverse() * entry.C1
				end
			end
		end
	end

	self.LastDelta = delta
end

function WeaponRig:Restore()
	for _, entry in ipairs(self.Joints) do
		entry.Joint.C1 = entry.C1
	end
	self.LastDelta = CFrame.identity
end

function WeaponRig:SolveSight(targetFrame, baseFrame)
	baseFrame = baseFrame or self:BaseCFrame()
	local desired = targetFrame * self.SightFrame:Inverse()
	return baseFrame:Inverse() * desired
end

function WeaponRig:MuzzleFrame()
	local muzzle = self.Muzzle
	if muzzle then
		return muzzle.WorldCFrame
	end
	return self.Handle.CFrame
end

function WeaponRig:BoreDirection()
	local fire, tail = self.FirePos, self.EndPos
	if fire and tail then
		local delta = fire.WorldPosition - tail.WorldPosition
		if delta.Magnitude > 1e-4 then
			return delta.Unit
		end
	end
	return self.Handle.CFrame.UpVector * -1
end

function WeaponRig:MuzzlePosition()
	local muzzle = self.Muzzle
	if muzzle then
		return muzzle.WorldPosition
	end
	return self.Handle.Position
end

function WeaponRig:Destroy()
	self:Restore()
	table.clear(self.Joints)
	self.Primary = nil
end

return WeaponRig
