--!strict
-- WarmupService: builds the "Free Kicks" target-practice goal beside the pitch
-- (anchored to the Ball/Keeper markers) and grants capped rewards when a client
-- reports a finished session. The mini-game runs client-side; the server owns
-- the geometry + the (rate-limited, clamped) payout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Warmup = require(Shared:WaitForChild("Warmup"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local WarmupService = {}

local lastReward: { [Player]: number } = {}

local function findPart(name: string): BasePart?
	local inst = workspace:FindFirstChild(name, true)
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

-- Build ONE practice station (goal + targets + ball/prompt/sign) at `frame0`.
-- When `usesRealGoal` is true the stadium's own goal is the backdrop, so posts are
-- skipped and only the targets are placed in its mouth.
local function buildStation(folder: Folder, frame0: CFrame, usesRealGoal: boolean)
	-- Drop the station's base onto the real turf (no floating).
	local fp = frame0.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(fp + Vector3.new(0, 60, 0), Vector3.new(0, -300, 0), params)
	local gy = if hit then hit.Position.Y else fp.Y
	local frame = CFrame.new(Vector3.new(fp.X, gy, fp.Z)) * frame0.Rotation

	local W, H = Config.Goal.Width, Config.Goal.Height
	local half = W / 2
	local function pointWorld(x: number, y: number): Vector3
		return frame.Position + frame.RightVector * (x * half) + Vector3.new(0, y * H, 0)
	end

	-- Goal frame + net (skipped at the real far goal -- it's the backdrop). A mesh
	-- model if one is configured + loads, else built posts + net backing.
	if not usesRealGoal then
		local meshGoal = Assets.place(
			folder,
			Config.Models.Goal,
			CFrame.new(pointWorld(0, 0)) * frame.Rotation,
			H
		)
		if not meshGoal then
			local POST = Color3.fromRGB(245, 248, 252)
			part(folder, Vector3.new(W + 1, 0.6, 0.6), CFrame.new(pointWorld(0, 1)) * frame.Rotation, POST, Enum.Material.SmoothPlastic)
			part(folder, Vector3.new(0.6, H, 0.6), CFrame.new(pointWorld(-1, 0.5)) * frame.Rotation, POST, Enum.Material.SmoothPlastic)
			part(folder, Vector3.new(0.6, H, 0.6), CFrame.new(pointWorld(1, 0.5)) * frame.Rotation, POST, Enum.Material.SmoothPlastic)
			local net = part(folder, Vector3.new(W, H, 0.3), CFrame.new(pointWorld(0, 0.5) + frame.LookVector * -1.2) * frame.Rotation, Color3.fromRGB(225, 230, 240), Enum.Material.ForceField)
			net.Transparency = 0.5
		end
	end

	-- Target panels (neon discs) in the goal mouth.
	for _, t in Warmup.Targets do
		local disc = part(folder, Vector3.new(t.r * 2, t.r * 2, 0.3), CFrame.new(pointWorld(t.x, t.y)) * frame.Rotation, Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
		disc.Shape = Enum.PartType.Cylinder
		-- Cylinder's length is along X; rotate so the flat face points out of the goal.
		disc.CFrame = CFrame.new(pointWorld(t.x, t.y)) * frame.Rotation * CFrame.Angles(0, math.rad(90), 0)
		disc.Name = "Target"
	end

	-- A ball on a spot in front of the goal, carrying the start prompt.
	local spot = frame.Position + frame.LookVector * Config.Goal.PenaltySpotDistance
	local groundY = frame.Position.Y -- the grounded practice-goal surface
	local pedestalBall = part(folder, Vector3.new(1.6, 1.6, 1.6), CFrame.new(Vector3.new(spot.X, groundY + 0.8, spot.Z)), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic)
	pedestalBall.Shape = Enum.PartType.Ball
	pedestalBall.Name = "WarmupBall"

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WarmupPrompt"
	prompt.ActionText = "Free Kicks"
	prompt.ObjectText = "🎯 Target Practice"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestalBall

	-- A sign above it.
	local signBoard = part(folder, Vector3.new(1, 1, 1), CFrame.new(Vector3.new(spot.X, groundY + 5, spot.Z)), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	signBoard.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.MaxDistance = 55 -- fade with distance so it doesn't clutter the lobby
	billboard.AlwaysOnTop = false -- occlude behind geometry; never draw over the HUD
	billboard.Parent = signBoard
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.TextStrokeTransparency = 0.3
	label.Text = "🎯 FREE KICKS"
	label.Parent = billboard
end

-- Build every practice station (the primary side goal + the far goal if a FarGoal
-- marker exists), so players can warm up at either end of the pitch.
local function build()
	if not (findPart("Ball") and findPart("Keeper")) then
		return
	end
	local existing = workspace:FindFirstChild("WarmupRange")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "WarmupRange"
	folder.Parent = workspace

	for _, station in Warmup.stations() do
		buildStation(folder, station.frame, station.usesRealGoal)
	end
end

-- A client reports a finished session score; grant clamped coins/XP on cooldown.
function WarmupService.reward(player: Player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local score = tonumber((payload :: { [string]: unknown }).score)
	if not score then
		return
	end
	local now = os.clock()
	if now - (lastReward[player] or 0) < Warmup.Cooldown then
		return -- rate-limited
	end
	score = math.clamp(score, 0, Warmup.maxScore())
	if score <= 0 then
		return
	end
	lastReward[player] = now
	local coins = math.floor(score * Warmup.CoinPerPoint)
	local xp = math.floor(score * Warmup.XpPerPoint)
	DataService.grantReward(player, coins, xp)
	Net.getEvent(Net.Events.Notify):FireClient(player, {
		message = string.format("🎯 Target Practice: %d pts — +%d 💰", score, coins),
	})
end

function WarmupService.start()
	-- Build once the markers exist (retry briefly in case they load late).
	task.spawn(function()
		for _ = 1, 30 do
			if findPart("Ball") and findPart("Keeper") then
				build()
				return
			end
			task.wait(1)
		end
	end)

	Net.getEvent(Net.Events.WarmupReward).OnServerEvent:Connect(function(player, payload)
		WarmupService.reward(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastReward[player] = nil
	end)
end

return WarmupService
