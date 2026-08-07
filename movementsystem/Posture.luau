local SHOULDER_PIVOT = Vector3.new(0, 0.5, 0)
local WAIST_PIVOT = Vector3.new(0, -1, 0)
local TORSO_JOINTS = { "Neck", "Right Shoulder", "Left Shoulder" }
local LEG_JOINTS = { "Right Hip", "Left Hip" }
local TOOL_JOINTS = { "Tool6D_Torso", "Mag6D_Torso" }

local Posture = {}
Posture.__index = Posture

function Posture.new(rig, options)
	options = options or {}

	local self = setmetatable({
		Rig = rig,
		BodyScale = options.BodyScale or 0.9,
		HeadScale = options.HeadScale or 0.3,
		Limit = options.Limit or math.rad(72),
		RollLimit = options.RollLimit or math.rad(30),
		Pitch = 0,
		Roll = 0,
		Joints = {},
		Legs = {},
		ToolJoints = {},
		Tool = nil,
	}, Posture)

	local torso = rig.Torso
	if not torso then
		return self
	end

	for _, name in ipairs(TORSO_JOINTS) do
		local joint = torso:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			self.Joints[name] = { Joint = joint, C0 = joint.C0 }
		end
	end

	for _, name in ipairs(LEG_JOINTS) do
		local joint = torso:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			table.insert(self.Legs, { Joint = joint, C0 = joint.C0 })
		end
	end

	local waist = rig.Root:FindFirstChild("RootJoint")
	if waist and waist:IsA("Motor6D") then
		self.Waist = { Joint = waist, C0 = waist.C0 }
	end

	return self
end

function Posture:Track(tool)
	if self.Tool == tool then
		return
	end

	self:ReleaseTool()
	self.Tool = tool

	if not tool then
		return
	end

	for _, name in ipairs(TOOL_JOINTS) do
		local joint = tool:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			table.insert(self.ToolJoints, { Joint = joint, C0 = joint.C0 })
		end
	end
end

function Posture:ReleaseTool()
	for _, entry in ipairs(self.ToolJoints) do
		if entry.Joint.Parent then
			entry.Joint.C0 = entry.C0
		end
	end
	table.clear(self.ToolJoints)
	self.Tool = nil
end

function Posture:Bend(pitch)
	return CFrame.new(SHOULDER_PIVOT) * CFrame.Angles(pitch, 0, 0) * CFrame.new(-SHOULDER_PIVOT)
end

function Posture:Sway(roll)
	return CFrame.new(WAIST_PIVOT) * CFrame.Angles(0, 0, roll) * CFrame.new(-WAIST_PIVOT)
end

function Posture:Apply(pitch, roll)
	self.Pitch = math.clamp(pitch, -self.Limit, self.Limit)
	self.Roll = math.clamp(roll or 0, -self.RollLimit, self.RollLimit)

	if self.Waist and self.Waist.Joint.Parent then
		self.Waist.Joint.C0 = self:Sway(self.Roll) * self.Waist.C0
	end

	local counter = self:Sway(-self.Roll)
	for _, entry in ipairs(self.Legs) do
		if entry.Joint.Parent then
			entry.Joint.C0 = counter * entry.C0
		end
	end

	local body = self:Bend(self.Pitch * self.BodyScale)

	for name, entry in pairs(self.Joints) do
		if entry.Joint.Parent then
			if name == "Neck" then
				local extra = self.Rig.IsR15
					and CFrame.Angles(self.Pitch * self.HeadScale, 0, 0)
					or CFrame.Angles(0, 0, self.Pitch * self.HeadScale)
				entry.Joint.C0 = body * entry.C0 * extra
			else
				entry.Joint.C0 = body * entry.C0
			end
		end
	end

	for _, entry in ipairs(self.ToolJoints) do
		if entry.Joint.Parent then
			entry.Joint.C0 = body * entry.C0
		end
	end
end

function Posture:Relax()
	for _, entry in pairs(self.Joints) do
		if entry.Joint.Parent then
			entry.Joint.C0 = entry.C0
		end
	end
	for _, group in ipairs({ self.Legs, self.ToolJoints }) do
		for _, entry in ipairs(group) do
			if entry.Joint.Parent then
				entry.Joint.C0 = entry.C0
			end
		end
	end
	if self.Waist and self.Waist.Joint.Parent then
		self.Waist.Joint.C0 = self.Waist.C0
	end
	self.Pitch = 0
	self.Roll = 0
end

function Posture:Destroy()
	self:Relax()
	table.clear(self.Joints)
	table.clear(self.Legs)
	table.clear(self.ToolJoints)
	self.Waist = nil
	self.Tool = nil
end

return Posture
