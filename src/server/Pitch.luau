--!strict
-- Pitch: server-side venue positioning, derived from the stadium's `Ball` and
-- `Keeper` markers. Places real player avatars on the pitch -- the current
-- shooter steps up to the penalty spot, everyone else lines up on a bench -- and
-- spawns the pre-game lobby. The server owns this so all clients see the same
-- thing. (The ball + decorative keeper are still animated client-side.)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MapLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapLayout"))

local Pitch = {}

-- Character animations (loaded once; played on the relevant action). "" skipped.
local function loadAnim(id: string): Animation?
	if id == "" then
		return nil
	end
	local a = Instance.new("Animation")
	a.AnimationId = id
	return a
end
local kickAnim = loadAnim(Config.Animations.Kick)
local diveAnim = loadAnim(Config.Animations.Dive)

local function playAnim(player: Player, anim: Animation?)
	if not anim then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim :: Animation)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.05)
	end
end

local function toPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart
			or (inst:FindFirstChild("HumanoidRootPart") :: BasePart?)
			or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function findPart(name: string): BasePart?
	local inst = workspace:FindFirstChild(name, true)
	return if inst then toPart(inst) else nil
end

type Geo = { ball: Vector3, goal: Vector3, dir: Vector3, right: Vector3, standY: number }

-- Direction from the ball to the goal, a horizontal "right", and the height
-- avatars stand at (taken from the keeper marker, which is on the pitch).
local function geo(): Geo?
	local ball, keeper = findPart("Ball"), findPart("Keeper")
	if not ball or not keeper then
		return nil
	end
	local flat =
		Vector3.new(keeper.Position.X - ball.Position.X, 0, keeper.Position.Z - ball.Position.Z)
	if flat.Magnitude < 0.1 then
		return nil
	end
	local dir = flat.Unit
	return {
		ball = ball.Position,
		goal = keeper.Position,
		dir = dir,
		right = dir:Cross(Vector3.yAxis),
		standY = keeper.Position.Y,
	}
end

-- Penalty spot (just behind the ball, facing the goal).
function Pitch.spotCFrame(): CFrame?
	local g = geo()
	if not g then
		return nil
	end
	local pos = Vector3.new(g.ball.X, g.standY, g.ball.Z) - g.dir * 3
	return CFrame.lookAt(pos, pos + g.dir)
end

-- Fallback midfield distance (studs from the penalty spot) used ONLY until you
-- place a part named "Center" at the halfway line, after which everything scales
-- to your real pitch automatically.
Pitch.MidfieldBack = 30

-- The halfway point of the field: the "Center" marker if present, else a fallback
-- estimate behind the spot. Players gather here so the whole pitch is the lobby.
function Pitch.midfield(): Vector3?
	local g = geo()
	if not g then
		return nil
	end
	local center = findPart("Center")
	if center then
		return Vector3.new(center.Position.X, g.standY, center.Position.Z)
	end
	return Vector3.new(g.ball.X, g.standY, g.ball.Z) - g.dir * Pitch.MidfieldBack
end

-- Where waiting players gather: just in front of the midfield centre (so they
-- don't spawn inside a centre-circle model), facing the goal.
function Pitch.lobbyCFrame(): CFrame?
	-- Spawn in the plaza (MapLayout's single source of truth), grounded on the apron
	-- with the HRP raised so players stand cleanly instead of sinking.
	local cf = MapLayout.plaza("spawn")
	if cf then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local excludes: { Instance } = {}
		for _, n in { "WarmupRange", "HubProps", "WorldCupDecor", "LobbySpawn" } do
			local f = workspace:FindFirstChild(n)
			if f then
				table.insert(excludes, f)
			end
		end
		params.FilterDescendantsInstances = excludes
		local hit = workspace:Raycast(cf.Position + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), params)
		local groundY = if hit then hit.Position.Y else cf.Position.Y
		return CFrame.new(Vector3.new(cf.Position.X, groundY + 3.5, cf.Position.Z)) * cf.Rotation
	end

	-- Fallback: the old midfield gather point.
	local g = geo()
	local mid = Pitch.midfield()
	if not g or not mid then
		return nil
	end
	local pos = mid + g.dir * 8
	return CFrame.lookAt(pos, pos + g.dir)
end

-- The keeper stands on the goal line (just in front of it), facing the shooter.
function Pitch.keeperLineCFrame(): CFrame?
	local g = geo()
	if not g then
		return nil
	end
	local pos = Vector3.new(g.goal.X, g.standY, g.goal.Z) - g.dir * 1.5
	return CFrame.lookAt(pos, pos - g.dir) -- look back toward the ball/shooter
end

-- Spectators wait off to the side, beyond the ad boards and out of the camera's
-- shot, so they never block the goal. Alternates sides, stepping back in ranks.
local function sidelineCFrame(index: number): CFrame?
	local g = geo()
	if not g then
		return nil
	end
	local side = if index % 2 == 0 then 1 else -1
	local rank = math.floor((index - 1) / 2)
	local pos = Vector3.new(g.ball.X, g.standY, g.ball.Z)
		+ g.right * (side * 24)
		- g.dir * (4 + rank * 4)
	return CFrame.lookAt(pos, pos - g.right * side) -- face in toward the pitch
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function anchorAt(player: Player, cframe: CFrame?)
	local root = rootOf(player)
	if root and cframe then
		root.CFrame = cframe
		root.Anchored = true
	end
end

-- Stage the turn: shooter at the spot, keeper on the line, everyone else off to
-- the sideline (out of frame).
function Pitch.positionPlayers(players: { Player }, shooter: Player, keeper: Player)
	local specIndex = 0
	for _, player in players do
		if player.Parent == Players then
			if player == shooter then
				anchorAt(player, Pitch.spotCFrame())
			elseif player == keeper then
				anchorAt(player, Pitch.keeperLineCFrame())
			else
				specIndex += 1
				anchorAt(player, sidelineCFrame(specIndex))
			end
		end
	end
end

-- The keeper throws a full diving save toward their guess as the ball is struck
-- (server-side so every client sees the same attempt). The body lunges sideways
-- AND rolls horizontal into the dive, then recovers to its stance. `guessX` is
-- in goal space (-1 = their left post, +1 = their right), matched to the shot.
function Pitch.keeperDive(player: Player, guessX: number)
	local g = geo()
	local root = rootOf(player)
	if not g or not root then
		return
	end
	-- Right vector of the goal frame (same basis the shot aims in).
	local lookVec = Vector3.new(g.ball.X - g.goal.X, 0, g.ball.Z - g.goal.Z).Unit
	local rightWorld = lookVec:Cross(Vector3.yAxis)
	local home = root.CFrame
	local x = math.clamp(guessX, -1, 1)

	playAnim(player, diveAnim) -- real diving animation if one is configured

	-- A centre guess is just a small ready-step; a corner guess is a full dive
	-- that rolls the body horizontal toward that post. If a real dive clip is set,
	-- let the animation pose the body and only lunge sideways (no manual roll).
	local reach = x * 4.5
	local lift = 1 + math.abs(x) * 1.6
	local roll = if diveAnim then CFrame.identity else CFrame.Angles(0, 0, math.rad(-78) * x)
	local target = CFrame.new(home.Position + rightWorld * reach + Vector3.new(0, lift, 0))
		* home.Rotation
		* roll

	TweenService
		:Create(root, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = target,
		})
		:Play()
	task.delay(0.95, function()
		if root.Parent then
			TweenService:Create(root, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = home })
				:Play()
		end
	end)
end

-- Force a (re)spawned character to the lobby, overriding whatever spawn Roblox
-- picked (the stadium's own spawn, or the origin).
function Pitch.placeAtLobby(player: Player)
	local lobby = Pitch.lobbyCFrame()
	local root = rootOf(player)
	if lobby and root then
		root.CFrame = lobby
	end
end

-- Unanchor and send everyone back to the lobby.
function Pitch.releasePlayers(players: { Player })
	local lobby = Pitch.lobbyCFrame()
	for _, player in players do
		local root = rootOf(player)
		if root then
			root.Anchored = false
			if lobby then
				root.CFrame = lobby
			end
		end
	end
end

-- The shooter plants and strikes as the ball launches: a quick lunge into the
-- ball with a forward lean, then recover (server-side so all clients see it).
function Pitch.kickShooter(player: Player)
	local g = geo()
	local root = rootOf(player)
	if not g or not root then
		return
	end
	playAnim(player, kickAnim) -- real striking animation (limbs), on top of the step-in
	local home = root.CFrame
	local strike = CFrame.new(home.Position + g.dir * 1.6)
		* home.Rotation
		* CFrame.Angles(math.rad(-14), 0, 0) -- a smaller lean now the anim does the kick
	TweenService
		:Create(root, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = strike,
		})
		:Play()
	task.delay(0.14, function()
		if root.Parent then
			TweenService:Create(root, TweenInfo.new(0.28, Enum.EasingStyle.Quad), { CFrame = home })
				:Play()
		end
	end)
end

-- A spawn at the lobby gathering point so players appear together on the pitch.
function Pitch.setupLobby()
	if workspace:FindFirstChild("LobbySpawn") then
		return
	end
	local lobby = Pitch.lobbyCFrame() or CFrame.new(0, 5, 0)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(18, 1, 18)
	spawn.Transparency = 1
	spawn.CanCollide = false -- not a wall; players stand on the real pitch
	spawn.CFrame = lobby * CFrame.new(0, -2.5, 0) -- pad near foot level
	spawn.Parent = workspace
end

return Pitch
