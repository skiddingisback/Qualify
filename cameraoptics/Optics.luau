local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Util = require(Sable.Lib.Util)
local Enums = require(Sable.Data.Enums)
local Tuning = require(Sable.Data.Tuning)

local Context = require(script.Parent.Context)
local Camera = require(script.Parent.Camera)
local Weapon = require(script.Parent.Weapon)

local Optics = {}

local depthOfField
local blur
local correction

local blurLevel = 0
local blurPulse = 0
local flashPulse = 0
local damageLevel = 0
local strafeRoll = 0
local lastHealth = math.huge

local function ensure(className, name, props)
	local effect = Lighting:FindFirstChild(name)
	if not effect or not effect:IsA(className) then
		effect = Instance.new(className)
		effect.Name = name
		effect.Parent = Lighting
	end
	for key, value in pairs(props or {}) do
		effect[key] = value
	end
	return effect
end

function Optics.pulse(amount)
	blurPulse = math.min(blurPulse + amount, 12)
end

function Optics.flash(amount)
	flashPulse = math.min(flashPulse + amount, 3)
end

function Optics.sting(amount)
	damageLevel = math.min(damageLevel + amount, 1)
end

local function aimAlpha()
	return math.clamp(Weapon.AimAlpha or 0, 0, 1)
end

local function updateFocus(dt)
	local optics = Tuning.Optics
	local alpha = aimAlpha()

	depthOfField.FocusDistance = Util.damp(
		depthOfField.FocusDistance,
		Util.lerp(optics.RestFocusDistance, optics.AdsFocusDistance, alpha),
		optics.FocusSmoothing, dt
	)
	depthOfField.InFocusRadius = Util.damp(
		depthOfField.InFocusRadius,
		Util.lerp(optics.RestInFocusRadius, optics.AdsInFocusRadius, alpha),
		optics.FocusSmoothing, dt
	)
	depthOfField.NearIntensity = Util.damp(
		depthOfField.NearIntensity,
		Util.lerp(optics.RestNearIntensity, optics.AdsNearIntensity, alpha),
		optics.FocusSmoothing, dt
	)
	depthOfField.FarIntensity = Util.damp(
		depthOfField.FarIntensity,
		Util.lerp(optics.RestFarIntensity, optics.AdsFarIntensity, alpha),
		optics.FocusSmoothing, dt
	)
end

local function motionBlurTarget()
	local optics = Tuning.Optics

	if Context.Motion == Enums.Motion.Slide then
		return optics.SlideBlur
	end
	if Context.Sprinting and Context.Speed > 8 then
		local ramp = math.clamp((Context.Speed - 8) / (Tuning.Speed.StandSprint - 8), 0, 1)
		return optics.SprintBlur * ramp
	end
	return 0
end

local function updateBlur(dt)
	local optics = Tuning.Optics

	blurPulse = math.max(blurPulse - optics.BlurDecay * dt, 0)
	flashPulse = math.max(flashPulse - optics.BlurDecay * dt, 0)
	blurLevel = Util.damp(blurLevel, motionBlurTarget(), 6, dt)
	blur.Size = blurLevel + blurPulse
	blur.Enabled = blur.Size > 0.05
end

local function updateTone(dt)
	local optics = Tuning.Optics
	local vitals = Context.Vitals

	damageLevel = math.max(damageLevel - optics.DamageDecay * dt, 0)

	local fraction = 1
	if vitals and vitals.MaxHealth > 0 then
		fraction = math.clamp(vitals.Health / vitals.MaxHealth, 0, 1)
	end

	local starved = math.clamp(1 - fraction / optics.LowHealthFraction, 0, 1)
	local pulse = starved > 0 and (0.5 + 0.5 * math.sin(os.clock() * optics.LowHealthPulse)) or 0

	correction.TintColor = Color3.new(1, 1, 1):Lerp(optics.DamageTint, math.max(damageLevel, starved * 0.35 * pulse))
	correction.Saturation = optics.LowHealthSaturation * starved
	correction.Brightness = flashPulse * optics.FireBrightness
	correction.Enabled = damageLevel > 0.01 or starved > 0.01 or flashPulse > 0.05
end

local function updateStrafe(dt)
	local rig = Context.Rig
	if not rig or not rig.Root.Parent then
		return
	end

	local velocity = rig.Root.CFrame:VectorToObjectSpace(rig:Velocity())
	local lateral = math.clamp(velocity.X / Tuning.Speed.StandSprint, -1, 1)
	local target = -lateral * Tuning.Optics.StrafeRoll * (1 - aimAlpha() * 0.6)

	strafeRoll = Util.damp(strafeRoll, target, Tuning.Optics.StrafeSmoothing, dt)
	Camera.StrafeRoll = strafeRoll
end

local function step(dt)
	updateFocus(dt)
	updateBlur(dt)
	updateTone(dt)
	updateStrafe(dt)
end

function Optics.start()
	depthOfField = ensure("DepthOfFieldEffect", "DepthOfField", { Enabled = true })
	blur = ensure("BlurEffect", "SableMotionBlur", { Size = 0, Enabled = false })
	correction = ensure("ColorCorrectionEffect", "SableTone", {
		Enabled = false,
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	})

	Camera.StrafeRoll = 0

	Weapon.Fired:Connect(function()
		local optics = Tuning.Optics
		Optics.pulse(Util.lerp(optics.FireBlur, optics.FireBlurAds, aimAlpha()))
		Optics.flash(Util.lerp(optics.FireBlur, optics.FireBlurAds, aimAlpha()))
	end)

	Context.Landed:Connect(function(speed)
		Optics.pulse(math.clamp(speed / 40, 0, 1) * Tuning.Optics.LandBlur)
	end)

	Context.VitalsChanged:Connect(function(payload)
		if payload.Health < lastHealth - 0.5 then
			Optics.sting(Tuning.Optics.DamagePerHit)
		end
		lastHealth = payload.Health
	end)

	Context.CharacterReady:Connect(function()
		lastHealth = math.huge
		damageLevel = 0
		blurPulse = 0
		flashPulse = 0
		blurLevel = 0
	end)

	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[Optics] " .. tostring(err))
		end
	end)
end

return Optics
