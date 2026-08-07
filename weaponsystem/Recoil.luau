local Catalog = require(script.Parent.Parent.Data.Weapons)

local SEQUENCE_RESET = 0.42

local Recoil = {}
Recoil.__index = Recoil

function Recoil.new(weapon)
	return setmetatable({
		Weapon = weapon,
		ShotIndex = 0,
		Applied = Vector2.zero,
		Pending = Vector2.zero,
		_lastShot = -math.huge,
		_recovering = false,
	}, Recoil)
end

function Recoil:Fire(context)
	local weapon = self.Weapon
	local config = weapon.Recoil

	self.ShotIndex += 1
	self._lastShot = os.clock()
	self._recovering = false

	local vertical, horizontal = Catalog.recoilStep(weapon, self.ShotIndex)
	local scale = 1

	if context.Aiming then
		scale *= config.AdsScale
	end
	if context.Stance == "Crouch" then
		scale *= 0.82
	elseif context.Stance == "Prone" then
		scale *= 0.6
	end
	if context.Airborne then
		scale *= 1.45
	end
	if context.ArmInjury then
		scale *= 1 + 0.5 * context.ArmInjury
	end

	local spread = config.Jitter or 0.12
	local pitch = math.rad(vertical * scale * (1 + (math.random() * 2 - 1) * spread))
	local yaw = math.rad(horizontal * scale * (1 + (math.random() * 2 - 1) * spread * 0.5))

	self.Applied += Vector2.new(pitch, yaw)
	return pitch, yaw
end

function Recoil:Update(dt)
	local now = os.clock()
	local config = self.Weapon.Recoil

	if now - self._lastShot > SEQUENCE_RESET then
		self.ShotIndex = 0
	end

	if now - self._lastShot < config.Rise then
		return Vector2.zero
	end

	local magnitude = self.Applied.Magnitude
	if magnitude < 1e-5 then
		self.Applied = Vector2.zero
		return Vector2.zero
	end

	local alpha = math.clamp(config.Recovery * dt * 3.2, 0, 1)
	local recovered = self.Applied * alpha
	self.Applied -= recovered
	return recovered
end

function Recoil:Release()
	self._recovering = true
end

function Recoil:Reset()
	self.ShotIndex = 0
	self.Applied = Vector2.zero
	self._lastShot = -math.huge
end

function Recoil:ViewKick(context)
	local config = self.Weapon.Recoil
	local scale = config.ViewScale * (context.Aiming and config.AdsScale or 1)
	return Vector3.new(
		(math.random() * 2 - 1) * 0.035 * scale,
		0.028 * scale,
		config.Punch * scale
	)
end

return Recoil
