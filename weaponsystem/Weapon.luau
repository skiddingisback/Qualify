local RunService = game:GetService("RunService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Fsm = require(Sable.Lib.Fsm)
local Spring = require(Sable.Lib.Spring)
local Rng = require(Sable.Lib.Rng)
local Util = require(Sable.Lib.Util)
local Signal = require(Sable.Lib.Signal)
local Enums = require(Sable.Data.Enums)
local Tuning = require(Sable.Data.Tuning)
local Catalog = require(Sable.Data.Weapons)
local Ballistics = require(Sable.Shared.Ballistics)
local SpreadModel = require(Sable.Shared.Spread)
local RecoilModel = require(Sable.Shared.Recoil)
local WeaponRig = require(Sable.Shared.WeaponRig)
local AnimationSet = require(Sable.Shared.AnimationSet)
local SoundKit = require(Sable.Shared.SoundKit)

local Context = require(script.Parent.Context)
local Input = require(script.Parent.Input)
local Camera = require(script.Parent.Camera)
local Effects = require(script.Parent.Effects)

local Weapon = {}

Weapon.Active = nil
Weapon.Ammo = {}
Weapon.Machine = nil
Weapon.AmmoChanged = Signal.new("ClientAmmoChanged")
Weapon.Fired = Signal.new("ClientFired")
Weapon.SpreadDegrees = 0
Weapon.AimAlpha = 0

local adsSpring = Spring.new(0, Tuning.Viewmodel.AdsStiffness, Tuning.Viewmodel.AdsDamping)
local poseSpring = Spring.new(Vector3.zero, Tuning.Viewmodel.MoveStiffness, Tuning.Viewmodel.MoveDamping)
local swaySpring = Spring.new(Vector2.zero, Tuning.Viewmodel.SwayStiffness, Tuning.Viewmodel.SwayDamping)
local kickSpring = Spring.new(Vector3.zero, Tuning.Viewmodel.RecoilStiffness, Tuning.Viewmodel.RecoilDamping)
local twistSpring = Spring.new(Vector3.zero, Tuning.Viewmodel.RecoilStiffness * 0.8, Tuning.Viewmodel.RecoilDamping)

local triggerHeld = false
local burstRemaining = 0
local lastFire = -math.huge
local lastSway = Vector2.zero
local reloadTokens = {}
local pendingCycle = false
local cueTrack = nil

local function slotState(weaponId)
	local state = Weapon.Ammo[weaponId]
	if not state then
		state = { Magazine = 0, Reserve = 0, Mode = nil, Cycled = true }
		Weapon.Ammo[weaponId] = state
	end
	return state
end

local function cancelReloadTokens()
	for _, token in ipairs(reloadTokens) do
		token.Cancelled = true
	end
	table.clear(reloadTokens)
	cueTrack = nil
end

local function playCue(node, name)
	if name == "ShellIn" then
		SoundKit.pick(node, "ShellIn", 3, { Jitter = 0.07 })
	else
		SoundKit.playFrom(node, name, { Jitter = 0.05 })
	end
end

local function armCues(animationName, cues, node)
	cueTrack = nil

	local active = Weapon.Active
	if not active or not cues or not node or #cues == 0 then
		return
	end

	local track = active.Anims:Get(animationName)
	if not track then
		return
	end

	cueTrack = { Track = track, Node = node, Cues = cues, Fired = {} }
end

local function pumpCues()
	local set = cueTrack
	if not set then
		return
	end

	local track = set.Track
	if not track.IsPlaying or track.Length <= 0 then
		if not track.IsPlaying then
			cueTrack = nil
		end
		return
	end

	local progress = track.TimePosition / track.Length
	for index, cue in ipairs(set.Cues) do
		if not set.Fired[index] and progress >= cue[1] then
			set.Fired[index] = true
			playCue(set.Node, cue[2])
		end
	end
end

local function newToken()
	local token = { Cancelled = false }
	table.insert(reloadTokens, token)
	return token
end

local function detach()
	local active = Weapon.Active
	if not active then
		return
	end

	cancelReloadTokens()
	if active.Anims then
		active.Anims:Destroy()
	end
	if active.Rig then
		active.Rig:Destroy()
	end

	Weapon.Active = nil
	Context.WeaponId = nil
	Context.setAiming(false)
	Weapon.Machine:Force(Enums.Weapon.Stowed)
end

local function attach(tool)
	local weaponId = tool:GetAttribute("WeaponId")
	if not weaponId or not Catalog.exists(weaponId) then
		return
	end

	local rig = Context.Rig
	if not rig then
		return
	end

	detach()

	local weapon = Catalog.get(weaponId)
	local weaponRig = WeaponRig.new(tool)
	if not weaponRig then
		return
	end

	WeaponRig.bind(tool, rig.Character)
	weaponRig:LinkArms(rig.Character)
	Effects.prepareTool(tool)

	local folder = tool:FindFirstChild("AnimsFolder")
	local anims = AnimationSet.new(rig.Animator, folder)

	local sight = weaponRig.Handle:FindFirstChild(weapon.Sights.Attachment)
	local reach = 2.4
	if weaponRig.EndPos and sight then
		reach = (sight.Position - weaponRig.EndPos.Position).Magnitude - (weapon.Sights.EyeRelief or 0.2)
	end

	Weapon.Active = {
		Tool = tool,
		Id = weaponId,
		Weapon = weapon,
		Rig = weaponRig,
		Anims = anims,
		SightNode = sight,
		Spread = SpreadModel.new(weapon),
		Recoil = RecoilModel.new(weapon),
		Reach = math.max(reach, 0.6),
	}

	Context.WeaponId = weaponId
	Context.setSpeedModifier("Weapon", weapon.Handling.Weight)

	burstRemaining = 0
	pendingCycle = false
	posedFrame = CFrame.identity
	adsSpring:Reset(0)
	kickSpring:Reset(Vector3.zero)
	twistSpring:Reset(Vector3.zero)

	Weapon.Machine:Force(Enums.Weapon.Drawing)
end

local function activeAnims()
	local active = Weapon.Active
	return active and active.Anims or nil
end

local function playIdle(fade)
	local active = Weapon.Active
	if not active then
		return
	end
	local anims = active.Anims
	if Context.Sprinting and not Context.Aiming then
		anims:Stop(active.Weapon.Anim.Idle, 0.2)
		if not anims:IsPlaying(active.Weapon.Anim.Run) then
			anims:Play(active.Weapon.Anim.Run, fade or 0.22)
		end
	else
		anims:Stop(active.Weapon.Anim.Run, 0.2)
		if not anims:IsPlaying(active.Weapon.Anim.Idle) then
			anims:Play(active.Weapon.Anim.Idle, fade or 0.22)
		end
	end
end

local function canFire()
	local active = Weapon.Active
	if not active or not Context.canAct() then
		return false
	end
	if not Weapon.Machine:Is(Enums.Weapon.Ready, Enums.Weapon.Firing) then
		return false
	end
	if os.clock() - lastFire < active.Weapon.Fire.Interval then
		return false
	end

	local state = slotState(active.Id)
	if state.Magazine <= 0 then
		return false
	end
	if active.Weapon.Fire.RequiresCycle and not state.Cycled then
		return false
	end
	return true
end

local function dryFire()
	local active = Weapon.Active
	if not active or not active.Rig.TriggerNode then
		return
	end
	SoundKit.playFrom(active.Rig.TriggerNode, "Empty", { Jitter = 0.04 })
end

local function beginCycle()
	local active = Weapon.Active
	if not active then
		return
	end

	local weapon = active.Weapon
	local token = newToken()
	pendingCycle = true

	Weapon.Machine:Force(Enums.Weapon.Cycling)
	active.Anims:RestartScaled(weapon.Anim.Cycle, weapon.Fire.CycleTime, 0.08)
	armCues(weapon.Anim.Cycle, weapon.CycleCues, active.Rig.ReloadNode)

	task.delay(weapon.Fire.CycleTime, function()
		if token.Cancelled or Weapon.Active ~= active then
			return
		end
		pendingCycle = false
		slotState(active.Id).Cycled = true
		Net.Fire("WeaponAction", "Cycled", active.Id)
		Weapon.AmmoChanged:Fire(active.Id, slotState(active.Id))
		if Weapon.Machine:Is(Enums.Weapon.Cycling) then
			Weapon.Machine:Force(Enums.Weapon.Ready)
		end
	end)
end

local function zeroedDirection(active, origin)
	local alpha = math.clamp(adsSpring.Position, 0, 1)
	local look = Camera.lookVector()
	local node = active.SightNode

	if alpha < 0.02 or not node or not node.Parent then
		return look
	end

	local through = node.WorldPosition - origin
	if through.Magnitude < 0.75 then
		return look
	end

	return look:Lerp(through.Unit, alpha).Unit
end

local function fireOnce()
	local active = Weapon.Active
	local weapon = active.Weapon
	local state = slotState(active.Id)
	local context = Context.shotContext()

	lastFire = os.clock()
	state.Magazine -= 1
	if weapon.Fire.RequiresCycle then
		state.Cycled = false
	end
	Weapon.AmmoChanged:Fire(active.Id, state)

	local spreadDegrees = active.Spread:Sample(context)
	local seed = Rng.newSeed()
	local rng = Rng.new(seed)

	local origin = Camera.origin()
	local aim = zeroedDirection(active, origin)
	local directions = Ballistics.pelletFan(weapon, aim, spreadDegrees, rng)

	local ignore = { Context.Character, active.Tool, workspace:FindFirstChild("SableEffects") }
	local claims = {}
	local muzzle = active.Rig:MuzzlePosition()

	Effects.muzzle(active.Rig, weapon)

	for _, direction in ipairs(directions) do
		local trace = Ballistics.trace({
			Origin = origin,
			Direction = direction,
			Weapon = weapon,
			Ignore = ignore,
		})

		local firstSegment = trace.Segments[1]
		if firstSegment then
			Effects.tracer(muzzle, firstSegment.To, weapon)
			for index = 2, #trace.Segments do
				Effects.tracer(trace.Segments[index].From, trace.Segments[index].To, weapon)
			end
		else
			Effects.tracer(muzzle, trace.Terminal, weapon)
		end

		for _, impact in ipairs(trace.Impacts) do
			Effects.impact(impact, weapon)
			if impact.Character then
				table.insert(claims, { P = impact.Instance, X = impact.Position, E = impact.Energy })
			end
		end
	end

	active.Spread:Punch(1)

	local recoilConfig = weapon.Recoil
	local adsAlpha = math.clamp(adsSpring.Position, 0, 1)
	local shakeScale = 1 + ((recoilConfig.AdsVisualScale or 0.7) - 1) * adsAlpha

	active.Recoil:Fire(context)

	local climb, drift = Catalog.recoilStep(weapon, active.Recoil.ShotIndex)
	local spray = recoilConfig.Spray
	local rock = active.Recoil.ShotIndex % 2 == 0 and -1 or 1
	local punchScale = recoilConfig.CameraScale * shakeScale
	local aimEase = 1 - adsAlpha * (1 - recoilConfig.AdsScale)

	local shotPitch = (spray.Pitch + climb * 0.9 * aimEase) * punchScale
	local shotYaw = (spray.Yaw * rock + drift * 0.6 * aimEase) * punchScale
	local shotRoll = (spray.Roll * rock - drift * 0.9 * aimEase) * punchScale

	Camera.viewPunch(shotPitch, shotYaw, shotRoll)
	Camera.fovPunch(Tuning.Camera.FovPunchPerShot * recoilConfig.CameraScale * shakeScale)
	Camera.addTremor(weapon.Fx.Shake * Tuning.Camera.TremorPerShot * shakeScale)

	local modelScale = recoilConfig.ViewScale * (1 - adsAlpha * (recoilConfig.AdsModelDamp or 0.8))
	local shove = Vector3.new(drift * 0.14, 0.3, 1) * 13 * recoilConfig.Punch * modelScale
	local twist = Vector3.new(
		math.rad(shotPitch) * 0.55,
		math.rad(shotYaw) * 0.7,
		math.rad(shotRoll) * 0.9
	) * 34 * recoilConfig.Rise * modelScale

	kickSpring:Impulse(shove)
	twistSpring:Impulse(twist)

	local share = Tuning.Viewmodel.RecoilCounterShare
	task.delay(Tuning.Camera.PunchCounterDelay, function()
		if Weapon.Active ~= active then
			return
		end
		kickSpring:Impulse(-shove * share)
		twistSpring:Impulse(Vector3.new(-twist.X * share, -twist.Y * share, 0))
	end)

	Effects.ejectShell(active.Rig, weapon)

	local fireAnim = (Context.Aiming and active.Anims:Has(weapon.Anim.AimFire)) and weapon.Anim.AimFire or weapon.Anim.Fire
	local fireLength = active.Anims:Length(fireAnim, 0.2)
	active.Anims:RestartScaled(fireAnim, math.min(fireLength, weapon.Fire.Interval * 1.9), 0.02)

	Net.Fire("FireShot", {
		W = active.Id,
		O = origin,
		D = aim,
		S = seed,
		L = 300,
		H = claims,
	})

	Weapon.Fired:Fire(active.Id, spreadDegrees)

	if weapon.Fire.RequiresCycle then
		task.delay(0.12, function()
			if Weapon.Active == active and slotState(active.Id).Magazine >= 0 and not slotState(active.Id).Cycled then
				if Weapon.Machine:Is(Enums.Weapon.Ready, Enums.Weapon.Firing) then
					beginCycle()
				end
			end
		end)
	end
end

local function tryFire()
	local active = Weapon.Active
	if not active then
		return
	end

	if not canFire() then
		local state = slotState(active.Id)
		if state.Magazine <= 0 and os.clock() - lastFire > 0.28 and Weapon.Machine:Is(Enums.Weapon.Ready) then
			lastFire = os.clock()
			dryFire()
		end
		return
	end

	fireOnce()
end

local function requestReload()
	local active = Weapon.Active
	if not active or not Context.canAct() then
		return
	end
	if Weapon.Machine:Is(Enums.Weapon.Reloading, Enums.Weapon.Drawing, Enums.Weapon.Stowing) then
		return
	end

	local state = slotState(active.Id)
	if state.Reserve <= 0 or state.Magazine >= active.Weapon.Ammo.Magazine then
		return
	end

	Net.Fire("RequestReload")
end

local function beginMagazineReload(weapon, duration, wasEmpty)
	local active = Weapon.Active
	local token = newToken()

	Weapon.Machine:Force(Enums.Weapon.Reloading)
	Context.setAiming(false)
	active.Anims:RestartScaled(weapon.Anim.Reload, duration, 0.12)
	armCues(weapon.Anim.Reload, wasEmpty and weapon.Reload.EmptyCues or weapon.Reload.Cues, active.Rig.ReloadNode)

	if wasEmpty and weapon.Reload.ChamberAnim and active.Anims:Has(weapon.Reload.ChamberAnim) then
		task.delay(duration - weapon.Reload.ChamberDuration, function()
			if not token.Cancelled and Weapon.Active == active then
				active.Anims:RestartScaled(weapon.Reload.ChamberAnim, weapon.Reload.ChamberDuration, 0.06)
			end
		end)
	end
end

local function beginShellReload(weapon)
	local active = Weapon.Active
	newToken()

	Weapon.Machine:Force(Enums.Weapon.Reloading)
	Context.setAiming(false)
	active.Anims:RestartScaled(weapon.Anim.ReloadStart, weapon.Reload.StartDuration, 0.1)
end

local function onReloadStage(stage, weaponId, a, b)
	local active = Weapon.Active
	if not active or active.Id ~= weaponId then
		return
	end

	local weapon = active.Weapon

	if stage == "Begin" then
		cancelReloadTokens()
		if weapon.Reload.Kind == "Shell" then
			beginShellReload(weapon)
		else
			beginMagazineReload(weapon, a or weapon.Reload.Duration, b == true)
		end
	elseif stage == "Shell" then
		newToken()
		active.Anims:RestartScaled(weapon.Anim.ReloadStep, weapon.Reload.StepDuration, 0.06)
		armCues(weapon.Anim.ReloadStep, weapon.Reload.StepCues, active.Rig.ReloadNode)
	elseif stage == "Finish" then
		local token = newToken()
		if weapon.Reload.Kind == "Shell" then
			active.Anims:RestartScaled(weapon.Anim.ReloadEnd, weapon.Reload.EndDuration, 0.08)
			armCues(weapon.Anim.ReloadEnd, weapon.Reload.EndCues, active.Rig.ReloadNode)
			task.delay(weapon.Reload.EndDuration, function()
				if not token.Cancelled and Weapon.Active == active and Weapon.Machine:Is(Enums.Weapon.Reloading) then
					Weapon.Machine:Force(Enums.Weapon.Ready)
				end
			end)
		else
			if Weapon.Machine:Is(Enums.Weapon.Reloading) then
				Weapon.Machine:Force(Enums.Weapon.Ready)
			end
		end
	end
end

local function cancelReload()
	if not Weapon.Machine:Is(Enums.Weapon.Reloading) then
		return
	end
	local active = Weapon.Active
	if not active or active.Weapon.Reload.Kind ~= "Shell" then
		return
	end

	cancelReloadTokens()
	Net.Fire("WeaponAction", "CancelReload")
	active.Anims:StopGroup({ active.Weapon.Anim.ReloadStart, active.Weapon.Anim.ReloadStep }, 0.1)
	Weapon.Machine:Force(Enums.Weapon.Ready)
end

local function inspect()
	local active = Weapon.Active
	if not active or not Weapon.Machine:Is(Enums.Weapon.Ready) then
		return
	end

	local weapon = active.Weapon
	if not active.Anims:Has(weapon.Anim.Inspect) then
		return
	end

	local token = newToken()
	Weapon.Machine:Force(Enums.Weapon.Inspecting)
	active.Anims:Play(weapon.Anim.Inspect, 0.12)
	Net.Fire("WeaponAction", "Inspect", active.Id)

	task.delay(active.Anims:Length(weapon.Anim.Inspect, weapon.Handling.Inspect), function()
		if not token.Cancelled and Weapon.Active == active and Weapon.Machine:Is(Enums.Weapon.Inspecting) then
			Weapon.Machine:Force(Enums.Weapon.Ready)
		end
	end)
end

local function switchFiremode()
	local active = Weapon.Active
	if not active then
		return
	end
	if #active.Weapon.Fire.Modes <= 1 then
		return
	end

	Net.Fire("SwitchFiremode")

	if active.Anims:Has(active.Weapon.Anim.ModeSwitch) then
		active.Anims:Restart(active.Weapon.Anim.ModeSwitch, 0.08)
	end
	if active.Rig.TriggerNode then
		SoundKit.playFrom(active.Rig.TriggerNode, "FireModeSwitch", { Jitter = 0.03 })
	end
end

local function aimAllowed()
	if not Context.canAct() or not Weapon.Active then
		return false
	end
	if Context.Sprinting then
		return false
	end
	return Weapon.Machine:Is(Enums.Weapon.Ready, Enums.Weapon.Firing, Enums.Weapon.Cycling)
end

local function updateAim(dt)
	local active = Weapon.Active
	local wants = Input.isDown("Aim") and aimAllowed()

	if wants ~= Context.Aiming then
		Context.setAiming(wants)
		Net.Fire("SetAimState", wants, Camera.Pitch)
	end

	if not active then
		adsSpring.Target = 0
		adsSpring:Update(dt)
		Weapon.AimAlpha = math.clamp(adsSpring.Position, 0, 1)
		Camera.SensitivityScale = 1
		return
	end

	local weapon = active.Weapon
	adsSpring.Target = wants and 1 or 0
	local handling = wants and weapon.Handling.AdsIn or weapon.Handling.AdsOut
	adsSpring:Tune(2 / math.max(handling, 0.05) * 46, 2 / math.max(handling, 0.05) * 13)
	adsSpring:Update(dt)

	local alpha = math.clamp(adsSpring.Position, 0, 1)
	Weapon.AimAlpha = alpha
	Camera.setFov(Util.lerp(Tuning.Camera.BaseFov, weapon.Sights.Fov, alpha))
	Camera.SensitivityScale = Util.lerp(1, weapon.Handling.AdsSpeed, alpha)
	Context.setSpeedModifier("Ads", Util.lerp(1, weapon.Handling.AdsSpeed, alpha))

end

local function proceduralOffset(dt)
	local active = Weapon.Active
	local weapon = active.Weapon

	local delta = Camera.RawDelta
	local follow = Tuning.Viewmodel.SwayFollow
	lastSway = Vector2.new(
		Util.damp(lastSway.X, delta.X, follow, dt),
		Util.damp(lastSway.Y, delta.Y, follow, dt)
	)

	local swayWeight = weapon.Handling.SwayWeight * (1 + Context.armInjury() * 0.8)
	swaySpring.Target = Vector2.new(
		math.clamp(-lastSway.X * Tuning.Viewmodel.SwayTranslation * swayWeight, -Tuning.Viewmodel.SwayClamp, Tuning.Viewmodel.SwayClamp),
		math.clamp(-lastSway.Y * Tuning.Viewmodel.SwayTranslation * swayWeight, -Tuning.Viewmodel.SwayClamp, Tuning.Viewmodel.SwayClamp)
	)
	swaySpring:Update(dt)

	local velocity = Context.Rig:Velocity()
	local local_ = Context.Rig.Root.CFrame:VectorToObjectSpace(velocity)
	poseSpring.Target = Vector3.new(
		math.clamp(-local_.X / 40, -0.12, 0.12),
		math.clamp(local_.Y / 90, -0.14, 0.14),
		math.clamp(-local_.Z / 60, -0.12, 0.12)
	)
	poseSpring:Update(dt)

	kickSpring.Target = Vector3.zero
	kickSpring:Update(dt)
	twistSpring.Target = Vector3.zero
	twistSpring:Update(dt)

	local settle = 1 - math.clamp(adsSpring.Position, 0, 1) * 0.72
	local sway = swaySpring.Position * settle
	local pose = poseSpring.Position * settle
	local kick = kickSpring.Position * Tuning.Viewmodel.RecoilTranslation
	local twist = twistSpring.Position * Tuning.Viewmodel.RecoilRotation

	local recoilFrame = CFrame.new(kick.X, kick.Y, kick.Z)
		* CFrame.Angles(twist.X, twist.Y, twist.Z)

	local swayFrame = CFrame.new(
		sway.X + pose.X,
		sway.Y + pose.Y,
		pose.Z
	) * CFrame.Angles(
		sway.Y * 2.4 + pose.Y * Tuning.Viewmodel.FallTilt * 22,
		sway.X * 2.8,
		-pose.X * Tuning.Viewmodel.MoveTilt * 26
	)

	return recoilFrame, swayFrame
end

local function stancePose()
	local active = Weapon.Active

	if Context.Motion == Enums.Motion.Slide then
		return Tuning.Viewmodel.SlidePose, 1
	end
	if Context.Sprinting and Context.Speed > 6 and not Context.Aiming then
		return Tuning.Viewmodel.SprintPose, math.clamp(Context.Speed / Tuning.Speed.StandSprint, 0, 1)
	end
	if Context.Stance == Enums.Stance.Crouch and active then
		return Catalog.crouchFrame(active.Weapon), 1 - math.clamp(adsSpring.Position, 0, 1)
	end
	if Context.Stance == Enums.Stance.Prone then
		return Tuning.Viewmodel.PronePose, 1
	end
	return CFrame.identity, 0
end

local posedFrame = CFrame.identity

local function yawCatchup(base)
	local rig = Context.Rig
	local torso = rig and rig.Torso
	if not torso or not torso.Parent then
		return CFrame.identity
	end

	local look = torso.CFrame.LookVector
	local torsoYaw = math.atan2(-look.X, -look.Z)
	local drift = (Camera.Yaw - torsoYaw + math.pi) % (math.pi * 2) - math.pi

	local limit = Tuning.Viewmodel.YawCatchupLimit
	drift = math.clamp(drift, -limit, limit) * Tuning.Viewmodel.YawCatchup

	if math.abs(drift) < 1e-4 then
		return CFrame.identity
	end

	local origin = Camera.Frame.Position
	local correction = CFrame.new(origin) * CFrame.Angles(0, drift, 0) * CFrame.new(-origin)
	return base:Inverse() * correction * base
end

local function leanFrame()
	local value = Camera.LeanValue
	if math.abs(value) < 1e-4 then
		return CFrame.identity
	end
	return CFrame.new(value * Tuning.Lean.Offset, 0, 0) * CFrame.Angles(0, 0, -value * Tuning.Lean.Angle)
end

local function renderRig(dt)
	local active = Weapon.Active
	if not active then
		return
	end

	local weaponRig = active.Rig
	if not weaponRig:IsBound() then
		return
	end

	local pivot = weaponRig.PivotFrame
	local inverse = pivot:Inverse()
	local recoilFrame, swayFrame = proceduralOffset(dt)

	local pose, poseWeight = stancePose()
	posedFrame = posedFrame:Lerp(CFrame.identity:Lerp(pose, poseWeight), 1 - math.exp(-Tuning.Viewmodel.PoseSmoothing * dt))

	local hipPose = leanFrame() * Catalog.hipFrame(active.Weapon) * posedFrame
	local base = weaponRig:BaseCFrame()
	local localDelta = yawCatchup(base) * pivot * (recoilFrame * hipPose * swayFrame) * inverse

	local alpha = math.clamp(adsSpring.Position, 0, 1)
	local final = localDelta

	if alpha > 0.001 then
		local weapon = active.Weapon
		local target = Camera.Frame * CFrame.new(0, 0, -active.Reach) * weapon.Sights.Offset
		local sightDelta = weaponRig:SolveSight(target, base) * (pivot * recoilFrame * swayFrame * inverse)
		final = localDelta:Lerp(sightDelta, alpha)
	end

	weaponRig:Apply(final)
end

local function update(dt)
	local active = Weapon.Active

	pumpCues()

	if active then
		local context = Context.shotContext()
		Weapon.SpreadDegrees = active.Spread:Update(dt, context)
		active.Recoil:Update(dt)
	end

	updateAim(dt)

	if not active or not Context.canAct() then
		return
	end

	if Weapon.Machine:Is(Enums.Weapon.Ready, Enums.Weapon.Firing) then
		playIdle()
	end

	if triggerHeld and Context.canAct() then
		local mode = slotState(active.Id).Mode or active.Weapon.Fire.DefaultMode
		if mode == Enums.FireMode.Auto then
			tryFire()
		elseif mode == Enums.FireMode.Burst and burstRemaining > 0 then
			if canFire() then
				burstRemaining -= 1
				fireOnce()
			end
		end
	elseif burstRemaining > 0 then
		if canFire() then
			burstRemaining -= 1
			fireOnce()
		end
	end
end

local STATES = {
	[Enums.Weapon.Stowed] = {},
	[Enums.Weapon.Ready] = {
		Enter = function()
			Context.WeaponBusy = false
			playIdle(0.18)
		end,
	},
	[Enums.Weapon.Firing] = {},
	[Enums.Weapon.Cycling] = {},
	[Enums.Weapon.Inspecting] = {},
	[Enums.Weapon.Reloading] = {},
	[Enums.Weapon.Drawing] = {
		Enter = function()
			local active = Weapon.Active
			if not active then
				return
			end

			Context.WeaponBusy = true
			local weapon = active.Weapon
			active.Anims:PlayScaled(weapon.Anim.Equip, weapon.Handling.Draw, 0.05)
			if active.Rig.TriggerNode then
				SoundKit.playFrom(active.Rig.TriggerNode, "EquipSound", { Jitter = 0.04 })
			end

			task.delay(weapon.Handling.Draw, function()
				if Weapon.Active == active and Weapon.Machine:Is(Enums.Weapon.Drawing) then
					Weapon.Machine:Force(Enums.Weapon.Ready)
				end
			end)
		end,
	},
	[Enums.Weapon.Stowing] = {},
}

function Weapon.start()
	Weapon.Machine = Fsm.new(Weapon, STATES, Enums.Weapon.Stowed)

	Input.Pressed:Connect(function(action)
		if action == "Fire" then
			triggerHeld = true
			local active = Weapon.Active
			if not active then
				return
			end

			if Weapon.Machine:Is(Enums.Weapon.Reloading) then
				cancelReload()
				return
			end

			local mode = slotState(active.Id).Mode or active.Weapon.Fire.DefaultMode
			if mode == Enums.FireMode.Burst then
				burstRemaining = active.Weapon.Fire.BurstCount
			elseif mode ~= Enums.FireMode.Auto then
				tryFire()
			end
		elseif action == "Reload" then
			requestReload()
		elseif action == "Firemode" then
			switchFiremode()
		elseif action == "Inspect" then
			inspect()
		end
	end)

	Input.Released:Connect(function(action)
		if action == "Fire" then
			triggerHeld = false
			local active = Weapon.Active
			if active then
				active.Recoil:Release()
			end
		end
	end)

	Net.On("AmmoSync", function(weaponId, magazine, reserve, chambered, mode, cycled)
		local state = slotState(weaponId)
		state.Magazine = magazine
		state.Reserve = reserve
		state.Chambered = chambered
		state.Mode = mode
		state.Cycled = cycled
		Weapon.AmmoChanged:Fire(weaponId, state)
	end)

	Net.On("ReloadStage", onReloadStage)

	Context.CharacterReady:Connect(function(rig)
		detach()

		rig.Character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				task.defer(attach, child)
			end
		end)

		rig.Character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") and Weapon.Active and Weapon.Active.Tool == child then
				detach()
			end
		end)

		local existing = rig:CurrentTool()
		if existing then
			task.defer(attach, existing)
		end
	end)

	Context.CharacterLost:Connect(detach)

	RunService:BindToRenderStep("SableWeapon", Enum.RenderPriority.Camera.Value + 5, function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			warn("[Weapon] update: " .. tostring(err))
		end
	end)

	RunService:BindToRenderStep("SableWeaponRig", Enum.RenderPriority.Character.Value + 10, function(dt)
		if not Weapon.Active then
			return
		end
		local ok, err = pcall(renderRig, dt)
		if not ok then
			warn("[Weapon] rig: " .. tostring(err))
		end
	end)
end

return Weapon
