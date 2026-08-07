local RunService = game:GetService("RunService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Fsm = require(Sable.Lib.Fsm)
local Util = require(Sable.Lib.Util)
local Enums = require(Sable.Data.Enums)
local Tuning = require(Sable.Data.Tuning)
local Materials = require(Sable.Data.Materials)
local Animations = require(Sable.Data.Animations)
local SoundKit = require(Sable.Shared.SoundKit)

local Context = require(script.Parent.Context)
local Input = require(script.Parent.Input)

local Locomotion = {}
Locomotion.Machine = nil
Locomotion.Grounded = true
Locomotion.GroundPart = nil
Locomotion.SlideVelocity = Vector3.zero

local stanceAlpha = 0
local stanceTarget = 0
local hipDrop = 0
local hipTarget = 0
local baseHipHeight = 0
local lastJump = -math.huge
local lastVault = -math.huge
local lastSlide = -math.huge
local lastStaminaUse = -math.huge
local footTimer = 0
local footPhase = 1
local airTime = 0
local fallSpeed = 0
local exhausted = false
local walkSpeed = 0
local bodyTracks = nil
local climbTrack = nil
local publishAccumulator = 0

local STANCE_HEIGHT = {
	[Enums.Stance.Stand] = 0,
	[Enums.Stance.Crouch] = Tuning.Stance.CrouchCameraDrop,
	[Enums.Stance.Prone] = Tuning.Stance.ProneCameraDrop,
}

local STANCE_HIP = {
	[Enums.Stance.Stand] = 0,
	[Enums.Stance.Crouch] = Tuning.Stance.CrouchHipDrop,
	[Enums.Stance.Prone] = Tuning.Stance.ProneHipDrop,
}

local function rig()
	return Context.Rig
end

local function raycast(origin, direction, extra)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { Context.Character }
	if extra then
		for _, item in ipairs(extra) do
			table.insert(filter, item)
		end
	end
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	return workspace:Raycast(origin, direction, params)
end

function Locomotion.stanceOffset()
	return stanceAlpha
end

function Locomotion.headClearance()
	local current = rig()
	if not current then
		return true
	end
	local origin = current.Root.Position
	local result = raycast(origin, Vector3.new(0, Tuning.Stance.ClearanceRadius + 2.4, 0))
	return result == nil
end

local function loadStanceTracks()
	local current = rig()
	if not current then
		return
	end

	Animations.release(bodyTracks)
	bodyTracks = Animations.build(current.Animator, Animations.Body)

	local animateScript = Context.Character:FindFirstChild("Animate")
	local climbHolder = animateScript and animateScript:FindFirstChild("climb")
	local climbAnim = climbHolder and climbHolder:FindFirstChildOfClass("Animation")

	if climbAnim and climbAnim.AnimationId ~= "" then
		local ok, track = pcall(function()
			return current.Animator:LoadAnimation(climbAnim)
		end)
		if ok then
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			climbTrack = track
		end
	end
end

function Locomotion.bodyTracks()
	return bodyTracks
end

local function refreshStanceAnimations()
	local stance = Context.Stance
	local sliding = Locomotion.Machine and Locomotion.Machine:Is(Enums.Motion.Slide)

	Animations.toggle(bodyTracks, "Slide", sliding == true)
	Animations.toggle(bodyTracks, "Crouch", stance == Enums.Stance.Crouch and not sliding)
	Animations.toggle(bodyTracks, "Downed", Context.Downed)
end

local function refreshInjuryAnimations()
	local vitals = Context.Vitals
	if not vitals or not vitals.Limbs then
		return
	end

	local function broken(limb)
		local data = vitals.Limbs[limb]
		return data ~= nil and data[2] == 1
	end

	local armed = Context.WeaponId ~= nil
	Animations.toggle(bodyTracks, "BrokenRightArm", broken(Enums.Limb.RightArm) and not armed, 0.8)
	Animations.toggle(bodyTracks, "BrokenLeftArm", broken(Enums.Limb.LeftArm) and not armed, 0.8)
	Animations.toggle(bodyTracks, "BrokenRightLeg", broken(Enums.Limb.RightLeg), 0.45)
	Animations.toggle(bodyTracks, "BrokenLeftLeg", broken(Enums.Limb.LeftLeg), 0.45)
end

function Locomotion.baseSpeed()
	local stance = Context.Stance
	if stance == Enums.Stance.Prone then
		return Tuning.Speed.ProneWalk
	elseif stance == Enums.Stance.Crouch then
		return Tuning.Speed.CrouchWalk
	end

	if Context.Sprinting then
		return Tuning.Speed.StandSprint
	end
	return Tuning.Speed.StandWalk
end

function Locomotion.resolvedSpeed()
	local speed = Locomotion.baseSpeed() * Context.speedMultiplier()

	local legs = Context.legInjury()
	if legs > 0 then
		speed *= math.max(1 - legs * Tuning.Vitals.BrokenLimbSpeedPenalty, 0.3)
	end

	if Context.Downed then
		return Tuning.Speed.Downed
	end

	local move = Input.moveVector()
	if move.Y > 0.4 then
		speed *= Tuning.Speed.BackpedalScale
	elseif math.abs(move.X) > 0.7 then
		speed *= Tuning.Speed.StrafeScale
	end

	return math.max(speed, 0)
end

local function canSprint()
	if not Context.canAct() then
		return false
	end
	if exhausted or Context.Stamina <= Tuning.Stamina.SprintFloor then
		return false
	end
	if Context.Stance ~= Enums.Stance.Stand then
		return false
	end
	if Context.Aiming or Context.WeaponBusy then
		return false
	end
	local move = Input.moveVector()
	return move.Y < -0.35
end

local function spendStamina(amount)
	Context.Stamina = math.max(Context.Stamina - amount, 0)
	lastStaminaUse = os.clock()
	if Context.Stamina <= 0.5 then
		exhausted = true
	end
end

local function updateStamina(dt)
	if Context.Sprinting and Context.Speed > 4 then
		spendStamina(Tuning.Stamina.SprintDrain * dt)
		return
	end

	local delay = exhausted and Tuning.Stamina.ExhaustedRegenDelay or Tuning.Stamina.RegenDelay
	if os.clock() - lastStaminaUse < delay then
		return
	end

	local rate = Tuning.Stamina.Regen
	if Context.Stance ~= Enums.Stance.Stand then
		rate *= Tuning.Stamina.CrouchRegenBonus
	end

	Context.Stamina = math.min(Context.Stamina + rate * dt, Tuning.Stamina.Max)
	if exhausted and Context.Stamina > Tuning.Stamina.Max * 0.35 then
		exhausted = false
	end
end

local function updateGround()
	local current = rig()
	if not current then
		return
	end

	local humanoid = current.Humanoid
	local state = humanoid:GetState()
	local grounded = state ~= Enum.HumanoidStateType.Freefall
		and state ~= Enum.HumanoidStateType.Jumping
		and state ~= Enum.HumanoidStateType.Flying

	local part, _, _, distance = current:GroundInfo(6)
	Locomotion.GroundPart = part

	if part and distance and distance <= 3.6 then
		grounded = true
	end

	if Locomotion.Grounded and not grounded then
		airTime = 0
	end

	if not grounded then
		airTime += 1 / 60
		fallSpeed = math.max(fallSpeed, -current:Velocity().Y)
	elseif not Locomotion.Grounded then
		Context.Landed:Fire(fallSpeed, part)
		if fallSpeed > Tuning.Footsteps.LandThreshold then
			local soundId = Materials.StepFor(part)
			SoundKit.spatial(soundId, current.Root.Position, { Volume = 0.7, Pitch = 0.75, MaxDistance = 90 })
		end
		fallSpeed = 0
	end

	Locomotion.Grounded = grounded
	Context.Airborne = not grounded
end

function Locomotion.stepCadence(humanoid, planarSpeed)
	local config = Tuning.Footsteps
	local gait = math.min((humanoid.WalkSpeed + math.min(planarSpeed, humanoid.WalkSpeed)) * 0.5, 50)
	local interval = config.Cadence / math.max(gait / config.CadenceReference, 0.05)
	return math.clamp(interval, config.CadenceMin, config.CadenceMax)
end

local function updateFootsteps(dt)
	local current = rig()
	if not current or not Locomotion.Grounded or Context.Speed < 1.5 then
		footTimer = 0
		return
	end

	local config = Tuning.Footsteps
	local stance = Context.Stance
	local sprinting = Context.Sprinting and stance == Enums.Stance.Stand

	local volume = config.Volume.Walk
	local emitter = config.Emitter.Walk
	local interval = Locomotion.stepCadence(current.Humanoid, Context.Speed)

	if stance == Enums.Stance.Prone then
		volume, emitter = config.Volume.Prone, config.Emitter.Prone
		interval *= config.StanceInterval.Prone
	elseif stance == Enums.Stance.Crouch then
		volume, emitter = config.Volume.Crouch, config.Emitter.Crouch
		interval *= config.StanceInterval.Crouch
	elseif sprinting then
		volume, emitter = config.Volume.Sprint, config.Emitter.Sprint
	end

	footTimer += dt
	if footTimer < interval then
		return
	end
	footTimer = 0
	footPhase = footPhase == 1 and 2 or 1

	local soundId, pitch = Materials.StepFor(Locomotion.GroundPart)
	SoundKit.spatial(soundId, current.Root.Position - Vector3.new(0, 2.6, 0), {
		Volume = volume,
		Pitch = (pitch or 1) * (footPhase == 1 and 1 or 0.94),
		MaxDistance = Tuning.Footsteps.AudibleRadius,
		EmitterSize = emitter,
		Distortion = sprinting and config.SprintDistortion or nil,
		Jitter = 0.1,
	})
	Context.Footstep:Fire(footPhase)
end

local function probeLedge()
	local current = rig()
	if not current then
		return nil
	end

	local root = current.Root
	local forward = Util.safeUnit(Util.flatten(root.CFrame.LookVector))
	if forward.Magnitude < 0.5 then
		return nil
	end

	local chest = root.Position + Vector3.new(0, 0.2, 0)
	local wall = raycast(chest, forward * Tuning.Vault.ProbeDistance)
	if not wall or wall.Normal:Dot(Vector3.yAxis) > 0.55 then
		return nil
	end

	local feetY = root.Position.Y - 2
	local above = wall.Position + forward * 0.35 + Vector3.new(0, Tuning.Vault.MaxLedge + 1.5, 0)
	local top = raycast(above, Vector3.new(0, -(Tuning.Vault.MaxLedge + 3), 0))
	if not top then
		return nil
	end

	local height = top.Position.Y - feetY
	if height < Tuning.Vault.MinLedge or height > Tuning.Vault.MaxLedge then
		return nil
	end

	local standing = top.Position + Vector3.new(0, 3, 0)
	if raycast(standing, Vector3.new(0, Tuning.Vault.ClearanceHeight - 3, 0)) then
		return nil
	end

	local landing = top.Position + forward * Tuning.Vault.ClearanceDepth + Vector3.new(0, 3, 0)
	if raycast(top.Position + Vector3.new(0, 2.6, 0), forward * Tuning.Vault.ClearanceDepth) then
		landing = top.Position + forward * 0.6 + Vector3.new(0, 3, 0)
	end

	return landing, height, forward
end

local function performVault(landing, height, forward)
	local current = rig()
	if not current then
		return
	end

	local root = current.Root
	local humanoid = current.Humanoid
	local duration = height > 3 and Tuning.Vault.TallDuration or Tuning.Vault.ShortDuration
	local startCFrame = root.CFrame
	local peak = math.max(startCFrame.Position.Y, landing.Y) + 0.8

	root.Anchored = true
	humanoid.AutoRotate = false
	spendStamina(Tuning.Stamina.VaultCost)
	lastVault = os.clock()

	if climbTrack then
		climbTrack:Play(0.1)
		climbTrack:AdjustSpeed(climbTrack.Length > 0 and climbTrack.Length / duration or 1)
	end

	local elapsed = 0
	while elapsed < duration do
		local dt = RunService.RenderStepped:Wait()
		elapsed += dt

		if not root.Parent or not Context.alive() then
			break
		end

		local alpha = math.clamp(elapsed / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 2
		local flat = startCFrame.Position:Lerp(landing, eased)
		local arc = math.sin(alpha * math.pi) * (peak - math.max(startCFrame.Position.Y, landing.Y)) * 0.6
		local lift = Util.lerp(startCFrame.Position.Y, landing.Y, eased) + arc

		root.CFrame = CFrame.new(Vector3.new(flat.X, lift, flat.Z)) * (startCFrame - startCFrame.Position)
	end

	if root.Parent then
		root.Anchored = false
		root.AssemblyLinearVelocity = forward * Tuning.Vault.ForwardBoost
	end

	if climbTrack then
		climbTrack:Stop(0.15)
	end
end

local function tryVault()
	if os.clock() - lastVault < Tuning.Vault.Cooldown then
		return false
	end
	if Context.Stamina < Tuning.Stamina.VaultCost then
		return false
	end
	if Context.Stance == Enums.Stance.Prone then
		return false
	end

	local landing, height, forward = probeLedge()
	if not landing then
		return false
	end

	Locomotion.Machine:Force(Enums.Motion.Vault)
	task.spawn(function()
		performVault(landing, height, forward)
		if Locomotion.Machine.Current == Enums.Motion.Vault then
			Locomotion.Machine:Force(Enums.Motion.Idle)
		end
	end)
	return true
end

local function tryJump()
	local current = rig()
	if not current or not Context.canAct() then
		return
	end

	if tryVault() then
		return
	end

	if not Locomotion.Grounded or os.clock() - lastJump < Tuning.Jump.Cooldown then
		return
	end
	if Context.Stance ~= Enums.Stance.Stand then
		Locomotion.setStance(Enums.Stance.Stand)
		return
	end
	if Context.Stamina < Tuning.Stamina.JumpCost then
		return
	end

	lastJump = os.clock()
	spendStamina(Tuning.Stamina.JumpCost)
	current.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

function Locomotion.setStance(stance)
	if stance ~= Enums.Stance.Stand and not Context.canAct() then
		return false
	end
	if stance == Enums.Stance.Stand and Context.Stance ~= Enums.Stance.Stand then
		if not Locomotion.headClearance() then
			return false
		end
	end

	if not Context.setStance(stance) then
		return false
	end

	stanceTarget = STANCE_HEIGHT[stance] or 0
	hipTarget = STANCE_HIP[stance] or 0
	refreshStanceAnimations()
	Net.Fire("SetStance", stance, Context.Motion)
	return true
end

function Locomotion.toggleStance(stance)
	if Context.Stance == stance then
		return Locomotion.setStance(Enums.Stance.Stand)
	end
	return Locomotion.setStance(stance)
end

local function enterSlide()
	local current = rig()
	if not current then
		return false
	end
	if os.clock() - lastSlide < Tuning.Slide.Cooldown then
		return false
	end
	if Context.Speed < Tuning.Slide.MinimumSpeed or not Locomotion.Grounded then
		return false
	end
	if Context.Stamina < Tuning.Stamina.SlideCost then
		return false
	end

	local velocity = Util.flatten(current:Velocity())
	if velocity.Magnitude < Tuning.Slide.MinimumSpeed * 0.6 then
		return false
	end

	Locomotion.SlideVelocity = velocity
	spendStamina(Tuning.Stamina.SlideCost)
	lastSlide = os.clock()
	return Locomotion.Machine:Force(Enums.Motion.Slide)
end

local function updateSlide(dt)
	local current = rig()
	if not current then
		return
	end

	local machine = Locomotion.Machine
	local velocity = Locomotion.SlideVelocity
	local speed = velocity.Magnitude

	local _, _, normal = current:GroundInfo(5)
	if normal then
		local slope = Vector3.new(normal.X, 0, normal.Z)
		if slope.Magnitude > 0.05 then
			velocity += slope.Unit * Tuning.Slide.SlopeAccel * slope.Magnitude * dt
		end
	end

	local steer = Input.moveVector()
	if steer.Magnitude > 0.1 then
		local right = current.Root.CFrame.RightVector
		velocity += right * steer.X * Tuning.Slide.SteerAuthority * dt * speed * 0.1
	end

	velocity -= Util.safeUnit(velocity) * Tuning.Slide.Friction * dt
	Locomotion.SlideVelocity = velocity

	local root = current.Root
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, root.AssemblyLinearVelocity.Y, velocity.Z)

	if velocity.Magnitude < Tuning.Slide.ExitSpeed or machine:Elapsed() > Tuning.Slide.Duration or not Locomotion.Grounded then
		if Input.isDown("Crouch") or not Locomotion.headClearance() then
			Locomotion.setStance(Enums.Stance.Crouch)
		else
			Locomotion.setStance(Enums.Stance.Stand)
		end
		machine:Force(Enums.Motion.Idle)
	end
end

local function applyMovement(dt)
	local current = rig()
	if not current then
		return
	end

	local humanoid = current.Humanoid
	local move = Input.moveVector()
	local yaw = Context.LookYaw
	local facing = CFrame.Angles(0, yaw, 0)
	local direction = facing:VectorToWorldSpace(Vector3.new(move.X, 0, move.Y))

	if Locomotion.Machine:Is(Enums.Motion.Slide, Enums.Motion.Vault) then
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero, false)
		return
	end

	local target = Locomotion.resolvedSpeed()
	if not Locomotion.Grounded then
		target *= 1 - Tuning.Jump.AirControl * 0.35
	end

	walkSpeed = Util.damp(walkSpeed, target, Tuning.Speed.WalkSpeedSmoothing, dt)
	humanoid.WalkSpeed = walkSpeed
	humanoid:Move(direction, false)
end

local function classifyMotion()
	if Context.Downed then
		return Enums.Motion.Downed
	end
	if not Locomotion.Grounded then
		return Enums.Motion.Airborne
	end
	if Context.Speed < 0.8 then
		return Enums.Motion.Idle
	end
	if Context.Sprinting then
		return Enums.Motion.Sprint
	end
	return Enums.Motion.Walk
end

local STATES = {
	[Enums.Motion.Idle] = {},
	[Enums.Motion.Walk] = {},
	[Enums.Motion.Sprint] = {},
	[Enums.Motion.Airborne] = {},
	[Enums.Motion.Downed] = {},
	[Enums.Motion.Vault] = {},
	[Enums.Motion.Slide] = {
		Enter = function()
			Context.setStance(Enums.Stance.Crouch)
			stanceTarget = Tuning.Slide.CameraDrop
			hipTarget = Tuning.Stance.CrouchHipDrop
			refreshStanceAnimations()
		end,
		Update = function(_, _, dt)
			updateSlide(dt)
		end,
		Exit = function()
			stanceTarget = STANCE_HEIGHT[Context.Stance] or 0
			hipTarget = STANCE_HIP[Context.Stance] or 0
			task.defer(refreshStanceAnimations)
		end,
	},
}

local function step(dt)
	local current = rig()
	if not current or not current.Root.Parent then
		return
	end

	Context.Speed = Util.damp(Context.Speed, current:PlanarSpeed(), Tuning.Speed.ReadoutSmoothing, dt)

	updateGround()

	local wantsSprint = Input.isDown("Sprint") and canSprint() and Locomotion.Grounded
	if wantsSprint ~= Context.Sprinting then
		Context.Sprinting = wantsSprint
	end

	updateStamina(dt)
	applyMovement(dt)

	if not Locomotion.Machine:Is(Enums.Motion.Slide, Enums.Motion.Vault) then
		local motion = classifyMotion()
		if motion ~= Locomotion.Machine.Current then
			Locomotion.Machine:Force(motion)
		end
		Context.setMotion(motion)
	else
		Context.setMotion(Locomotion.Machine.Current)
	end

	Locomotion.Machine:Update(dt)
	updateFootsteps(dt)
	refreshInjuryAnimations()

	stanceAlpha = Util.damp(stanceAlpha, stanceTarget, 12, dt)
	hipDrop = Util.damp(hipDrop, hipTarget, Tuning.Stance.HipSmoothing, dt)
	current.Humanoid.HipHeight = baseHipHeight - hipDrop

	publishAccumulator += dt
	if publishAccumulator > 0.15 then
		publishAccumulator = 0
		Net.Fire("SetStance", Context.Stance, Context.Motion)
	end
end

local function onCharacter(newRig)
	stanceAlpha = 0
	stanceTarget = 0
	hipDrop = 0
	hipTarget = 0
	baseHipHeight = newRig.Humanoid.HipHeight
	exhausted = false
	walkSpeed = Tuning.Speed.StandWalk
	climbTrack = nil
	Locomotion.Grounded = true
	Locomotion.SlideVelocity = Vector3.zero

	newRig.Humanoid.AutoRotate = false
	newRig.Humanoid.UseJumpPower = true
	newRig.Humanoid.JumpPower = Tuning.Jump.Power

	loadStanceTracks()
	Locomotion.Machine:Force(Enums.Motion.Idle)
end

function Locomotion.start()
	Locomotion.Machine = Fsm.new(Locomotion, STATES, Enums.Motion.Idle)

	Input.Pressed:Connect(function(action)
		if not Context.canAct() then
			return
		end

		if action == "Jump" then
			tryJump()
		elseif action == "Crouch" then
			if Context.Sprinting and Locomotion.Grounded and Context.Speed > Tuning.Slide.MinimumSpeed then
				if not enterSlide() then
					Locomotion.setStance(Enums.Stance.Crouch)
				end
			else
				Locomotion.setStance(Enums.Stance.Crouch)
			end
		end
	end)

	Input.Released:Connect(function(action)
		if action ~= "Crouch" then
			return
		end
		if Locomotion.Machine:Is(Enums.Motion.Slide) then
			return
		end
		Locomotion.setStance(Enums.Stance.Stand)
	end)

	Context.CharacterReady:Connect(onCharacter)
	Context.CharacterLost:Connect(function()
		Animations.release(bodyTracks)
		bodyTracks = nil
		climbTrack = nil
	end)

	RunService:BindToRenderStep("SableLocomotion", Enum.RenderPriority.Input.Value + 10, function(dt)
		if Context.Rig then
			local ok, err = pcall(step, dt)
			if not ok then
				warn("[Locomotion] " .. tostring(err))
			end
		end
	end)
end

return Locomotion
