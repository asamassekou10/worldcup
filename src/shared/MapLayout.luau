--!strict
-- MapLayout: the SINGLE SOURCE OF TRUTH for where things sit on the map.
-- Placement services (HubService, WarmupService, WatchPartyService, the spawn, …)
-- read their anchors from here -- all derived from the pitch's Ball / Keeper /
-- FarGoal markers -- instead of each inventing its own offsets. That keeps the map
-- coherent: the social props form one tidy plaza row along a touchline, the match
-- pitch stays clear, and new props stay coordinated.
--
-- Anchors are returned UNGROUNDED (a nominal Y from the markers); callers raycast
-- them down to the turf as they already do.

local Workspace = game:GetService("Workspace")

local MapLayout = {}

-- How far from the pitch centre the plaza row sits, along the +side touchline.
-- 64 puts the props just INSIDE the perimeter ad-boards (~71) so they read as on
-- the field edge, in front of the boards, rather than tucked behind them in the
-- apron. (Ground is flat turf, ~Y3, from the centre out past the touchline.)
local PLAZA_DIST = 64

local function findMarker(name: string): BasePart?
	local i = Workspace:FindFirstChild(name, true)
	if i and i:IsA("BasePart") then
		return i
	end
	if i and i:IsA("Model") then
		return i.PrimaryPart or i:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

export type Geo = {
	nearGoal: Vector3,
	ball: Vector3,
	axis: Vector3, -- unit, near goal -> far goal (down the pitch)
	side: Vector3, -- unit, across the pitch toward the plaza touchline (+side)
	halfLen: number,
	center: Vector3, -- midfield
}

function MapLayout.geo(): Geo?
	local ball, keeper = findMarker("Ball"), findMarker("Keeper")
	if not ball or not keeper then
		return nil
	end
	local nearGoal = Vector3.new(keeper.Position.X, ball.Position.Y, keeper.Position.Z)
	local far = findMarker("FarGoal")
	local axis: Vector3
	local halfLen: number
	if far then
		local v = Vector3.new(far.Position.X - nearGoal.X, 0, far.Position.Z - nearGoal.Z)
		axis = v.Unit
		halfLen = v.Magnitude / 2
	else
		axis = -Vector3.new(
			keeper.Position.X - ball.Position.X,
			0,
			keeper.Position.Z - ball.Position.Z
		).Unit
		halfLen = 98
	end
	local side = axis:Cross(Vector3.yAxis)
	return {
		nearGoal = nearGoal,
		ball = ball.Position,
		axis = axis,
		side = side,
		halfLen = halfLen,
		center = nearGoal + axis * halfLen,
	}
end

-- Plaza slots along the +side touchline, by `t` = studs from midfield down the
-- pitch (negative = toward the near goal). One evenly-spaced row, spawn in the
-- middle so players arrive facing the pitch with shops to one side and the watch
-- party + booths to the other.
MapLayout.PlazaT = {
	shop = -50,
	ranks = -30,
	store = -10,
	spawn = 6,
	photo = 30,
} :: { [string]: number }

-- The ACTIVITIES row sits on the OPPOSITE touchline (-side): trivia duel, match
-- predictions, the ice-cream treat cart, and the watch-party screen. Keeps the
-- shopping plaza (+side) uncluttered and groups the "things to do" on one side.
MapLayout.ActivityT = {
	trivia = -42,
	predict = -14,
	icecream = 14,
	watch = 42,
} :: { [string]: number }

-- An ungrounded CFrame for a plaza slot, facing across the apron toward the pitch.
function MapLayout.plaza(name: string): CFrame?
	local geo = MapLayout.geo()
	local t = MapLayout.PlazaT[name]
	if not geo or not t then
		return nil
	end
	local pos = geo.center + geo.side * PLAZA_DIST + geo.axis * t
	return CFrame.lookAt(pos, pos - geo.side)
end

-- An ungrounded CFrame for an activities slot on the far (-side) touchline, facing
-- back across the pitch toward the plaza.
function MapLayout.activity(name: string): CFrame?
	local geo = MapLayout.geo()
	local t = MapLayout.ActivityT[name]
	if not geo or not t then
		return nil
	end
	local pos = geo.center - geo.side * PLAZA_DIST + geo.axis * t
	return CFrame.lookAt(pos, pos + geo.side)
end

-- A dedicated CLEAR slot for the Choices-runner portal + its perk shop, at the far end
-- of the activities row (well past the watch-party screen at t=42) so it gets its own
-- corner instead of overlapping the predict booth / treat cart in the middle. Faces the
-- pitch like the other activities.
function MapLayout.choices(): CFrame?
	local geo = MapLayout.geo()
	if not geo then
		return nil
	end
	local pos = geo.center - geo.side * PLAZA_DIST + geo.axis * 78
	return CFrame.lookAt(pos, pos + geo.side)
end

-- The centre of the activities row (a landmark spot, e.g. for the flaming-ball
-- beacon), ungrounded.
function MapLayout.activityCenter(): CFrame?
	local geo = MapLayout.geo()
	if not geo then
		return nil
	end
	local pos = geo.center - geo.side * PLAZA_DIST
	return CFrame.lookAt(pos, pos + geo.side)
end

return MapLayout
