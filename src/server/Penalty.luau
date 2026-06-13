--!strict
-- Penalty: the authoritative, pure shot-resolution. Continuous skill aiming --
-- a shot (x, y, power) vs. a keeper's dive point (x, y). No Instances, so it's
-- the single, testable place that decides goal/save/miss.
--
-- The duel:
--   * more power shrinks the keeper's reach (harder to save),
--   * ...but too much power sprays the shot (it can miss the goal entirely),
--   * aim far from where the keeper commits and you score.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Penalty = {}

local rng = Random.new()

-- Goal-space (x,y) -> studs, so the keeper's reach is a real circle on the goal.
local function toStuds(x: number, y: number): (number, number)
	return x * (Config.Goal.Width / 2), y * Config.Goal.Height
end

function Penalty.resolveSkill(shot: Types.ShotRequest, keeper: Types.KeeperInput): Types.ShotResult
	local power = math.clamp(shot.power, 0, 1)
	local curve = math.clamp(shot.curve, -1, 1)
	local skill = Config.Skill

	-- 1) Accuracy: leaning past the power sweet spot sprays the shot, and so does
	-- bending it -- harder to place a swerving ball.
	local over = math.max(0, power - skill.SweetSpotPower)
	local spread = skill.BaseSpread
		+ over * skill.SpreadPerOverPower
		+ math.abs(curve) * skill.CurveSpread

	-- Curve bends the endpoint sideways (you aim, then bend it into the corner).
	local bentX = shot.x + curve * skill.CurveBend
	local ax = math.clamp(bentX, -1.3, 1.3) + rng:NextNumber(-spread, spread)
	local ay = math.clamp(shot.y, 0, 1.2) + rng:NextNumber(-spread, spread)

	local outcome: Types.ShotOutcome
	if math.abs(ax) > 1 or ay > 1 or ay < 0 then
		-- Off target -- wide or over the bar.
		outcome = "Miss"
	else
		-- 2) Did the keeper get a hand to it? Distance from dive point to ball,
		-- in studs; reach shrinks with power, and a swerve is harder to read.
		local sx, sy = toStuds(ax, ay)
		local kx, ky = toStuds(math.clamp(keeper.x, -1, 1), math.clamp(keeper.y, 0, 1))
		local dist = math.sqrt((sx - kx) ^ 2 + (sy - ky) ^ 2)
		local reach = skill.BaseReach
			- power * skill.ReachPerPower
			- math.abs(curve) * skill.CurveBeat
		outcome = if dist <= reach then "Save" else "Goal"
	end

	return {
		outcome = outcome,
		shotX = ax,
		shotY = ay,
		keeperX = keeper.x,
		keeperY = keeper.y,
		curve = curve,
	}
end

return Penalty
