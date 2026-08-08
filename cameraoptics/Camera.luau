local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Spring = require(Sable.Lib.Spring)
local Util = require(Sable.Lib.Util)
local Enums = require(Sable.Data.Enums)
local Tuning = require(Sable.Data.Tuning)
local SoundKit = require(Sable.Shared.SoundKit)

local Context = require(script.Parent.Context)
local Input = require(script.Parent.Input)
local Locomotion = require(script.Parent.Locomotion)

local Camera = {}

Camera.Yaw = 0
Camera.Pitch = 0
Camera.TargetYaw = 0
Camera.TargetPitch = 0
Camera.FovTarget = Tuning.Camera.BaseFov
Camera.Fov = Tuning.Camera.BaseFov
Camera.SensitivityScale = 1
Camera.Frame = CFrame.identity
Camera.RawDelta = Vector2.zero
Camera.MouseLocked = true
Camera.StrafeRoll = 0
Camera.LeanValue = 0
Camera.ThirdPerson = false
Camera.MenuOpen = false
Camera.ShoulderLock = false
Camera.EyeOffset = Tuning.Camera.HeadOffset

local sway = Spring.new(Vector2.zero, Tuning.Camera.SwayStiffness, Tuning.Camera.SwayDamping)
local bob = Spring.new(Vector3.zero, Tuning.Camera.BobStiffness, Tuning.Camera.BobDamping)
local lean = Spring.new(0, Tuning.Lean.Stiffness, Tuning.Lean.Damping)
local shake = Spring.new(Vector3.zero, 210, 16)
local breathe = Spring.new(Vector2.zero, 8, 4)

local punch = Spring.new(Vector3.zero, Tuning.Camera.PunchStiffness, Tuning.Camera.PunchDamping)
local fovPunch = Spring.new(0, 190, 18)

local bobPhase = 0
local bobRate = 0
local landPunch = 0
local viewBlend = 0
local bodyShown = false
local orbitSmoothed = nil
local facing = nil
local tremorTarget = 0
local tremorLevel = 0
local tremorClock = 0
local tremorSeed = math.random() * 512

local VIEWED_LIMBS = {
	["Right Arm"] = true,
	["Left Arm"] = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
}

local function heldByViewer(instance)
	return instance:FindFirstAncestorWhichIsA("Tool") ~= nil
end

local function shouldRender(part)
	if not part or not part:IsA("BasePart") then
		return false
	end
	return VIEWED_LIMBS[part.Name] == true or heldByViewer(part)
end

local function conceal(instance)
	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = shouldRender(instance) and 0 or 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.LocalTransparencyModifier = shouldRender(instance.Parent) and 0 or 1
	elseif instance:IsA("Accessory") then
		for _, child in ipairs(instance:GetDescendants()) do
			conceal(child)
		end
	end
end

function Camera.applyFirstPerson(rig)
	if not rig or not rig.Character.Parent then
		return
	end

	bodyShown = false
	for _, descendant in ipairs(rig.Character:GetDescendants()) do
		conceal(descendant)
	end
end

function Camera.showBody(rig)
	if not rig or not rig.Character.Parent then
		return
	end

	bodyShown = true
	for _, descendant in ipairs(rig.Character:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.LocalTransparencyModifier = 0
		end
	end
end

local function buildFacing(rig)
	local root = rig.Root

	local attachment = root:FindFirstChild("SableFacing")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "SableFacing"
		attachment.Parent = root
	end

	local align = root:FindFirstChild("SableAlign")
	if not align then
		align = Instance.new("AlignOrientation")
		align.Name = "SableAlign"
		align.Parent = root
	end

	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.ReactionTorqueEnabled = false
	align.Enabled = false
	return align
end

local function orbitFrame(anchor, rig)
	local shoulder = Tuning.Camera.ThirdPersonShoulder
	local pivot = anchor * CFrame.new(shoulder.X, shoulder.Y, 0)
	local distance = Tuning.Camera.ThirdPersonDistance

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig.Character, workspace:FindFirstChild("SableEffects") }
	params.IgnoreWater = true

	local result = workspace:Raycast(pivot.Position, pivot.LookVector * -distance, params)
	if result then
		distance = math.max((result.Position - pivot.Position).Magnitude - Tuning.Camera.ThirdPersonPadding, 0.8)
	end

	return pivot * CFrame.new(0, 0, distance)
end

local function wobbleFrame()
	local clock = os.clock() * Tuning.Camera.ThirdPersonWobbleFrequency
	local amplitude = Tuning.Camera.ThirdPersonWobble
	return CFrame.Angles(
		math.noise(clock, 13.7) * amplitude,
		math.noise(clock * 0.79, 41.2) * amplitude,
		math.noise(clock * 0.58, 77.9) * amplitude * 1.4
	)
end

local function currentBobProfile()
	if Context.Stance == Enums.Stance.Prone then
		return Tuning.Bob.Prone
	elseif Context.Stance == Enums.Stance.Crouch then
		return Tuning.Bob.Crouch
	elseif Context.Sprinting then
		return Tuning.Bob.Sprint
	end
	return Tuning.Bob.Walk
end

function Camera.setMouseLocked(locked)
	if Camera.MouseLocked == locked and UserInputService.MouseIconEnabled == not locked then
		return
	end
	Camera.MouseLocked = locked
	UserInputService.MouseBehavior = locked and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not locked
end



function Camera.shakeImpulse(magnitude)
	shake:Impulse(Vector3.new(
		(math.random() * 2 - 1) * magnitude,
		(math.random() * 2 - 1) * magnitude,
		(math.random() * 2 - 1) * magnitude * 0.5
	))
end

function Camera.viewPunch(pitchDegrees, yawDegrees, rollDegrees)
	local omega = math.sqrt(Tuning.Camera.PunchStiffness)
	local impulse = Vector3.new(
		math.rad(pitchDegrees),
		math.rad(yawDegrees),
		math.rad(rollDegrees)
	) * omega

	punch:Impulse(impulse)

	local share = Tuning.Camera.PunchCounterShare
	task.delay(Tuning.Camera.PunchCounterDelay, function()
		punch:Impulse(Vector3.new(-impulse.X * share, -impulse.Y * share, 0))
	end)
end

function Camera.fovPunch(amount)
	fovPunch:Impulse(amount)
end

function Camera.addTremor(amount)
	tremorTarget = math.min(tremorTarget + amount, Tuning.Camera.TremorMax)
end

local function sampleTremor(dt)
	tremorClock += dt
	tremorTarget = math.max(tremorTarget - Tuning.Camera.TremorDecay * dt, 0)
	tremorLevel = Util.damp(tremorLevel, tremorTarget, Tuning.Camera.TremorRamp, dt)

	if tremorLevel < 1e-5 then
		return Vector3.zero
	end

	local frequency = Tuning.Camera.TremorFrequency
	local time = tremorClock * frequency

	return Vector3.new(
		math.noise(time, tremorSeed) * tremorLevel * 1.6,
		math.noise(time * 0.83, tremorSeed + 37.4) * tremorLevel * 1.1,
		math.noise(time * 0.61, tremorSeed + 91.2) * tremorLevel * 1.2
	)
end

function Camera.setFov(target)
	Camera.FovTarget = target
end

function Camera.lookVector()
	return Camera.Frame.LookVector
end

function Camera.origin()
	return Camera.Frame.Position
end

local function integrateLook(dt)
	local delta = Input.consumeMouseDelta()
	Camera.RawDelta = delta

	if not Context.alive() or Camera.MenuOpen then
		return
	end

	local sensitivity = Tuning.Camera.Sensitivity * Camera.SensitivityScale * 0.01
	if Context.Aiming then
		sensitivity *= Tuning.Camera.AdsSensitivityScale
	end

	Camera.TargetYaw -= delta.X * sensitivity
	Camera.TargetPitch = math.clamp(
		Camera.TargetPitch - delta.Y * sensitivity,
		-Tuning.Camera.PitchLimit,
		Tuning.Camera.PitchLimit
	)

	local follow = 1 - math.exp(-Tuning.Camera.RotationSmoothing * dt)
	Camera.Yaw += (Camera.TargetYaw - Camera.Yaw) * follow
	Camera.Pitch += (Camera.TargetPitch - Camera.Pitch) * follow

	local scale = Tuning.Camera.SwayScale * (Context.Aiming and 0.35 or 1)
	sway:Impulse(Vector2.new(
		math.clamp(-delta.X * scale, -Tuning.Camera.SwayMax, Tuning.Camera.SwayMax),
		math.clamp(-delta.Y * scale, -Tuning.Camera.SwayMax, Tuning.Camera.SwayMax)
	))

	Context.LookYaw = Camera.Yaw
	Context.LookPitch = Camera.Pitch
end

local function leanTarget()
	if not Context.canAct() or Context.Sprinting then
		return 0
	end
	if Context.Stance == Enums.Stance.Prone then
		return 0
	end
	return Input.leanAxis()
end

local function clampLean(rig, amount)
	if amount == 0 then
		return 0
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Context.Character }
	params.IgnoreWater = true

	local origin = rig.Root.Position + Vector3.new(0, 1.2, 0)
	local direction = CFrame.Angles(0, Camera.Yaw, 0).RightVector * (amount * (Tuning.Lean.Offset + Tuning.Lean.ProbePadding))
	local result = workspace:Raycast(origin, direction, params)
	if not result then
		return amount
	end

	local available = (result.Position - origin).Magnitude - 0.35
	local allowed = math.clamp(available / (Tuning.Lean.Offset + Tuning.Lean.ProbePadding), 0, 1)
	return amount * allowed
end

local function updateBob(dt, rig)
	local profile = currentBobProfile()
	local speed = Context.Speed

	if not Locomotion.Grounded or speed < 1.2 then
		bob.Target = Vector3.zero
		bob:Update(dt)
		bobRate = Util.damp(bobRate, 0, Tuning.Camera.BobPhaseSmoothing, dt)
		return bob.Position, 0
	end

	local intensity = math.clamp(speed / Tuning.Speed.StandSprint, 0, 1.25)
	if Context.Aiming then
		intensity *= Tuning.Bob.AdsScale
	end

	bobRate = Util.damp(
		bobRate,
		profile.Frequency * math.clamp(speed / Tuning.Speed.StandWalk, 0.4, 1.8),
		Tuning.Camera.BobPhaseSmoothing, dt
	)
	bobPhase += dt * bobRate

	local amplitude = profile.Amplitude * intensity
	local target = Vector3.new(
		math.cos(bobPhase) * amplitude.X,
		math.abs(math.sin(bobPhase)) * amplitude.Y - amplitude.Y * 0.5,
		math.sin(bobPhase * 0.5) * amplitude.Z
	)

	bob.Target = target
	bob:Update(dt)
	return bob.Position, math.sin(bobPhase) * profile.Roll * intensity
end

local function apply(dt)
	local rig = Context.Rig
	local camera = workspace.CurrentCamera
	if not rig or not rig.Root.Parent or not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	lean.Target = clampLean(rig, leanTarget())
	lean:Update(dt)
	sway:Update(dt)
	shake.Target = Vector3.zero
	shake:Update(dt)
	punch.Target = Vector3.zero
	punch:Update(dt)
	fovPunch.Target = 0
	fovPunch:Update(dt)
	breathe:Update(dt)

	local bobOffset, bobRoll = updateBob(dt, rig)

	local eye = Camera.EyeOffset
	local stanceDrop = Locomotion.stanceOffset()
	local basePosition = rig.Root.Position + Vector3.new(0, eye.Y + 0.9 - stanceDrop, 0)

	if rig.Head then
		local headDelta = rig.Head.Position - (rig.Root.Position + Vector3.new(0, 1.5, 0))
		basePosition += headDelta * Tuning.Camera.HeadFollow
	end

	landPunch = Util.damp(landPunch, 0, 9, dt)

	local leanValue = lean.Position
	Camera.LeanValue = leanValue
	local swayValue = sway.Position
	local shakeValue = shake.Position

	local punchValue = punch.Position
	local tremor = sampleTremor(dt)

	local rotation = CFrame.Angles(0, Camera.Yaw, 0)
		* CFrame.Angles(Camera.Pitch + swayValue.Y + shakeValue.Y * 0.05 + punchValue.X + tremor.X, 0, 0)
		* CFrame.Angles(0, swayValue.X * 0.6 + shakeValue.X * 0.015 + punchValue.Y + tremor.Y, 0)
		* CFrame.Angles(0, 0, punchValue.Z + tremor.Z)

	local leanFrame = CFrame.new(leanValue * Tuning.Lean.Offset, 0, 0)
		* CFrame.Angles(0, 0, -leanValue * Tuning.Lean.Angle + bobRoll + Camera.StrafeRoll)

	local offsetFrame = CFrame.new(
		bobOffset.X + eye.X,
		bobOffset.Y - landPunch,
		bobOffset.Z + eye.Z
	)

	local anchor = CFrame.new(basePosition) * rotation * leanFrame
	local frame = anchor * offsetFrame

	viewBlend = Util.damp(viewBlend, Camera.ThirdPerson and 1 or 0, Tuning.Camera.ViewBlendSmoothing, dt)

	if viewBlend > 0.001 then
		local target = orbitFrame(anchor, rig)
		if orbitSmoothed then
			orbitSmoothed = orbitSmoothed:Lerp(target, 1 - math.exp(-Tuning.Camera.ThirdPersonSmoothing * dt))
		else
			orbitSmoothed = target
		end
		frame = frame:Lerp(orbitSmoothed * wobbleFrame(), viewBlend)
	else
		orbitSmoothed = nil
	end

	if (viewBlend > 0.5) ~= bodyShown then
		if viewBlend > 0.5 then
			Camera.showBody(rig)
		else
			Camera.applyFirstPerson(rig)
		end
	end

	Camera.Frame = frame
	camera.CFrame = frame

	local fovTarget = Util.lerp(Camera.FovTarget, Tuning.Camera.ThirdPersonFov, viewBlend)
	Camera.Fov = Util.damp(Camera.Fov, fovTarget, Tuning.Camera.FovSmoothing, dt)
	camera.FieldOfView = math.clamp(Camera.Fov + fovPunch.Position, 20, 110)

	local locked = not Camera.ThirdPerson or Camera.ShoulderLock
	rig.Humanoid.AutoRotate = not locked

	if facing then
		facing.Enabled = locked
		facing.CFrame = CFrame.Angles(0, Camera.Yaw, 0)
	end
end

local function baselineFov()
	if Context.Aiming then
		return Camera.FovTarget
	end
	if Context.Motion == Enums.Motion.Slide then
		return Tuning.Camera.SlideFov
	end
	if Context.Sprinting and Context.Speed > 6 then
		return Tuning.Camera.SprintFov
	end
	return Tuning.Camera.BaseFov
end

local function onCharacter(rig)
	Camera.Pitch = 0
	Camera.Yaw = math.atan2(-rig.Root.CFrame.LookVector.X, -rig.Root.CFrame.LookVector.Z)
	Camera.TargetYaw = Camera.Yaw
	Camera.TargetPitch = 0
	Context.LookYaw = Camera.Yaw
	landPunch = 0
	bobPhase = 0

	viewBlend = Context.WeaponId == nil and 1 or 0
	bodyShown = false
	orbitSmoothed = nil
	facing = buildFacing(rig)
	SoundKit.setListenerFilter({ rig.Character, workspace:FindFirstChild("SableEffects") })

	sway:Reset(Vector2.zero)
	bob:Reset(Vector3.zero)
	shake:Reset(Vector3.zero)
	punch:Reset(Vector3.zero)
	fovPunch:Reset(0)
	lean:Reset(0)
	tremorTarget = 0
	tremorLevel = 0

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = rig.Humanoid

	task.defer(Camera.applyFirstPerson, rig)

	rig.Character.DescendantAdded:Connect(function(descendant)
		task.defer(conceal, descendant)
	end)
end

function Camera.start()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	Context.CharacterReady:Connect(onCharacter)

	Input.Pressed:Connect(function(action)
		if action == "ShoulderLock" then
			Camera.ShoulderLock = not Camera.ShoulderLock
		end
	end)

	Context.Landed:Connect(function(speed)
		landPunch = math.clamp(speed / 120, 0, 0.55)
		Camera.shakeImpulse(math.clamp(speed / 90, 0, 1.2))
	end)

	Context.Footstep:Connect(function(phase)
		if Context.Aiming then
			return
		end
		bob:Impulse(Vector3.new(0, -0.012 * (phase == 1 and 1 or 0.8), 0))
	end)

	RunService:BindToRenderStep("SableLook", Enum.RenderPriority.Input.Value, integrateLook)

	RunService:BindToRenderStep("SableCamera", Enum.RenderPriority.Camera.Value, function(dt)
		Camera.ThirdPerson = Context.WeaponId == nil

		if not Context.Aiming then
			Camera.FovTarget = baselineFov()
		end

		Camera.setMouseLocked(not Camera.MenuOpen)
		if Camera.MouseLocked and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end

		local ok, err = pcall(apply, dt)
		if not ok then
			warn("[Camera] " .. tostring(err))
		end
	end)
end

return Camera
