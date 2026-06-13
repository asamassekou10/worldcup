--!strict
-- Warmup: the client-side "Free Kicks" target-practice mini-game. Walk to the
-- practice ball + press E -> a reticle sweeps the goal; tap SHOOT to fire at it.
-- Hit the lit targets for points; the server grants capped coins/XP at the end.
-- Self-contained (own HUD + camera) so it never touches the match systems.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WarmupData = require(Shared:WaitForChild("Warmup"))
local Venue = require(script.Parent:WaitForChild("Venue"))
local Sound = require(script.Parent:WaitForChild("Sound"))

local Warmup = {}

local player = Players.LocalPlayer
local rewardEvent = Net.getEvent(Net.Events.WarmupReward)

local active = false
local shotsLeft = 0
local score = 0
local canShoot = false
local aimX, aimY = 0, 0.5
local sweepConn: RBXScriptConnection? = nil
local startClock = 0

-- ===== world bits (built once) =====

local reticlePart = Instance.new("Part")
reticlePart.Name = "WarmupReticle"
reticlePart.Anchored = true
reticlePart.CanCollide = false
reticlePart.CanQuery = false
reticlePart.Transparency = 1
reticlePart.Size = Vector3.new(0.2, 0.2, 0.2)
reticlePart.Parent = Workspace
local reticleGui = Instance.new("BillboardGui")
reticleGui.Size = UDim2.fromOffset(46, 46)
reticleGui.AlwaysOnTop = true
reticleGui.Enabled = false
reticleGui.Adornee = reticlePart
reticleGui.Parent = reticlePart
local reticleRing = Instance.new("Frame")
reticleRing.Size = UDim2.fromScale(1, 1)
reticleRing.BackgroundTransparency = 1
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = reticleRing
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = Color3.fromRGB(60, 220, 110)
ringStroke.Thickness = 3
ringStroke.Parent = reticleRing
reticleRing.Parent = reticleGui

local flightBall = Instance.new("Part")
flightBall.Name = "WarmupFlightBall"
flightBall.Shape = Enum.PartType.Ball
flightBall.Anchored = true
flightBall.CanCollide = false
flightBall.CanQuery = false
flightBall.Size = Vector3.new(1.6, 1.6, 1.6)
flightBall.Color = Color3.fromRGB(245, 245, 245)
flightBall.Transparency = 1
flightBall.Parent = Workspace

local function burst(at: Vector3, color: Color3)
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.Transparency = 1
	fx.Size = Vector3.one
	fx.CFrame = CFrame.new(at)
	fx.Parent = Workspace
	local att = Instance.new("Attachment")
	att.Parent = fx
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Size = NumberSequence.new(0.5)
	emitter.Rate = 0
	emitter.Parent = att
	emitter:Emit(28)
	Debris:AddItem(fx, 1.5)
end

-- ===== HUD (own ScreenGui) =====

local screen = Instance.new("ScreenGui")
screen.Name = "WarmupHud"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Enabled = false
screen.Parent = player:WaitForChild("PlayerGui")

local title = Instance.new("TextLabel")
title.Size = UDim2.fromScale(0.4, 0.06)
title.Position = UDim2.fromScale(0.3, 0.04)
title.BackgroundTransparency = 0.3
title.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 220, 90)
title.Text = "🎯 FREE KICKS"
local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = title
title.Parent = screen

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.fromScale(0.4, 0.05)
statusLabel.Position = UDim2.fromScale(0.3, 0.11)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextScaled = true
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextStrokeTransparency = 0.5
statusLabel.Text = ""
statusLabel.Parent = screen

local shootButton = Instance.new("TextButton")
shootButton.Size = UDim2.fromScale(0.24, 0.12)
shootButton.Position = UDim2.fromScale(0.38, 0.82)
shootButton.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
shootButton.Font = Enum.Font.GothamBlack
shootButton.TextScaled = true
shootButton.TextColor3 = Color3.fromRGB(255, 255, 255)
shootButton.Text = "SHOOT"
local shootCorner = Instance.new("UICorner")
shootCorner.CornerRadius = UDim.new(0, 12)
shootCorner.Parent = shootButton
shootButton.Parent = screen

local quitButton = Instance.new("TextButton")
quitButton.Size = UDim2.fromScale(0.1, 0.06)
quitButton.Position = UDim2.fromScale(0.88, 0.04)
quitButton.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
quitButton.Font = Enum.Font.GothamBlack
quitButton.TextScaled = true
quitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
quitButton.Text = "✕"
local quitCorner = Instance.new("UICorner")
quitCorner.CornerRadius = UDim.new(0, 10)
quitCorner.Parent = quitButton
quitButton.Parent = screen

local function updateStatus()
	statusLabel.Text = string.format("Shots left: %d   ·   Score: %d", shotsLeft, score)
end

-- ===== session =====

local function setCamera(scriptable: boolean)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	if scriptable then
		local cf = Venue.practiceCameraCFrame()
		if cf then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = cf
		end
	else
		cam.CameraType = Enum.CameraType.Custom
	end
end

local function endSession()
	if not active then
		return
	end
	active = false
	if sweepConn then
		sweepConn:Disconnect()
		sweepConn = nil
	end
	reticleGui.Enabled = false
	flightBall.Transparency = 1
	screen.Enabled = false
	setCamera(false)
	if score > 0 then
		rewardEvent:FireServer({ score = score })
	end
end

local function fireShot()
	if not active or not canShoot then
		return
	end
	canShoot = false
	local shotX, shotY = aimX, aimY
	local target = Venue.practicePointWorld(shotX, shotY)
	local spot = Venue.practiceSpot()
	if not target or not spot then
		canShoot = true
		return
	end
	Sound.play("Kick")
	local start = spot + Vector3.new(0, 1, 0)
	flightBall.Transparency = 0
	flightBall.Position = start
	local elapsed = 0
	local flightTime = 0.42
	local arc = 2.5
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local t = math.clamp(elapsed / flightTime, 0, 1)
		flightBall.Position = start:Lerp(target, t) + Vector3.new(0, 4 * arc * t * (1 - t), 0)
		if t >= 1 then
			conn:Disconnect()
			local points = WarmupData.scoreShot(shotX, shotY)
			if points > 0 then
				score += points
				burst(target, Color3.fromRGB(60, 220, 110))
				Sound.play("Goal")
			else
				burst(target, Color3.fromRGB(170, 180, 200))
			end
			shotsLeft -= 1
			updateStatus()
			flightBall.Transparency = 1
			if shotsLeft <= 0 then
				task.delay(0.6, endSession)
			else
				canShoot = true
			end
		end
	end)
end

local function startSession()
	if active then
		return
	end
	active = true
	shotsLeft = WarmupData.Shots
	score = 0
	canShoot = true
	startClock = os.clock()
	updateStatus()
	screen.Enabled = true
	reticleGui.Enabled = true
	setCamera(true)

	sweepConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startClock
		aimX = 0.85 * math.sin(t * 1.7)
		aimY = 0.52 + 0.34 * math.sin(t * 2.4 + 1)
		local p = Venue.practicePointWorld(aimX, aimY)
		if p then
			reticlePart.Position = p
		end
	end)
end

shootButton.Activated:Connect(fireShot)
quitButton.Activated:Connect(endSession)

function Warmup.cancel()
	endSession()
end

function Warmup.start()
	ProximityPromptService.PromptTriggered:Connect(
		function(prompt: ProximityPrompt, triggerer: Player)
			if triggerer == player and prompt.Name == "WarmupPrompt" then
				startSession()
			end
		end
	)
end

return Warmup
