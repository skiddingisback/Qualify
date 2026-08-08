local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local ACOUSTIC_RATE = 1 / 14
local OCCLUSION_RANGE = 240
local MUFFLE_DISTANCE = 0.72
local MUFFLE_BLOCKED = 0.55

local SoundKit = {}

local function ensureGroup(name)
	local group = SoundService:FindFirstChild(name)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = SoundService
	end
	return group
end

SoundKit.Groups = {
	Weapons = ensureGroup("SableWeapons"),
	World = ensureGroup("SableWorld"),
	Interface = ensureGroup("SableInterface"),
}

local monitored = {}
local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Exclude
occlusionParams.IgnoreWater = true

local function sourcePosition(sound)
	local parent = sound.Parent
	if not parent then
		return nil
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function equalizerFor(sound)
	local effect = sound:FindFirstChild("SableAcoustics")
	if not effect then
		effect = Instance.new("EqualizerSoundEffect")
		effect.Name = "SableAcoustics"
		effect.Priority = 20
		effect.Parent = sound
	end
	return effect
end

function SoundKit.setListenerFilter(instances)
	occlusionParams.FilterDescendantsInstances = instances
end

function SoundKit.monitor(sound)
	if not sound or monitored[sound] or not sourcePosition(sound) then
		return
	end
	monitored[sound] = { Equalizer = equalizerFor(sound), Blocked = 0, Probe = 0 }
end

local function refreshAcoustics()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local listener = camera.CFrame.Position
	local now = os.clock()

	for sound, entry in pairs(monitored) do
		local source = sound.Parent and sourcePosition(sound)
		if not source or not sound.IsPlaying then
			monitored[sound] = nil
			continue
		end

		local distance = (source - listener).Magnitude
		local reach = math.max(sound.RollOffMaxDistance, 1)
		local far = math.clamp(distance / reach, 0, 1)

		if distance < OCCLUSION_RANGE and now - entry.Probe > 0.2 then
			entry.Probe = now
			local hit = workspace:Raycast(listener, source - listener, occlusionParams)
			entry.Blocked = (hit and (hit.Position - source).Magnitude > 3) and 1 or 0
		end

		local muffle = math.clamp(far * MUFFLE_DISTANCE + entry.Blocked * MUFFLE_BLOCKED, 0, 1)
		local equalizer = entry.Equalizer
		equalizer.HighGain = -78 * muffle
		equalizer.MidGain = -30 * muffle
		equalizer.LowGain = -2 * far
	end
end

if RunService:IsClient() then
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < ACOUSTIC_RATE then
			return
		end
		accumulator = 0
		refreshAcoustics()
	end)
end

function SoundKit.detachedPlay(template, pitchJitter, volumeScale)
	if not template or not template:IsA("Sound") then
		return nil
	end

	local clone = template:Clone()
	clone.Name = template.Name .. "_x"
	clone.SoundGroup = template.SoundGroup or SoundKit.Groups.Weapons

	if pitchJitter and pitchJitter > 0 then
		clone.PlaybackSpeed = template.PlaybackSpeed * (1 + (math.random() * 2 - 1) * pitchJitter)
	end
	if volumeScale then
		clone.Volume = template.Volume * volumeScale
	end

	clone.Parent = template.Parent
	clone:Play()
	SoundKit.monitor(clone)
	Debris:AddItem(clone, math.max(clone.TimeLength / math.max(clone.PlaybackSpeed, 0.05), 1) + 0.5)
	return clone
end

function SoundKit.playFrom(container, name, options)
	if not container then
		return nil
	end
	local template = container:FindFirstChild(name, true)
	if not template then
		return nil
	end
	options = options or {}
	return SoundKit.detachedPlay(template, options.Jitter or 0.03, options.Volume)
end

function SoundKit.pick(container, prefix, count, options)
	local index = math.random(1, count)
	return SoundKit.playFrom(container, prefix .. index, options)
end

local emitterPool = {}

local function acquireEmitter()
	local emitter = table.remove(emitterPool)
	if emitter and emitter.Parent == nil then
		return emitter
	end

	emitter = Instance.new("Part")
	emitter.Name = "SableEmitter"
	emitter.Size = Vector3.one * 0.1
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	return emitter
end

function SoundKit.spatial(soundId, position, options)
	if not soundId or soundId == "" then
		return nil
	end
	options = options or {}

	local emitter = acquireEmitter()
	emitter.CFrame = CFrame.new(position)
	emitter.Parent = workspace.Terrain

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = options.Volume or 0.6
	sound.RollOffMinDistance = options.MinDistance or 6
	sound.RollOffMaxDistance = options.MaxDistance or 140
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.PlaybackSpeed = (options.Pitch or 1) * (1 + (math.random() * 2 - 1) * (options.Jitter or 0.06))
	sound.SoundGroup = options.Group or SoundKit.Groups.World
	sound.EmitterSize = options.EmitterSize or sound.EmitterSize

	if options.Distortion and options.Distortion > 0 then
		local distortion = Instance.new("DistortionSoundEffect")
		distortion.Level = options.Distortion
		distortion.Parent = sound
	end

	sound.Parent = emitter
	sound:Play()
	SoundKit.monitor(sound)

	task.delay(options.Life or 3, function()
		sound:Destroy()
		emitter.Parent = nil
		if #emitterPool < 24 then
			table.insert(emitterPool, emitter)
		else
			emitter:Destroy()
		end
	end)

	return sound
end

function SoundKit.attached(soundId, parent, options)
	if not soundId or soundId == "" or not parent then
		return nil
	end
	options = options or {}

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = options.Volume or 0.5
	sound.RollOffMinDistance = options.MinDistance or 4
	sound.RollOffMaxDistance = options.MaxDistance or 90
	sound.PlaybackSpeed = (options.Pitch or 1) * (1 + (math.random() * 2 - 1) * (options.Jitter or 0.05))
	sound.SoundGroup = options.Group or SoundKit.Groups.World
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, options.Life or 4)
	return sound
end

function SoundKit.ui(soundId, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.4
	sound.SoundGroup = SoundKit.Groups.Interface
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
	return sound
end

return SoundKit
