--!strict
-- Warmup: shared constants for the "Free Kicks" target-practice mini-game by the
-- pitch. The practice goal sits `Offset` studs to the side of the real goal;
-- targets are placed in goal-space (x in [-1,1], y in [0,1]) so the server can
-- build them and the client can hit-test them the same way. Pure data + math.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Warmup = {}

Warmup.Offset = 48 -- fallback offset (used until a "Center" marker is placed)
Warmup.Shots = 5 -- shots per session
Warmup.Cooldown = 12 -- seconds between rewarded sessions (anti-farm)
Warmup.CoinPerPoint = 0.5 -- payout
Warmup.XpPerPoint = 0.4

local function findMarker(name: string): BasePart?
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

-- True when practice runs at the real FAR goal (a "FarGoal" marker -- best -- or a
-- "Center" marker to reflect the near goal across midfield).
function Warmup.atFarGoal(): boolean
	return findMarker("FarGoal") ~= nil or findMarker("Center") ~= nil
end

-- The practice goal frame (ungrounded; callers drop it to the turf). Priority:
--   1. a "FarGoal" marker at the far goal-line centre (exact);
--   2. a "Center" marker -> reflect the near goal across midfield (approximate);
--   3. fallback: a built goal off to the side of the near goal.
-- In cases 1 & 2 the mouth faces back toward the field/shooter.
function Warmup.practiceFrame(): CFrame?
	local ball, keeper = findMarker("Ball"), findMarker("Keeper")
	if not ball or not keeper then
		return nil
	end
	local toBall =
		Vector3.new(ball.Position.X - keeper.Position.X, 0, ball.Position.Z - keeper.Position.Z)
	if toBall.Magnitude < 0.1 then
		return nil
	end
	toBall = toBall.Unit

	local farMarker = findMarker("FarGoal")
	if farMarker then
		local fp = farMarker.Position
		local toField = Vector3.new(ball.Position.X - fp.X, 0, ball.Position.Z - fp.Z)
		toField = if toField.Magnitude < 0.1 then -toBall else toField.Unit
		return CFrame.lookAt(fp, fp + toField) -- mouth faces the field/shooter
	end

	local center = findMarker("Center")
	if center then
		local cp = center.Position
		local far = Vector3.new(
			2 * cp.X - keeper.Position.X,
			keeper.Position.Y,
			2 * cp.Z - keeper.Position.Z
		)
		return CFrame.lookAt(far, far - toBall) -- mouth faces back toward midfield
	end

	return CFrame.lookAt(keeper.Position, keeper.Position + toBall)
		* CFrame.new(Warmup.Offset, 0, 0)
end

export type Target = { x: number, y: number, r: number, points: number }

-- Target panels in the goal mouth (r is a studs radius). Corners are worth more.
Warmup.Targets = {
	{ x = -0.72, y = 0.32, r = 1.9, points = 30 },
	{ x = 0.72, y = 0.32, r = 1.9, points = 30 },
	{ x = -0.66, y = 0.80, r = 1.7, points = 50 },
	{ x = 0.66, y = 0.80, r = 1.7, points = 50 },
	{ x = 0.0, y = 0.58, r = 2.2, points = 20 },
} :: { Target }

-- Goal-space (x,y) -> studs offset from the goal centre.
local function toStuds(x: number, y: number): (number, number)
	return x * (Config.Goal.Width / 2), y * Config.Goal.Height
end

-- Points for a shot landing at (x,y): the best target it's inside, else 0. Also
-- returns the index of that target (0 = miss) so the client can light it up.
function Warmup.scoreShot(x: number, y: number): (number, number)
	local bestPoints, bestIndex = 0, 0
	for i, t in Warmup.Targets do
		local sx, sy = toStuds(x - t.x, y - t.y)
		if math.sqrt(sx * sx + sy * sy) <= t.r and t.points > bestPoints then
			bestPoints, bestIndex = t.points, i
		end
	end
	return bestPoints, bestIndex
end

function Warmup.maxScore(): number
	local best = 0
	for _, t in Warmup.Targets do
		best = math.max(best, t.points)
	end
	return Warmup.Shots * best
end

return Warmup
