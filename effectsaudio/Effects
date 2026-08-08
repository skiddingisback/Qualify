local TweenService = game:GetService("TweenService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Pool = require(Sable.Lib.Pool)
local Enums = require(Sable.Data.Enums)
local Materials = require(Sable.Data.Materials)
local SoundKit = require(Sable.Shared.SoundKit)

local Effects = {}

local container = nil
local tracerPool = nil
local holePool = nil
local burstPool = nil
local shellPool = nil

local function buildContainer()
	local folder = workspace:FindFirstChild("SableEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SableEffects"
		folder.Parent = workspace
	end
	return folder
end

local function buildTracerTemplate()
	local part = Instance.new("Part")
	part.Name = "Tracer"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(1, 0.05, 0.05)
	part.Color = Color3.fromRGB(255, 226, 150)
	part.Transparency = 0.35
	return part
end

local function buildHoleTemplate()
	local part = Instance.new("Part")
	part.Name = "Hole"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(16, 14, 12)
	part.Size = Vector3.new(0.22, 0.03, 0.22)
	part.Transparency = 0.05
	return part
end

local function buildBurstTemplate()
	local part = Instance.new("Part")
	part.Name = "Burst"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.1

	local attachment = Instance.new("Attachment")
	attachment.Name = "Node"
	attachment.Parent = part

	local debris = Instance.new("ParticleEmitter")
	debris.Name = "Debris"
	debris.Enabled = false
	debris.Rate = 0
	debris.Speed = NumberRange.new(9, 22)
	debris.Lifetime = NumberRange.new(0.25, 0.6)
	debris.SpreadAngle = Vector2.new(38, 38)
	debris.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	debris.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	debris.Acceleration = Vector3.new(0, -48, 0)
	debris.Parent = attachment

	local dust = debris:Clone()
	dust.Name = "Dust"
	dust.Speed = NumberRange.new(1, 4)
	dust.Lifetime = NumberRange.new(0.4, 1.1)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1.1),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = attachment

	local sparks = debris:Clone()
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 214, 128))
	sparks.LightEmission = 1
	sparks.Speed = NumberRange.new(14, 34)
	sparks.Lifetime = NumberRange.new(0.12, 0.34)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.09),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = attachment

	return part
end

local function buildShellTemplate()
	local part = Instance.new("Part")
	part.Name = "Shell"
	part.Anchored = false
	part.CanCollide = true
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Metal
	part.Color = Color3.fromRGB(196, 158, 74)
	part.Size = Vector3.new(0.08, 0.08, 0.22)
	part.Shape = Enum.PartType.Cylinder
	return part
end

function Effects.prepareTool(tool)
	local handle = tool:FindFirstChild("WeaponHandle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if not muzzle then
		return
	end

	for _, child in ipairs(muzzle:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child.Enabled = false
		end
	end
end

function Effects.muzzle(weaponRig, weapon)
	local muzzle = weaponRig.Muzzle
	if not muzzle then
		return
	end

	for _, child in ipairs(muzzle:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			local count = 2
			if child.Rate > 0 then
				count = math.clamp(math.floor(child.Rate * 0.06), 1, 9)
			end
			child:Emit(count)
		end
	end

	local light = muzzle:FindFirstChild("SableFlash")
	if not light then
		light = Instance.new("PointLight")
		light.Name = "SableFlash"
		light.Color = Color3.fromRGB(255, 216, 150)
		light.Shadows = false
		light.Parent = muzzle
	end

	light.Range = weapon.Fx.LightRange
	light.Brightness = weapon.Fx.LightBrightness
	light.Enabled = true

	task.delay(weapon.Fx.FlashDuration, function()
		if light and light.Parent then
			light.Enabled = false
		end
	end)

	SoundKit.pick(muzzle, "FireSound", 3, { Jitter = 0.04 })
end

function Effects.tracer(from, to, weapon)
	if math.random() > weapon.Fx.TracerChance then
		return
	end

	local delta = to - from
	local length = delta.Magnitude
	if length < 3 then
		return
	end

	local part = tracerPool:Acquire()
	part.Size = Vector3.new(length, weapon.Fx.TracerWidth, weapon.Fx.TracerWidth)
	part.Color = weapon.Fx.TracerColor
	part.Transparency = 0.28
	part.CFrame = CFrame.lookAt(from + delta * 0.5, to) * CFrame.Angles(0, math.rad(90), 0)

	local tween = TweenService:Create(part, TweenInfo.new(weapon.Fx.TracerLife, Enum.EasingStyle.Linear), { Transparency = 1 })
	tween:Play()
	tracerPool:ReleaseAfter(part, weapon.Fx.TracerLife + 0.05)
end

function Effects.impact(impact, weapon)
	local profile = impact.Profile or Materials.Default
	local normal = impact.Normal
	local position = impact.Position

	local burst = burstPool:Acquire()
	burst.CFrame = CFrame.lookAt(position, position + normal)

	local node = burst:FindFirstChild("Node")
	if node then
		local debris = node:FindFirstChild("Debris")
		local dust = node:FindFirstChild("Dust")
		local sparks = node:FindFirstChild("Sparks")

		if debris then
			debris.Color = ColorSequence.new(profile.Dust)
			debris:Emit(math.floor(6 * impact.Energy) + 2)
		end
		if dust then
			dust.Color = ColorSequence.new(profile.Dust)
			dust:Emit(math.floor(4 * impact.Energy) + 1)
		end
		if sparks and profile.Sparks then
			sparks:Emit(math.floor(8 * impact.Energy) + 3)
		end
	end
	burstPool:ReleaseAfter(burst, 1.4)

	if profile.Decal and not impact.Character then
		local hole = holePool:Acquire()
		hole.CFrame = CFrame.lookAt(position + normal * 0.02, position + normal * 2) * CFrame.Angles(math.rad(90), 0, 0)
		hole.Transparency = 0.05
		hole.Size = Vector3.new(0.18 + math.random() * 0.1, 0.02, 0.18 + math.random() * 0.1)
		TweenService:Create(hole, TweenInfo.new(14, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		holePool:ReleaseAfter(hole, 15)
	end

	SoundKit.spatial(profile.Impact, position, {
		Volume = impact.Character and 0.85 or 0.55,
		Pitch = impact.Character and 1 or 1.05,
		MaxDistance = 120,
		Jitter = 0.1,
	})
end

function Effects.ejectShell(weaponRig, weapon)
	local config = weapon.Shell
	if not config.Enabled then
		return
	end

	local node = weaponRig.ShellOut
	if not node then
		return
	end

	local function spawn()
		if not node.Parent then
			return
		end

		local shell = shellPool:Acquire()
		shell.Size = config.Size
		shell.Color = config.Color
		shell.Material = config.Material
		shell.CFrame = node.WorldCFrame * CFrame.Angles(0, 0, math.rad(90))
		shell.AssemblyLinearVelocity = node.WorldCFrame.RightVector * config.Force
			+ Vector3.new(0, config.Force * 0.35, 0)
			+ Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2
		shell.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * config.Spin,
			(math.random() - 0.5) * config.Spin,
			(math.random() - 0.5) * config.Spin
		)

		pcall(function()
			shell.CollisionGroup = Enums.CollisionGroup.Debris
		end)

		shellPool:ReleaseAfter(shell, config.Life)
	end

	if config.Delay > 0 then
		task.delay(config.Delay, spawn)
	else
		spawn()
	end
end

function Effects.renderShot(weaponRig, weapon, trace)
	Effects.muzzle(weaponRig, weapon)

	for _, segment in ipairs(trace.Segments) do
		Effects.tracer(segment.From, segment.To, weapon)
	end

	for _, impact in ipairs(trace.Impacts) do
		Effects.impact(impact, weapon)
	end
end

function Effects.start()
	container = buildContainer()
	tracerPool = Pool.new(buildTracerTemplate(), 26, container)
	holePool = Pool.new(buildHoleTemplate(), 48, container)
	burstPool = Pool.new(buildBurstTemplate(), 18, container)
	shellPool = Pool.new(buildShellTemplate(), 22, container)
end

return Effects
