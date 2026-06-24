--!strict
-- Venue: the gameplay frame derived from the hand-built stadium in the
-- Workspace. Instead of a code-built arena, we locate two marker parts -- `Ball`
-- (the penalty spot) and `Keeper` (the goal-line centre) -- and compute the
-- goal's orientation, the aim-zone world positions, and the TV camera from
-- them. Works at any stadium position/rotation, so nothing is hardcoded.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Warmup = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Warmup"))

local Venue = {}

-- Resolve a named marker to a BasePart. Accepts either a Part named `name` or a
-- Model named `name` (using its PrimaryPart or first descendant part), since
-- Toolbox assets are usually Models.
local function findPart(name: string): BasePart?
	local inst = Workspace:FindFirstChild(name, true)
	if not inst then
		return nil
	end
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

function Venue.ball(): BasePart?
	return findPart("Ball")
end

function Venue.keeper(): BasePart?
	return findPart("Keeper")
end

-- The raw named instance (Model or Part) -- used by the animator, which moves a
-- Model via PivotTo and a Part via CFrame.
function Venue.instance(name: string): Instance?
	return Workspace:FindFirstChild(name, true)
end

-- Goal frame: positioned at the goal-line centre (the Keeper marker), with its
-- LookVector pointing toward the ball (the shooter). RightVector then spans the
-- goal mouth horizontally.
function Venue.goalCFrame(): CFrame?
	local ball, keeper = Venue.ball(), Venue.keeper()
	if not ball or not keeper then
		return nil
	end
	local toBall = ball.Position - keeper.Position
	toBall = Vector3.new(toBall.X, 0, toBall.Z)
	if toBall.Magnitude < 0.1 then
		return nil
	end
	return CFrame.lookAt(keeper.Position, keeper.Position + toBall.Unit)
end

-- World extent of `part` measured along a world-space `axis` (handles any
-- rotation): project each of the part's three sized edges onto the axis.
local function extentAlong(part: BasePart, axis: Vector3): number
	local cf, s = part.CFrame, part.Size
	return math.abs(cf.RightVector:Dot(axis)) * s.X
		+ math.abs(cf.UpVector:Dot(axis)) * s.Y
		+ math.abs(cf.LookVector:Dot(axis)) * s.Z
end

-- The real goal mouth: width (post-to-post), height (ground-to-crossbar), and
-- the world Y of the base. Self-calibrating -- if the `Keeper` marker has been
-- scaled to fill the goal mouth (width >= 10 studs), we read the real cage off
-- it so the ball lines up exactly. A small point marker falls back to Config.
function Venue.goalDims(): (number, number, number)
	local keeper, frame = Venue.keeper(), Venue.goalCFrame()
	if keeper and frame then
		local width = extentAlong(keeper, frame.RightVector)
		if width >= 10 then -- marker sized across the posts -> calibrate from it
			local height = extentAlong(keeper, Vector3.yAxis)
			return width, height, keeper.Position.Y - height / 2
		end
		-- Keeper marker sits at mid-goal height; subtract half-height to get the base Y.
		return Config.Goal.Width, Config.Goal.Height, keeper.Position.Y - Config.Goal.Height / 2
	end
	return Config.Goal.Width, Config.Goal.Height, 0
end

-- World position of a continuous aim point: x in [-1,1] across the goal width,
-- y in [0,1] from ground to crossbar (can go outside for misses).
function Venue.goalPointWorld(x: number, y: number): Vector3?
	local frame = Venue.goalCFrame()
	if not frame then
		return nil
	end
	local width, height, baseY = Venue.goalDims()
	local horizontal = frame.RightVector * (x * (width / 2))
	return Vector3.new(
		frame.Position.X + horizontal.X,
		baseY + y * height,
		frame.Position.Z + horizontal.Z
	)
end

-- Inverse of goalPointWorld: a world point on the goal plane -> normalized (x,y).
function Venue.worldToGoalPoint(hit: Vector3): (number?, number?)
	local frame = Venue.goalCFrame()
	if not frame then
		return nil, nil
	end
	local width, height, baseY = Venue.goalDims()
	local lp = frame:PointToObjectSpace(hit)
	return lp.X / (width / 2), (hit.Y - baseY) / height
end

-- TV penalty camera: set back behind the ball and raised, framing the whole
-- goal mouth (the shooter sits in the lower third, keeper + goal beyond).
function Venue.cameraCFrame(): CFrame?
	local ball = Venue.ball()
	local frame = Venue.goalCFrame()
	if not ball or not frame then
		return nil
	end
	local _, height, baseY = Venue.goalDims()
	local behind = ball.Position + frame.LookVector * 20 + Vector3.new(0, 11, 0)
	local lookAt = Vector3.new(frame.Position.X, baseY + height * 0.45, frame.Position.Z)
	return CFrame.lookAt(behind, lookAt)
end

-- Keeper view: a low 3/4 angle from the FIELD side (never behind the goal, where
-- the net + ad boards would clutter the shot). Distinct from the shooter's wide
-- straight-on TV cam, with the goal mouth clear for aiming the dive.
function Venue.keeperCameraCFrame(): CFrame?
	local frame = Venue.goalCFrame()
	if not frame then
		return nil
	end
	local _, height, baseY = Venue.goalDims()
	local pos = frame.Position
		+ frame.LookVector * 16 -- out toward the field (in front of the goal)
		+ frame.RightVector * 8 -- offset to one side for a 3/4 angle
		+ Vector3.new(0, 4.5, 0) -- low and dramatic
	local lookAt = Vector3.new(frame.Position.X, baseY + height * 0.5, frame.Position.Z)
	return CFrame.lookAt(pos, lookAt)
end

-- ===== Warmup practice goal: the real goal shifted sideways, dropped to ground =====

-- Surface Y beneath an XZ point (so the practice goal rests on the turf instead
-- of hanging at the goal-line marker's height). Ignores the warmup props.
local function groundY(pos: Vector3, fallback: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excludes: { Instance } = {}
	local range = Workspace:FindFirstChild("WarmupRange")
	if range then
		table.insert(excludes, range)
	end
	params.FilterDescendantsInstances = excludes
	local hit = Workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -300, 0), params)
	return if hit then hit.Position.Y else fallback
end

function Venue.practiceGoalCFrame(): CFrame?
	-- Aim at the practice station NEAREST the local player, so walking to either end
	-- of the pitch practises at that goal. The character stands at the spot through
	-- the round, so the choice stays stable once a session begins.
	local stations = Warmup.stations()
	if #stations == 0 then
		return nil
	end
	local frame = stations[1].frame
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and #stations > 1 then
		local best = math.huge
		for _, s in stations do
			local d = (s.frame.Position - root.Position).Magnitude
			if d < best then
				best = d
				frame = s.frame
			end
		end
	end
	local p = frame.Position
	return CFrame.new(Vector3.new(p.X, groundY(p, p.Y), p.Z)) * frame.Rotation
end

function Venue.practicePointWorld(x: number, y: number): Vector3?
	local frame = Venue.practiceGoalCFrame()
	if not frame then
		return nil
	end
	return frame.Position
		+ frame.RightVector * (x * (Config.Goal.Width / 2))
		+ Vector3.new(0, y * Config.Goal.Height, 0)
end

-- Where the player stands to take practice shots (in front of the practice goal).
function Venue.practiceSpot(): Vector3?
	local frame = Venue.practiceGoalCFrame()
	if not frame then
		return nil
	end
	return frame.Position + frame.LookVector * Config.Goal.PenaltySpotDistance
end

function Venue.practiceCameraCFrame(): CFrame?
	local frame = Venue.practiceGoalCFrame()
	if not frame then
		return nil
	end
	-- Set back further + raised so the whole goal frames cleanly (and the crowd
	-- behind it is a backdrop, not in your face).
	local behind = frame.Position + frame.LookVector * 26 + Vector3.new(0, 13, 0)
	local lookAt = frame.Position + Vector3.new(0, Config.Goal.Height * 0.5, 0)
	return CFrame.lookAt(behind, lookAt)
end

return Venue
