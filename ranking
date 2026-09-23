-- shintichs / aigario
local Players = game:GetService("Players") 
local RunService = game:GetService("RunService") 
local TweenService = game:GetService("TweenService")

--------------------------------------------------------------------------------
-- 1. Settings
--------------------------------------------------------------------------------

local config = {
	turretCount = 4, -- number of turrets
	circleRadius = 70, -- distance from spawn
	range = 55, -- detection range
	scanDelay = 0.2, -- target scan interval
	turnSpeed = 7, -- head turn speed
	laserSpeed = 10, -- laser smoothing speed
	aimTolerance = math.rad(5), -- allowed aim error
	shotDelay = 0.45, -- delay between shots
	bulletSpeed = 110, -- projectile speed
	bulletLifetime = 3, -- projectile lifetime
	gravityScale = 0.3, -- projectile gravity scale
	damage = 10, -- damage per hit
	recoil = 0.6, -- recoil distance
	lookAroundAngle = math.rad(55), -- idle sweep angle
	lookAroundSpeed = 0.9, -- idle sweep speed
	sleepAngle = math.rad(35), -- disabled tilt
	hackHoldTime = 1.5, -- hack hold duration
	hackDistance = 10, -- hack distance
	hackDuration = 8, -- disabled duration
	hitBoxColor = Color3.fromRGB(255, 40, 40), -- hit indicator color
	pulseTime = 0.12, -- hit indicator speed
	pulseCount = 3, -- hit indicator repeats
	stateColors = {
		Idle = Color3.fromRGB(80, 255, 120), -- idle state
		Tracking = Color3.fromRGB(255, 60, 60), -- tracking state
		Disabled = Color3.fromRGB(70, 110, 255), -- disabled state
	},
}

local gravity = Vector3.new(0, -workspace.Gravity * config.gravityScale, 0) -- projectile gravity
local aimCosine = math.cos(config.aimTolerance) -- cosine of the aim tolerance

local headSize = Vector3.new(3, 2.4, 3) -- turret head size
local barrelLength = 3.5 -- barrel length
local baseHeight = 4 -- base height

local barrelOffset = CFrame.new(0, 0, -(headSize.Z + barrelLength) / 2) -- barrel position relative to the head
local barrelTipOffset = CFrame.new(0, 0, -(headSize.Z / 2 + barrelLength)) -- muzzle position
local lightOffset = CFrame.new(0, headSize.Y / 2 + 0.35, 0) -- status light offset

--------------------------------------------------------------------------------
-- 2. Helpers
--------------------------------------------------------------------------------

-- Shared part factory.
local function makePart(properties: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true -- moved by script
	part.CanCollide = false -- visual parts are non-collidable
	part.CanTouch = false -- no touch events are needed
	part.TopSurface = Enum.SurfaceType.Smooth -- smooth surfaces
	part.BottomSurface = Enum.SurfaceType.Smooth
	for name, value in properties do
		(part :: any)[name] = value -- apply supplied properties
	end
	part.Parent = parent -- parent after setup
	return part
end

local function makeFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	return folder
end

local turretFolder = makeFolder("Turrets") -- turret container
local bulletFolder = makeFolder("TurretBullets") -- projectile container

local rayParams = RaycastParams.new() -- reuse one raycast object
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { turretFolder, bulletFolder } -- ignore generated parts
rayParams.IgnoreWater = true -- water is ignored

-- Batch movement into one BulkMoveTo call.
local partsToMove: { BasePart } = {}
local placesToMove: { CFrame } = {}

local function moveLater(part: BasePart, cframe: CFrame)
	table.insert(partsToMove, part) -- keep parts and CFrames aligned
	table.insert(placesToMove, cframe)
end

local function moveEverything()
	if #partsToMove == 0 then
		return -- nothing queued
	end
	workspace:BulkMoveTo(partsToMove, placesToMove, Enum.BulkMoveMode.FireCFrameChanged) -- apply queued movement
	table.clear(partsToMove) -- reuse the arrays
	table.clear(placesToMove)
end

-- Return the target parts for a living player.
local function getAliveCharacter(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil -- player is between characters
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local body = character:FindFirstChild("HumanoidRootPart")
	if humanoid and body and humanoid.Health > 0 then
		return body :: BasePart, humanoid -- ignore dead players
	end
	return nil, nil
end

local function canSee(from: Vector3, body: BasePart): boolean
	local hit = workspace:Raycast(from, body.Position - from, rayParams)
	-- visible if the ray reaches the character
	return hit == nil or hit.Instance:IsDescendantOf(body.Parent :: Instance)
end

-- Lead the target based on horizontal velocity.
local function predictTargetPosition(from: Vector3, body: BasePart): Vector3
	local velocity = body.AssemblyLinearVelocity
	local walkVelocity = Vector3.new(velocity.X, 0, velocity.Z) -- ignore vertical movement
	local guess = body.Position
	for _ = 1, 3 do -- a few iterations are enough
		local flightTime = (guess - from).Magnitude / config.bulletSpeed
		guess = body.Position + walkVelocity * flightTime
	end
	return guess
end

-- Solve the launch velocity for the ballistic arc.
local function getShotVelocity(from: Vector3, target: Vector3): Vector3
	local flightTime = math.max((target - from).Magnitude / config.bulletSpeed, 0.05) -- avoid a zero flight time
	-- rearranged projectile motion equation
	return (target - from - 0.5 * gravity * flightTime * flightTime) / flightTime
end

-- Place a turret on the terrain below the point.
local function placeOnGround(position: Vector3, lookAt: Vector3): CFrame
	local hit = workspace:Raycast(position + Vector3.yAxis * 200, Vector3.yAxis * -400, rayParams)
	local groundY = if hit then hit.Position.Y else 0 -- fallback height
	local onGround = Vector3.new(position.X, groundY, position.Z)
	return CFrame.lookAt(onGround, Vector3.new(lookAt.X, groundY, lookAt.Z)) -- keep the base upright
end

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats" -- Roblox uses this folder for the player list
	local hacks = Instance.new("IntValue")
	hacks.Name = "Hacks"
	hacks.Parent = leaderstats
	leaderstats.Parent = player
end

local function addHackPoint(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local hacks = leaderstats and leaderstats:FindFirstChild("Hacks") :: IntValue?
	if hacks then
		hacks.Value += 1 -- player may have left
	end
end

--------------------------------------------------------------------------------
-- 3. Bullets
--------------------------------------------------------------------------------

type Bullet = {
	part: BasePart, -- visual projectile
	start: Vector3, -- launch position
	velocity: Vector3, -- launch velocity
	position: Vector3, -- current position
	age: number, -- elapsed time
}

local activeBullets: { Bullet } = {} -- active projectiles

-- Hit indicator animation.
local pulseInfo = TweenInfo.new(
	config.pulseTime, -- blink duration
	Enum.EasingStyle.Sine, -- smooth easing
	Enum.EasingDirection.InOut,
	config.pulseCount - 1, -- TweenInfo repeat count
	true -- reverse the tween
)

local hitBoxes: { [BasePart]: { box: SelectionBox, pulse: Tween } } = {} -- active hit indicators

local function showHitBox(part: BasePart)
	local hitBox = hitBoxes[part]
	if hitBox then
		hitBox.pulse:Cancel() -- restart an existing indicator
	else
		local box = Instance.new("SelectionBox") -- visible hit outline
		box.Color3 = config.hitBoxColor
		box.SurfaceColor3 = config.hitBoxColor -- light surface fill
		box.LineThickness = 0.05
		box.Adornee = part -- target part
		box.Parent = bulletFolder -- keep the indicator separate

		local pulse = TweenService:Create(box, pulseInfo, { Transparency = 0, SurfaceTransparency = 0.7 })
		pulse.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then -- only clean up completed tweens
				box:Destroy()
				hitBoxes[part] = nil -- release the reference
			end
		end)
		hitBox = { box = box, pulse = pulse }
		hitBoxes[part] = hitBox
	end
	hitBox.box.Transparency = 1 -- start hidden
	hitBox.box.SurfaceTransparency = 1
	hitBox.pulse:Play()
end

local function onBulletHit(hit: RaycastResult)
	local model = hit.Instance:FindFirstAncestorOfClass("Model") -- resolve the character model
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(config.damage) -- respect Roblox damage protection
		showHitBox(hit.Instance :: BasePart) -- show indicators only for characters
	end
end

local function shootBullet(from: Vector3, velocity: Vector3)
	local part = makePart({
		Name = "Bullet",
		Size = Vector3.new(0.3, 0.3, 1.4), -- tracer shape
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 90),
		CFrame = CFrame.lookAt(from, from + velocity), -- face the launch direction
	}, bulletFolder)
	table.insert(activeBullets, {
		part = part,
		start = from,
		velocity = velocity,
		position = from,
		age = 0,
	})
end

local function removeBullet(index: number)
	activeBullets[index].part:Destroy()
	local last = #activeBullets
	activeBullets[index] = activeBullets[last] -- O(1) removal
	activeBullets[last] = nil
end

local function updateBullets(deltaTime: number)
	for index = #activeBullets, 1, -1 do -- iterate backwards for safe removal
		local bullet = activeBullets[index]
		bullet.age += deltaTime
		local time = bullet.age
		local nextPosition = bullet.start + bullet.velocity * time + 0.5 * gravity * time * time -- ballistic position
		local step = nextPosition - bullet.position -- movement segment
		local hit = workspace:Raycast(bullet.position, step, rayParams) -- segment raycast prevents tunneling
		if hit then
			onBulletHit(hit)
			removeBullet(index)
		elseif time >= config.bulletLifetime then
			removeBullet(index) -- lifetime expired
		else
			bullet.position = nextPosition
			moveLater(bullet.part, CFrame.lookAt(nextPosition, nextPosition + step)) -- turn the bullet along its curve
		end
	end
end

--------------------------------------------------------------------------------
-- 4. Turret
--------------------------------------------------------------------------------

local Turret = {}
Turret.__index = Turret -- shared methods through the metatable

function Turret.new(groundCFrame: CFrame, number: number)
	local self = setmetatable({}, Turret)

	self.model = Instance.new("Model")
	self.model.Name = "Sentry" .. number

	local headCFrame = groundCFrame * CFrame.new(0, baseHeight + headSize.Y / 2, 0) -- head offset
	local look = groundCFrame.LookVector
	self.headPosition = headCFrame.Position -- the head only turns and never moves, so we save its position once
	self.homeAngle = math.atan2(-look.X, -look.Z) -- initial facing
	self.lookAroundOffset = number * 1.7 -- stagger idle motion
	self.aimCFrame = headCFrame -- smoothed aim
	self.nextScanTime = 0 -- first scan happens immediately
	self.nextShotTime = 0
	self.targetBody = nil :: BasePart?
	self.targetHumanoid = nil :: Humanoid?
	self.laserPoint = nil :: Vector3? -- smoothed laser target

	self.stand = makePart({
		Name = "Stand",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(baseHeight, 5, 5), -- cylinder orientation
		CFrame = groundCFrame * CFrame.new(0, baseHeight / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), -- rotate the cylinder upright
		CanCollide = true, -- solid base
		Material = Enum.Material.DiamondPlate,
		Color = Color3.fromRGB(60, 60, 66),
	}, self.model)

	self.head = makePart({
		Name = "Head",
		Size = headSize,
		CFrame = headCFrame,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(95, 95, 105),
	}, self.model)

	self.barrel = makePart({
		Name = "Barrel",
		Size = Vector3.new(0.6, 0.6, barrelLength),
		CFrame = headCFrame * barrelOffset, -- placed in front of the head
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(35, 35, 40),
	}, self.model)

	self.lamp = makePart({
		Name = "Lamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.7,
		CFrame = headCFrame * lightOffset,
		Material = Enum.Material.Neon,
	}, self.model)

	self.glow = Instance.new("PointLight") -- state light
	self.glow.Range = 12
	self.glow.Brightness = 2
	self.glow.Parent = self.lamp

	local laserStart = Instance.new("Attachment") -- beam start
	laserStart.Name = "LaserStart"
	laserStart.Position = Vector3.new(0, 0, -barrelLength / 2) -- muzzle attachment
	laserStart.Parent = self.barrel

	self.laserEnd = Instance.new("Attachment") -- beam end
	self.laserEnd.Name = "LaserEnd"
	self.laserEnd.Parent = self.stand -- attachment host

	self.laser = Instance.new("Beam") -- Beam handles the laser
	self.laser.Attachment0 = laserStart
	self.laser.Attachment1 = self.laserEnd
	self.laser.Color = ColorSequence.new(config.stateColors.Tracking)
	self.laser.Width0 = 0.12 -- beam width
	self.laser.Width1 = 0.12
	self.laser.FaceCamera = true -- keep beam visible
	self.laser.LightEmission = 1 -- emissive beam
	self.laser.Transparency = NumberSequence.new(0.2)
	self.laser.Enabled = false -- enabled by state
	self.laser.Parent = self.barrel

	self.prompt = Instance.new("ProximityPrompt") -- built-in interaction prompt
	self.prompt.ActionText = "Hack"
	self.prompt.ObjectText = "Sentry"
	self.prompt.HoldDuration = config.hackHoldTime
	self.prompt.MaxActivationDistance = config.hackDistance
	self.prompt.RequiresLineOfSight = false -- allow interaction through the head
	self.prompt.Parent = self.stand
	self.prompt.Triggered:Connect(function(player: Player)
		self:hack(player) -- prompt belongs to this turret
	end)

	self.state = nil :: string? -- force initial state setup
	self:setState("Idle")
	self.model.Parent = turretFolder -- parent after setup
	return self
end

function Turret:setState(newState: string)
	if self.state == newState then
		return -- skip unchanged states
	end
	self.state = newState
	local color = config.stateColors[newState]
	self.lamp.Color = color
	self.glow.Color = color
	self.laser.Enabled = newState == "Tracking" -- tracking beam
	self.laserPoint = nil -- reset the laser target
	self.prompt.Enabled = newState ~= "Disabled" -- disable repeated hacks
end

function Turret:getBarrelTip(): CFrame
	return self.aimCFrame * barrelTipOffset -- muzzle follows aim
end

function Turret:targetStillValid(): boolean
	local body, humanoid = self.targetBody, self.targetHumanoid
	return body ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and body:IsDescendantOf(workspace) -- target must still exist
		and (body.Position - self.headPosition).Magnitude <= config.range
end

function Turret:findClosestPlayer()
	local from = self:getBarrelTip().Position
	local closestBody, closestHumanoid, closestDistance = nil, nil, config.range -- range is also the initial best distance
	for _, player in Players:GetPlayers() do
		local body, humanoid = getAliveCharacter(player)
		if body then
			local distance = (body.Position - self.headPosition).Magnitude
			if distance < closestDistance and canSee(from, body) then -- cheap filter before raycast
				closestBody, closestHumanoid, closestDistance = body, humanoid, distance
			end
		end
	end
	self.targetBody, self.targetHumanoid = closestBody, closestHumanoid
end

-- Calculate this frame's aim and shot.
function Turret:getWantedAim(now: number): (CFrame, Vector3?)
	if self.state == "Disabled" then
		local hangDown = CFrame.Angles(-config.sleepAngle, 0, 0) -- disabled pose
		return CFrame.new(self.headPosition) * CFrame.Angles(0, self.homeAngle, 0) * hangDown, nil
	end

	if now >= self.nextScanTime then
		self.nextScanTime = now + config.scanDelay
		self:findClosestPlayer() -- a full search: can pick a closer player or lose one that hid behind a wall
	elseif not self:targetStillValid() then
		self.targetBody, self.targetHumanoid = nil, nil -- invalidate dead targets
	end

	local body = self.targetBody
	if body then
		self:setState("Tracking")
		local from = self:getBarrelTip().Position
		local target = predictTargetPosition(from, body)
		local shotVelocity = getShotVelocity(from, target)
		-- aim along the launch velocity
		return CFrame.lookAt(self.headPosition, self.headPosition + shotVelocity), shotVelocity
	end

	self:setState("Idle")
	local angle = self.homeAngle + math.sin(now * config.lookAroundSpeed + self.lookAroundOffset) * config.lookAroundAngle -- idle sweep
	return CFrame.new(self.headPosition) * CFrame.Angles(0, angle, 0), nil
end

function Turret:updateLaser(deltaTime: number)
	local body = self.targetBody :: BasePart -- this only runs while tracking, so there is always a target here
	-- keep the laser visually stable
	local smoothness = 1 - math.exp(-config.laserSpeed * deltaTime) -- frame-rate independent smoothing
	local laserPoint = if self.laserPoint then self.laserPoint:Lerp(body.Position, smoothness) else body.Position -- initialize the laser point
	self.laserPoint = laserPoint
	local from = self:getBarrelTip().Position
	local hit = workspace:Raycast(from, laserPoint - from, rayParams) -- stop the laser at obstacles
	if hit and not hit.Instance:IsDescendantOf(body.Parent :: Instance) then
		self.laserEnd.WorldPosition = hit.Position -- obstacle hit
	else
		-- let the beam reach the target
		self.laserEnd.WorldPosition = laserPoint
	end
end

function Turret:tryShoot(now: number, shotVelocity: Vector3)
	if now < self.nextShotTime then
		return -- fire cooldown
	end
	local barrelTip = self:getBarrelTip()
	if barrelTip.LookVector:Dot(shotVelocity.Unit) < aimCosine then
		return -- wait until aim is close enough
	end
	self.nextShotTime = now + config.shotDelay
	shootBullet(barrelTip.Position, shotVelocity)
	self.aimCFrame *= CFrame.new(0, 0, config.recoil) -- visual recoil
end

function Turret:update(deltaTime: number, now: number)
	local wantedAim, shotVelocity = self:getWantedAim(now)
	local smoothness = 1 - math.exp(-config.turnSpeed * deltaTime) -- frame-rate independent turning
	self.aimCFrame = self.aimCFrame:Lerp(wantedAim, smoothness) -- smooth the aim
	moveLater(self.head, self.aimCFrame)
	moveLater(self.barrel, self.aimCFrame * barrelOffset) -- keep attached parts aligned
	moveLater(self.lamp, self.aimCFrame * lightOffset) -- so they turn with it without any welds
	if shotVelocity then
		self:updateLaser(deltaTime)
		self:tryShoot(now, shotVelocity)
	end
end

function Turret:hack(player: Player)
	if self.state == "Disabled" then
		return -- guard against duplicate hacks
	end
	local body = getAliveCharacter(player)
	if not body or (body.Position - self.stand.Position).Magnitude > config.hackDistance + 4 then
		return -- server-side distance check
	end
	self.targetBody, self.targetHumanoid = nil, nil
	self:setState("Disabled")
	addHackPoint(player)
	task.delay(config.hackDuration, function()
		self.nextScanTime = 0 -- scan immediately after reboot
		self:setState("Idle")
	end)
end

--------------------------------------------------------------------------------
-- 5. Start
--------------------------------------------------------------------------------

local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
local center = if spawnLocation then spawnLocation.Position else Vector3.zero -- center the turret ring

local turrets = {}
for number = 1, config.turretCount do
	local angle = (number - 1) / config.turretCount * 2 * math.pi -- even spacing
	local offset = (CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -config.circleRadius)).Position -- rotate the ring offset
	local groundCFrame = placeOnGround(center + offset, center) -- face the arena center
	table.insert(turrets, Turret.new(groundCFrame, number))
end

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player) -- handle existing players
end

-- Single Heartbeat update loop.
RunService.Heartbeat:Connect(function(deltaTime: number)
	local now = os.clock() -- shared frame timestamp
	for _, turret in turrets do
		turret:update(deltaTime, now)
	end
	updateBullets(deltaTime)
	moveEverything()
end)
