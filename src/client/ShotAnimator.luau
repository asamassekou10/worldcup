--!strict
-- ShotAnimator: plays the cosmetic animation for the authoritative result -- the
-- ball flies to the exact (x,y) it was scored at, the keeper DIVES toward their
-- guess, with juice (ball trail, impact burst, slow-mo saves, goal fireworks).
-- Purely visual; the outcome is never computed here.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Sound = require(script.Parent:WaitForChild("Sound"))
local Venue = require(script.Parent:WaitForChild("Venue"))
local Camera = require(script.Parent:WaitForChild("Camera"))

local ShotAnimator = {}

-- ===== move a Model (PivotTo) or Part (CFrame) generically =====

type Mover = { get: () -> CFrame, set: (CFrame) -> () }

local function moverFor(inst: Instance?): Mover?
	if inst and inst:IsA("Model") then
		local model = inst
		return {
			get = function()
				return model:GetPivot()
			end,
			set = function(cf)
				model:PivotTo(cf)
			end,
		}
	elseif inst and inst:IsA("BasePart") then
		local part = inst
		return {
			get = function()
				return part.CFrame
			end,
			set = function(cf)
				part.CFrame = cf
			end,
		}
	end
	return nil
end

local function tweenMover(mover: Mover, target: CFrame, info: TweenInfo): Tween
	local cv = Instance.new("CFrameValue")
	cv.Value = mover.get()
	local conn = cv:GetPropertyChangedSignal("Value"):Connect(function()
		mover.set(cv.Value)
	end)
	local tween = TweenService:Create(cv, info, { Value = target })
	tween:Play()
	tween.Completed:Connect(function()
		conn:Disconnect()
		cv:Destroy()
	end)
	return tween
end

-- ===== resting poses (captured once) =====

local ballHome: CFrame? = nil
local shooterHome: CFrame? = nil

local RETURN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local KICK_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- A motion trail on the ball (added once; shows automatically when it moves).
local function ensureTrail(ball: BasePart)
	if ball:FindFirstChild("ShotTrail") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA0"
	a0.Position = Vector3.new(0, 0.4, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailA1"
	a1.Position = Vector3.new(0, -0.4, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Name = "ShotTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.MinLength = 0.2
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	trail.Parent = ball
end

local function burst(at: Vector3, color: Color3, count: number, lightEmission: number)
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.Transparency = 1
	fx.Size = Vector3.one
	fx.CFrame = CFrame.new(at)
	fx.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = fx
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.5, 1.0)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Size = NumberSequence.new(0.5)
	emitter.Rate = 0
	emitter.LightEmission = lightEmission
	emitter.Parent = att
	emitter:Emit(count)
	Debris:AddItem(fx, 2)
end

-- A quick white screen flash for impact emphasis (a light hit-stop substitute).
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "PenaltyKingsFlash"
flashGui.IgnoreGuiInset = true
flashGui.DisplayOrder = 5
flashGui.ResetOnSpawn = false
flashGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
flashFrame.BackgroundTransparency = 1
flashFrame.Parent = flashGui

-- Hit-stop: a sharp white freeze-frame HELD at contact, then released -- the
-- single biggest "weighty impact" trick. `hold` is how long the freeze lasts
-- before the flash eases out and the celebration bursts.
local function hitStop(strength: number, hold: number)
	flashFrame.BackgroundTransparency = 1 - strength
	task.delay(hold, function()
		TweenService:Create(flashFrame, TweenInfo.new(0.24, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1,
		}):Play()
	end)
end

-- An expanding neon shockwave sphere at the point of impact.
local function shockwave(at: Vector3, color: Color3, finalSize: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.one
	p.Transparency = 0.25
	p.CFrame = CFrame.new(at)
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(finalSize, finalSize, finalSize),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.5)
end

local function goalFlash(at: Vector3)
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.Transparency = 1
	fx.Size = Vector3.one
	fx.CFrame = CFrame.new(at)
	fx.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 245, 210)
	light.Brightness = 9
	light.Range = 34
	light.Parent = fx
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	Debris:AddItem(fx, 0.7)
end

local function animateShooter()
	local mover = moverFor(Venue.instance("Shooter"))
	local ball = Venue.ball()
	if not mover or not ball then
		return
	end
	shooterHome = shooterHome or mover.get()
	local home = shooterHome :: CFrame
	local toBall = ball.Position - home.Position
	toBall = Vector3.new(toBall.X, 0, toBall.Z)
	local dir = if toBall.Magnitude > 0.1 then toBall.Unit else home.LookVector
	local kick = tweenMover(mover, home + dir * 2.5, KICK_OUT)
	kick.Completed:Connect(function()
		tweenMover(mover, home, RETURN)
	end)
end

-- One live flight at a time -- cancel any previous so rapid turns don't fight.
local flightConn: RBXScriptConnection? = nil

-- A quick stadium-wide brightness pop on a goal (the lights "flash").
local function stadiumPulse()
	local base = Lighting.ExposureCompensation
	local up =
		TweenService:Create(Lighting, TweenInfo.new(0.12), { ExposureCompensation = base + 0.35 })
	up.Completed:Connect(function()
		TweenService:Create(Lighting, TweenInfo.new(0.5), { ExposureCompensation = base }):Play()
	end)
	up:Play()
end

-- Runs in its own thread (spawned) so the hit-stop can hold a real beat before the
-- celebration. The ball is already parked at the impact point during the freeze.
local function onArrive(result: Types.RoundResultInfo, target: Vector3)
	if result.outcome == "Goal" then
		-- 1) Freeze on contact (held white frame + a sharp jolt).
		hitStop(0.7, 0.075)
		Camera.shake(0.32)
		task.wait(0.075) -- the hit-stop beat
		-- 2) Release into the celebration.
		Sound.play("Horn")
		local goalTop = (Venue.goalPointWorld(0, 1) or target) + Vector3.new(0, 1, 0)
		burst(goalTop, Color3.fromRGB(255, 230, 120), 130, 0.4)
		goalFlash(goalTop)
		shockwave(target, Color3.fromRGB(255, 220, 120), 18) -- net-impact ring
		stadiumPulse()
		Camera.shake(0.5) -- big jolt on a goal...
		Camera.fovPunch(12)
		Camera.goalCam(1.9) -- ...and cut to the replay angle
	elseif result.outcome == "Save" then
		-- The keeper's hero beat: a sharp freeze on the parry, then cut to a low save-cam
		-- so the full-stretch stop reads as big as a goal.
		hitStop(0.5, 0.06)
		Camera.shake(0.34)
		task.wait(0.06)
		Sound.play("Save")
		burst(target, Color3.fromRGB(230, 240, 255), 80, 0.25) -- puff where it's parried
		shockwave(target, Color3.fromRGB(150, 200, 255), 13)
		goalFlash(target) -- a bright pop on the parry point
		Camera.shake(0.42)
		Camera.fovPunch(9)
		Camera.saveCam(1.7, result.keeperX) -- cut to the diving-save replay angle
	end
end

function ShotAnimator.play(result: Types.RoundResultInfo)
	local ball = Venue.ball()
	local target = Venue.goalPointWorld(result.shotX, result.shotY)
	if not ball or not target then
		return -- markers not set up yet
	end
	ensureTrail(ball)
	ballHome = ballHome or ball.CFrame
	local homeBall = ballHome :: CFrame
	local start = ball.Position

	Sound.play("Kick")
	animateShooter()
	Camera.shake(0.22) -- a little kick of shake as the ball is struck
	Camera.fovPunch(5)

	-- Curved flight: a parabola from the spot to the goal point, with the ball
	-- spinning about a side axis (topspin) for a struck-ball feel. A save plays
	-- a touch slower so the parry reads (mini slow-mo).
	local flightTime = if result.outcome == "Save" then 0.6 else 0.42
	local travel = target - start
	local flat = Vector3.new(travel.X, 0, travel.Z)
	local sideAxis = if flat.Magnitude > 0.1 then flat.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	local arc = math.clamp(travel.Magnitude * 0.14, 1.5, 5) -- higher arc on longer shots
	local bend = result.curve * 5 -- studs the path bows sideways at mid-flight

	if flightConn then
		flightConn:Disconnect()
	end
	local elapsed = 0
	local fired = false
	flightConn = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local t = math.clamp(elapsed / flightTime, 0, 1)
		local bow = 4 * t * (1 - t) -- 0 at the ends, 1 at mid-flight
		local pos = start:Lerp(target, t) + Vector3.new(0, arc * bow, 0) + sideAxis * (bend * bow)
		ball.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(sideAxis, t * math.pi * 7)
		if t >= 1 and not fired then
			fired = true
			if flightConn then
				flightConn:Disconnect()
				flightConn = nil
			end
			task.spawn(onArrive, result, target) -- hit-stop yields; keep the loop clean
			task.delay(0.9, function()
				TweenService:Create(ball, TweenInfo.new(0.3), { CFrame = homeBall }):Play()
			end)
		end
	end)
end

return ShotAnimator
