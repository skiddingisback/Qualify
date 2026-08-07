local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Sable = game:GetService("ReplicatedStorage"):WaitForChild("Sable")
local Signal = require(Sable.Lib.Signal)

local Input = {}

Input.Bindings = {
	Forward = { Enum.KeyCode.W },
	Backward = { Enum.KeyCode.S },
	Left = { Enum.KeyCode.A },
	Right = { Enum.KeyCode.D },
	Sprint = { Enum.KeyCode.LeftShift },
	Crouch = { Enum.KeyCode.C },
	ShoulderLock = { Enum.KeyCode.LeftAlt },
	LeanLeft = { Enum.KeyCode.Q },
	LeanRight = { Enum.KeyCode.E },
	Fire = { Enum.UserInputType.MouseButton1 },
	Aim = { Enum.UserInputType.MouseButton2 },
	Reload = { Enum.KeyCode.R },
	Firemode = { Enum.KeyCode.V },
	Inspect = { Enum.KeyCode.F },
	Cycle = { Enum.KeyCode.X },
	Interact = { Enum.KeyCode.F },
}

Input.State = {}
Input.Pressed = Signal.new("ActionPressed")
Input.Released = Signal.new("ActionReleased")
Input.MouseDelta = Vector2.zero

local lookup = {}
local frameDelta = Vector2.zero

local function indexBindings()
	table.clear(lookup)
	for action, keys in pairs(Input.Bindings) do
		Input.State[action] = false
		for _, key in ipairs(keys) do
			local bucket = lookup[key]
			if not bucket then
				bucket = {}
				lookup[key] = bucket
			end
			table.insert(bucket, action)
		end
	end
end

function Input.isDown(action)
	return Input.State[action] == true
end

function Input.moveVector()
	local x = (Input.State.Right and 1 or 0) - (Input.State.Left and 1 or 0)
	local z = (Input.State.Backward and 1 or 0) - (Input.State.Forward and 1 or 0)
	if x == 0 and z == 0 then
		return Vector2.zero
	end
	return Vector2.new(x, z).Unit
end

function Input.leanAxis()
	return (Input.State.LeanRight and 1 or 0) - (Input.State.LeanLeft and 1 or 0)
end

function Input.consumeMouseDelta()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		frameDelta = Vector2.zero
		local delta = UserInputService:GetMouseDelta()
		return Vector2.new(delta.X, delta.Y)
	end

	local delta = frameDelta
	frameDelta = Vector2.zero
	return delta
end

function Input.rebind(action, keys)
	Input.Bindings[action] = keys
	indexBindings()
end

local function dispatch(key, began, processed)
	local actions = lookup[key]
	if not actions then
		return
	end

	for _, action in ipairs(actions) do
		if began then
			if processed then
				continue
			end
			if not Input.State[action] then
				Input.State[action] = true
				Input.Pressed:Fire(action)
			end
		else
			if Input.State[action] then
				Input.State[action] = false
				Input.Released:Fire(action)
			end
		end
	end
end

function Input.releaseAll()
	for action, down in pairs(Input.State) do
		if down then
			Input.State[action] = false
			Input.Released:Fire(action)
		end
	end
end

function Input.start()
	indexBindings()

	UserInputService.InputBegan:Connect(function(input, processed)
		dispatch(input.KeyCode, true, processed)
		dispatch(input.UserInputType, true, processed)
	end)

	UserInputService.InputEnded:Connect(function(input)
		dispatch(input.KeyCode, false, false)
		dispatch(input.UserInputType, false, false)
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			frameDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		end
	end)

	UserInputService.WindowFocusReleased:Connect(Input.releaseAll)

	ContextActionService:BindAction("SableJump", function(_, state)
		if state == Enum.UserInputState.Begin then
			if not Input.State.Jump then
				Input.State.Jump = true
				Input.Pressed:Fire("Jump")
			end
		elseif state == Enum.UserInputState.End then
			if Input.State.Jump then
				Input.State.Jump = false
				Input.Released:Fire("Jump")
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.PlayerActions.CharacterJump)
end

return Input
