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

-- Practice stations (ungrounded frames; callers drop them to the turf). There are
-- up to two so you can practise at either end of the pitch:
--   1. PRIMARY: a built goal (posts + net) off to the side of the near goal, mouth
--      facing the shooter. `usesRealGoal=false` -> WarmupService builds the posts.
--   2. FAR: in front of the stadium's real far goal (needs a "FarGoal" marker),
--      mouth facing the field. `usesRealGoal=true` -> no posts built; the real goal
--      is the backdrop and only the targets are placed.
export type Station = { frame: CFrame, usesRealGoal: boolean }

function Warmup.stations(): { Station }
	local ball, keeper = findMarker("Ball"), findMarker("Keeper")
	if not ball or not keeper then
		return {}
	end
	local toBall =
		Vector3.new(ball.Position.X - keeper.Position.X, 0, ball.Position.Z - keeper.Position.Z)
	if toBall.Magnitude < 0.1 then
		return {}
	end
	toBall = toBall.Unit

	local out: { Station } = {}
	-- 1. Primary side station (built goal).
	table.insert(out, {
		frame = CFrame.lookAt(keeper.Position, keeper.Position + toBall)
			* CFrame.new(Warmup.Offset, 0, 0),
		usesRealGoal = false,
	})
	-- 2. Far goal station: a built goal just IN FRONT of the stadium's far goal,
	-- facing the field, so the targets always sit inside a real goal mouth (relying
	-- on the stadium goal as a backdrop left them floating with no posts).
	local far = findMarker("FarGoal")
	if far then
		local fp = far.Position
		local toField = Vector3.new(ball.Position.X - fp.X, 0, ball.Position.Z - fp.Z)
		toField = if toField.Magnitude < 0.1 then -toBall else toField.Unit
		-- Step a few studs toward the field so the built posts don't z-fight the
		-- stadium goal behind them.
		local frontPos = fp + toField * 4
		table.insert(out, { frame = CFrame.lookAt(frontPos, frontPos + toField), usesRealGoal = false })
	end
	return out
end

-- Back-compat single frame (the primary station), still used as a fallback.
function Warmup.practiceFrame(): CFrame?
	local stations = Warmup.stations()
	return if stations[1] then stations[1].frame else nil
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
