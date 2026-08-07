local Enums = require(script.Parent.Parent.Data.Enums)
local Tuning = require(script.Parent.Parent.Data.Tuning)
local Util = require(script.Parent.Parent.Lib.Util)

local Spread = {}
Spread.__index = Spread

function Spread.new(weapon)
	return setmetatable({
		Weapon = weapon,
		Bloom = 0,
		Value = weapon.Spread.Hip,
		_lastShot = -math.huge,
	}, Spread)
end

function Spread:Punch(count)
	local config = self.Weapon.Spread
	self.Bloom = math.min(self.Bloom + config.PerShot * (count or 1), config.Max)
	self._lastShot = os.clock()
end

function Spread:Reset()
	self.Bloom = 0
	self._lastShot = -math.huge
end

function Spread:Static(context)
	local config = self.Weapon.Spread
	local base = context.Aiming and config.Ads or config.Hip

	if context.Stance == Enums.Stance.Crouch then
		base += config.Crouch
	elseif context.Stance == Enums.Stance.Prone then
		base += config.Prone
	end

	local speed = context.Speed or 0
	if speed > 0.6 then
		local fraction = math.clamp(speed / Tuning.Speed.StandSprint, 0, 1.2)
		base += config.Move * fraction
	end

	if context.Airborne then
		base += config.Air
	end

	if context.ArmInjury then
		base += config.Hip * 0.45 * context.ArmInjury
	end

	return math.max(base, 0.02)
end

function Spread:Update(dt, context)
	local config = self.Weapon.Spread

	if os.clock() - self._lastShot > (config.RecoveryDelay or 0.08) then
		self.Bloom = math.max(self.Bloom - config.Recovery * dt, 0)
	end

	local target = math.min(self:Static(context) + self.Bloom, config.Max)
	self.Value = Util.damp(self.Value, target, 22, dt)
	return self.Value
end

function Spread:Degrees()
	return self.Value
end

function Spread:Sample(context)
	return math.min(self:Static(context) + self.Bloom, self.Weapon.Spread.Max)
end

return Spread
