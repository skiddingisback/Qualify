local PRIORITY = {
	Idle = Enum.AnimationPriority.Action,
	Run = Enum.AnimationPriority.Action,
	IdleToRun = Enum.AnimationPriority.Action,
	UBL_Idle = Enum.AnimationPriority.Action,
	Fire = Enum.AnimationPriority.Action2,
	AimFire = Enum.AnimationPriority.Action2,
	Pump = Enum.AnimationPriority.Action2,
	UBL_Fire = Enum.AnimationPriority.Action2,
	SlideBack = Enum.AnimationPriority.Action3,
	Reload = Enum.AnimationPriority.Action3,
	ReloadStart = Enum.AnimationPriority.Action3,
	Shell_in = Enum.AnimationPriority.Action3,
	ReloadEnd = Enum.AnimationPriority.Action3,
	FiremodeChange = Enum.AnimationPriority.Action3,
	Inspect = Enum.AnimationPriority.Action3,
	UBL_Reload = Enum.AnimationPriority.Action3,
	Equip = Enum.AnimationPriority.Action4,
	Holster = Enum.AnimationPriority.Action4,
	UBL_Enable = Enum.AnimationPriority.Action4,
	UBL_Disable = Enum.AnimationPriority.Action4,
}

local LOOPED = {
	Idle = true,
	Run = true,
	UBL_Idle = true,
}

local AnimationSet = {}
AnimationSet.__index = AnimationSet

function AnimationSet.new(animator, folder)
	local self = setmetatable({
		Animator = animator,
		Tracks = {},
		_active = {},
	}, AnimationSet)

	if folder then
		self:Load(folder)
	end
	return self
end

function AnimationSet:Load(folder)
	for _, animation in ipairs(folder:GetChildren()) do
		if animation:IsA("Animation") and animation.AnimationId ~= "" then
			local ok, track = pcall(function()
				return self.Animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = PRIORITY[animation.Name] or Enum.AnimationPriority.Action
				track.Looped = LOOPED[animation.Name] == true
				self.Tracks[animation.Name] = track
			end
		end
	end
	return self
end

function AnimationSet:Get(name)
	return name and self.Tracks[name] or nil
end

function AnimationSet:Has(name)
	return name ~= nil and self.Tracks[name] ~= nil
end

function AnimationSet:Length(name, fallback)
	local track = self:Get(name)
	if not track then
		return fallback or 0
	end
	if track.Length > 0 then
		return track.Length
	end
	return fallback or 0
end

function AnimationSet:Play(name, fade, speed, weight)
	local track = self:Get(name)
	if not track then
		return nil
	end

	track:Play(fade or 0.12, weight or 1, 1)
	if speed then
		track:AdjustSpeed(speed)
	end
	self._active[name] = true
	return track
end

function AnimationSet:PlayScaled(name, targetDuration, fade)
	local track = self:Get(name)
	if not track then
		return nil
	end

	local length = track.Length
	local speed = 1
	if length > 0 and targetDuration and targetDuration > 0 then
		speed = length / targetDuration
	end
	return self:Play(name, fade, speed)
end

function AnimationSet:RestartScaled(name, targetDuration, fade)
	local track = self:Get(name)
	if track then
		track:Stop(0)
	end
	return self:PlayScaled(name, targetDuration, fade)
end

function AnimationSet:Restart(name, fade, speed)
	local track = self:Get(name)
	if track then
		track:Stop(0)
	end
	return self:Play(name, fade, speed)
end

function AnimationSet:Stop(name, fade)
	local track = self:Get(name)
	if track then
		track:Stop(fade or 0.12)
		self._active[name] = nil
	end
end

function AnimationSet:IsPlaying(name)
	local track = self:Get(name)
	return track ~= nil and track.IsPlaying
end

function AnimationSet:StopAll(fade, except)
	for name, track in pairs(self.Tracks) do
		if name ~= except then
			track:Stop(fade or 0.1)
			self._active[name] = nil
		end
	end
end

function AnimationSet:StopGroup(names, fade)
	for _, name in ipairs(names) do
		self:Stop(name, fade)
	end
end

function AnimationSet:Destroy()
	for _, track in pairs(self.Tracks) do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(self.Tracks)
	table.clear(self._active)
end

return AnimationSet
