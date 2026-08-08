local RunService = game:GetService("RunService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Net = require(Sable.Lib.Net)
local Util = require(Sable.Lib.Util)
local Enums = require(Sable.Data.Enums)
local Tuning = require(Sable.Data.Tuning)
local Posture = require(Sable.Shared.Posture)

local Context = require(script.Parent.Context)
local Camera = require(script.Parent.Camera)

local UpperBody = {}

local posture = nil
local blend = 0
local lastSend = 0

local function targetWeight()
	if not Context.canAct() then
		return 0
	end
	if Context.Motion == Enums.Motion.Vault or Context.Motion == Enums.Motion.Slide then
		return 0.35
	end
	if not Context.WeaponId then
		return 0.45
	end
	if Context.Sprinting and Context.Speed > 6 and not Context.Aiming then
		return 0.55
	end
	return 1
end

local function step(dt)
	if not posture then
		return
	end

	local rig = Context.Rig
	if not rig or not rig.Torso or not rig.Torso.Parent then
		return
	end

	posture:Track(rig:CurrentTool())
	blend = Util.damp(blend, targetWeight(), 14, dt)

	local lean = -Camera.LeanValue * Tuning.Lean.Angle * Tuning.Lean.BodyShare

	if blend < 0.005 and math.abs(lean) < 1e-4 then
		posture:Relax()
	else
		posture:Apply(Camera.Pitch * blend, lean)
	end

	if os.clock() - lastSend > 0.1 then
		lastSend = os.clock()
		Net.Fire("SetLook", Camera.Pitch, lean)
	end
end

function UpperBody.start()
	Context.CharacterReady:Connect(function(rig)
		if posture then
			posture:Destroy()
		end
		blend = 0
		posture = Posture.new(rig, { BodyScale = 0.92, HeadScale = 0.3 })
	end)

	Context.CharacterLost:Connect(function()
		if posture then
			posture:Destroy()
			posture = nil
		end
	end)

	RunService:BindToRenderStep("SableUpperBody", Enum.RenderPriority.Character.Value + 6, function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[UpperBody] " .. tostring(err))
		end
	end)
end

return UpperBody
