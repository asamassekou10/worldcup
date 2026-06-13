--!strict
-- World: geometry + lighting builder (golden-hour stylized stadium).
--   * setupLighting()       -- Future lighting, atmosphere & post-processing.
--   * buildShowcase()       -- the permanent stadium used as the menu backdrop.
--   * buildArenaTemplate()  -- a reusable stadium authored in local space;
--                              ArenaService clones it per match.
--
-- Art contract (so an artist can replace ServerStorage.ArenaTemplate in Studio
-- without code changes): keep a `Ball` and `Keeper` BasePart at the local
-- positions below, goal mouth = Config.Goal dims, authored facing -Z with the
-- pivot at the goal-line center.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local World = {}

-- ============================== PALETTE ==============================

local TURF_LIGHT = Color3.fromRGB(86, 162, 84)
local TURF_DARK = Color3.fromRGB(66, 140, 70)
local LINE = Color3.fromRGB(235, 240, 235)
local FRAME_WHITE = Color3.fromRGB(245, 245, 248)
local CONCRETE = Color3.fromRGB(126, 126, 134)
local CONCRETE_DARK = Color3.fromRGB(92, 92, 100)
local METAL = Color3.fromRGB(150, 156, 168)
local ROOF = Color3.fromRGB(58, 62, 74)
local LAMP = Color3.fromRGB(255, 248, 214)

-- Host-nation accent colors (USA / Canada / Mexico), reused for ads/podium.
local HOST = {
	Color3.fromRGB(60, 110, 200),
	Color3.fromRGB(214, 64, 64),
	Color3.fromRGB(60, 168, 96),
}

-- A vivid spread of national colors for the packed crowd and the flag festoon,
-- to get the multicolor World Cup look from the reference art.
local NATIONS = {
	Color3.fromRGB(0, 82, 180),
	Color3.fromRGB(206, 17, 38),
	Color3.fromRGB(0, 140, 80),
	Color3.fromRGB(255, 205, 0),
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(247, 127, 0),
	Color3.fromRGB(120, 45, 150),
	Color3.fromRGB(0, 165, 180),
	Color3.fromRGB(232, 90, 160),
	Color3.fromRGB(140, 200, 60),
	Color3.fromRGB(30, 34, 48),
	Color3.fromRGB(196, 160, 90),
}

local VIEW_BEHIND_BALL = 6
local rng = Random.new(2026)

-- Where the (frozen, nameplate-hidden) player stands at the menu: behind the
-- hero camera so they're never in the shot.
World.MENU_STAND = CFrame.new(0, 4, 85)

local function add(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- ============================== LIGHTING ==============================

local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

-- Golden-hour mood + post-processing. The single biggest "polished vs. cheap"
-- lever on Roblox; tuned to read warm and cinematic.
function World.setupLighting()
	-- NOTE: Lighting.Technology is locked to scripts (RobloxScript capability);
	-- it's set to Future in default.project.json instead. Everything below is
	-- script-writable.
	-- Bright, vivid match-day (matching the reference art): high midday sun,
	-- punchy saturation, clear blue sky.
	Lighting.ClockTime = 14 -- midday
	Lighting.GeographicLatitude = 10
	Lighting.Brightness = 2.2
	Lighting.ExposureCompensation = -0.05
	Lighting.Ambient = Color3.fromRGB(62, 66, 82) -- deeper shadows for contrast
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 158, 175)
	Lighting.ShadowSoftness = 0.25 -- crisper, more defined shadows
	Lighting.FogEnd = 2500

	local atmosphere = ensure(Lighting, "Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 212, 228)
	atmosphere.Decay = Color3.fromRGB(140, 165, 195)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.2

	ensure(Lighting, "Sky", "Sky")

	local cc = ensure(Lighting, "ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Brightness = 0.02
	cc.Contrast = 0.16 -- filmic punch
	cc.Saturation = 0.22 -- rich but not garish
	cc.TintColor = Color3.fromRGB(255, 251, 244) -- a hair warm

	local bloom = ensure(Lighting, "BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.4 -- subtle; just enough for the floodlights to glow
	bloom.Size = 24
	bloom.Threshold = 1.1

	local sunRays = ensure(Lighting, "SunRaysEffect", "SunRays") :: SunRaysEffect
	sunRays.Intensity = 0.12
	sunRays.Spread = 0.4

	local dof = ensure(Lighting, "DepthOfFieldEffect", "DOF") :: DepthOfFieldEffect
	dof.FarIntensity = 0.08
	dof.FocusDistance = 55
	dof.InFocusRadius = 45
	dof.NearIntensity = 0
end

-- ====================== AIM / VIEW HELPERS (unchanged contract) ======================

function World.viewingCFrame(offset: Vector3, index: number): CFrame
	local x = if index == 1 then -2.5 else 2.5
	local viewPos = Vector3.new(x, 5, Config.Goal.PenaltySpotDistance + VIEW_BEHIND_BALL) + offset
	local lookAt = Vector3.new(0, Config.Goal.Height / 2, 0) + offset
	return CFrame.lookAt(viewPos, lookAt)
end

-- ============================ STADIUM PIECES ============================

-- Striped turf + painted line markings. Field local space: goal line at z=0,
-- pitch runs toward +z (run-up) and -z (behind goal).
local function buildPitch(arena: Model)
	local fieldWidth = 64
	local zFront, zBack = 40, -36
	local bands = 8
	local bandDepth = (zFront - zBack) / bands
	for i = 0, bands - 1 do
		local z = zBack + bandDepth * (i + 0.5)
		add(
			arena,
			"Turf",
			Vector3.new(fieldWidth, 1, bandDepth + 0.05),
			CFrame.new(0, -0.5, z),
			if i % 2 == 0 then TURF_LIGHT else TURF_DARK,
			Enum.Material.Grass
		)
	end

	-- Painted lines sit just above the turf.
	local function line(sx: number, sz: number, x: number, z: number)
		add(
			arena,
			"Line",
			Vector3.new(sx, 0.1, sz),
			CFrame.new(x, 0.06, z),
			LINE,
			Enum.Material.SmoothPlastic
		)
	end

	-- Goal line + the 18-yard and 6-yard boxes (drawn in front of the goal).
	line(fieldWidth, 0.3, 0, 0)
	-- 18-yard box (x: -20..20, z: 0..17)
	line(0.3, 17, -20, 8.5)
	line(0.3, 17, 20, 8.5)
	line(40.3, 0.3, 0, 17)
	-- 6-yard box (x: -10..10, z: 0..6)
	line(0.3, 6, -10, 3)
	line(0.3, 6, 10, 3)
	line(20.3, 0.3, 0, 6)

	-- Penalty arc (a few segments at the top of the box, centred on the spot).
	local spotZ = Config.Goal.PenaltySpotDistance
	for i = -2, 2 do
		local a = math.rad(90 + i * 18)
		local r = 9
		local x = math.cos(a) * r
		local z = spotZ - math.sin(a) * r
		add(
			arena,
			"Arc",
			Vector3.new(1.4, 0.1, 0.3),
			CFrame.new(x, 0.06, z) * CFrame.Angles(0, -a, 0),
			LINE,
			Enum.Material.SmoothPlastic
		)
	end
end

local function buildGoalAndNet(arena: Model)
	local goal = Config.Goal
	local postThickness = 0.6
	local halfWidth = goal.Width / 2

	add(
		arena,
		"PostLeft",
		Vector3.new(postThickness, goal.Height, postThickness),
		CFrame.new(-halfWidth, goal.Height / 2, 0),
		FRAME_WHITE,
		Enum.Material.Metal
	)
	add(
		arena,
		"PostRight",
		Vector3.new(postThickness, goal.Height, postThickness),
		CFrame.new(halfWidth, goal.Height / 2, 0),
		FRAME_WHITE,
		Enum.Material.Metal
	)
	add(
		arena,
		"Crossbar",
		Vector3.new(goal.Width + postThickness, postThickness, postThickness),
		CFrame.new(0, goal.Height, 0),
		FRAME_WHITE,
		Enum.Material.Metal
	)

	-- Net: four translucent panels forming the goal bag (behind the line).
	local depth = 4
	local function netPanel(name: string, size: Vector3, cframe: CFrame)
		local p = add(
			arena,
			name,
			size,
			cframe,
			Color3.fromRGB(235, 238, 245),
			Enum.Material.SmoothPlastic
		)
		p.Transparency = 0.55
		p.CastShadow = false
	end
	netPanel(
		"NetBack",
		Vector3.new(goal.Width, goal.Height, 0.1),
		CFrame.new(0, goal.Height / 2, -depth)
	)
	netPanel("NetTop", Vector3.new(goal.Width, 0.1, depth), CFrame.new(0, goal.Height, -depth / 2))
	netPanel(
		"NetLeft",
		Vector3.new(0.1, goal.Height, depth),
		CFrame.new(-halfWidth, goal.Height / 2, -depth / 2)
	)
	netPanel(
		"NetRight",
		Vector3.new(0.1, goal.Height, depth),
		CFrame.new(halfWidth, goal.Height / 2, -depth / 2)
	)

	-- Penalty spot (contract marker) + the gameplay Keeper and Ball.
	add(
		arena,
		"PenaltySpot",
		Vector3.new(1, 0.05, 1),
		CFrame.new(0, 0.06, goal.PenaltySpotDistance),
		LINE,
		Enum.Material.SmoothPlastic
	)

	add(
		arena,
		"Keeper",
		Vector3.new(4, 6, 1),
		CFrame.new(0, 3, 0.5),
		Color3.fromRGB(235, 190, 50),
		Enum.Material.SmoothPlastic
	)

	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.Size = Vector3.new(1.6, 1.6, 1.6)
	ball.Position = Vector3.new(0, 0.8, goal.PenaltySpotDistance)
	ball.Color = Color3.fromRGB(250, 250, 250)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Parent = arena
end

-- A tiered concrete stand. `faceZ` is the front edge; tiers step back/up away
-- from the pitch. Returns the top Y so a roof can sit above it.
local function buildStand(arena: Model, originCFrame: CFrame, width: number, tiers: number): number
	local tierH, tierD = 3, 4
	for i = 0, tiers - 1 do
		local y = tierH / 2 + i * tierH
		local back = -i * tierD
		add(
			arena,
			"Stand",
			Vector3.new(width, tierH, tierD),
			originCFrame * CFrame.new(0, y, back),
			if i % 2 == 0 then CONCRETE else CONCRETE_DARK,
			Enum.Material.Concrete
		)
	end
	return tiers * tierH
end

-- Coarse crowd: small colored blocks across the front tiers of the main stand.
-- Pack a crowd block onto every tier, wall to wall, in vivid nation colors.
-- `cols` is auto-derived from the width so seats stay ~1 stud wide (dense).
local function buildCrowd(arena: Model, originCFrame: CFrame, width: number, tiers: number)
	local tierH, tierD = 3, 4
	local cols = math.floor(width / 2.0)
	local seatW = width / cols
	for r = 0, tiers - 1 do
		for c = 0, cols - 1 do
			local x = -width / 2 + (c + 0.5) * seatW
			local y = tierH / 2 + r * tierH + 1.7
			local back = -r * tierD
			local seat = NATIONS[rng:NextInteger(1, #NATIONS)]
			local tint = rng:NextNumber(0.82, 1.12)
			add(
				arena,
				"Fan",
				Vector3.new(seatW * 0.92, 1.6, 1),
				originCFrame * CFrame.new(x, y, back + 0.7),
				Color3.new(
					math.clamp(seat.R * tint, 0, 1),
					math.clamp(seat.G * tint, 0, 1),
					math.clamp(seat.B * tint, 0, 1)
				),
				Enum.Material.SmoothPlastic
			)
		end
	end
end

local function buildFloodlight(arena: Model, x: number, z: number)
	add(
		arena,
		"FloodPole",
		Vector3.new(1.2, 44, 1.2),
		CFrame.new(x, 22, z),
		METAL,
		Enum.Material.Metal
	)
	local bank = add(
		arena,
		"FloodBank",
		Vector3.new(8, 4, 1.5),
		CFrame.new(x, 44, z),
		Color3.fromRGB(40, 42, 50),
		Enum.Material.Metal
	)
	bank.CFrame = CFrame.new(Vector3.new(x, 44, z), Vector3.new(0, 8, 0))
	-- Glowing lamp face (Neon = free light without a dynamic-light budget hit).
	local lamp = add(
		arena,
		"FloodLamp",
		Vector3.new(7, 3, 0.4),
		bank.CFrame * CFrame.new(0, 0, -0.9),
		LAMP,
		Enum.Material.Neon
	)
	lamp.CastShadow = false
end

local function buildAdBoards(arena: Model)
	-- A row of boards behind the goal line, host-nation colored.
	for i = -3, 3 do
		add(
			arena,
			"AdBoard",
			Vector3.new(7, 1.6, 0.4),
			CFrame.new(i * 7.5, 0.8, -6.5),
			HOST[((i + 3) % #HOST) + 1],
			Enum.Material.SmoothPlastic
		)
	end
end

local function buildCornerFlags(arena: Model)
	for _, x in { -31, 31 } do
		add(
			arena,
			"CornerPole",
			Vector3.new(0.3, 7, 0.3),
			CFrame.new(x, 3.5, 0.5),
			Color3.fromRGB(230, 230, 230),
			Enum.Material.SmoothPlastic
		)
		add(
			arena,
			"CornerFlag",
			Vector3.new(2.4, 1.6, 0.15),
			CFrame.new(x + 1.2, 6, 0.5),
			HOST[1],
			Enum.Material.SmoothPlastic
		)
	end
end

-- National flags: a banner row along the top of the main stand + an overhead
-- ring around the bowl. The festoon is the signature look from the reference.
local function buildFlags(arena: Model, mainTop: number, backZ: number)
	-- Banner of flags across the top of the main stand.
	local count = 30
	for i = 0, count - 1 do
		local x = -38 + i * (76 / (count - 1))
		add(
			arena,
			"StandFlag",
			Vector3.new(2.2, 1.5, 0.15),
			CFrame.new(x, mainTop + 2.5, backZ + 15),
			NATIONS[(i % #NATIONS) + 1],
			Enum.Material.Fabric
		)
	end

	-- Overhead ring of flags strung around the stadium.
	local ringCount = 40
	for i = 0, ringCount - 1 do
		local a = (i / ringCount) * math.pi * 2
		local r = 50
		local x, z = math.cos(a) * r, math.sin(a) * r - 6
		add(
			arena,
			"RingFlag",
			Vector3.new(3, 2, 0.2),
			CFrame.new(x, 30, z) * CFrame.Angles(0, -a, 0),
			NATIONS[(i % #NATIONS) + 1],
			Enum.Material.Fabric
		)
	end
end

-- A branded jumbotron screen above the main stand, facing the pitch (+Z).
local function buildJumbotron(arena: Model, y: number, z: number)
	add(
		arena,
		"JumboFrame",
		Vector3.new(28, 15, 1.5),
		CFrame.new(0, y, z),
		ROOF,
		Enum.Material.Metal
	)
	local screen = add(
		arena,
		"JumboScreen",
		Vector3.new(25, 12, 0.6),
		CFrame.new(0, y, z + 0.6),
		Color3.fromRGB(22, 26, 36),
		Enum.Material.SmoothPlastic
	)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "JumboGui"
	gui.Face = Enum.NormalId.Back -- +Z face, toward the pitch
	gui.CanvasSize = Vector2.new(800, 384)
	gui.Parent = screen

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = "⚽ PENALTY KINGS\nWORLD CUP 2026"
	label.Parent = gui
end

-- ============================ ARENA TEMPLATE ============================

function World.buildArenaTemplate(): Model
	local arena = Instance.new("Model")
	arena.Name = "ArenaTemplate"

	buildPitch(arena)
	buildGoalAndNet(arena)
	buildAdBoards(arena)
	buildCornerFlags(arena)

	-- Main grandstand behind the goal. Front edge at z=-14, +Z faces the pitch;
	-- buildStand rakes the tiers up and back (toward -Z).
	local mainFront = CFrame.new(0, 0, -14)
	local mainWidth = 80
	local mainTiers = 8
	local mainTop = buildStand(arena, mainFront, mainWidth, mainTiers)
	buildCrowd(arena, mainFront, mainWidth, mainTiers)
	local backZ = -14 - mainTiers * 4

	-- Players' tunnel mouth at the base of the main stand.
	add(
		arena,
		"Tunnel",
		Vector3.new(9, 6, 5),
		CFrame.new(0, 3, -14.5),
		Color3.fromRGB(16, 16, 20),
		Enum.Material.Concrete
	)

	-- Roof canopy over the back of the stand, on two pillars.
	add(
		arena,
		"Roof",
		Vector3.new(mainWidth + 10, 1, 34),
		CFrame.new(0, mainTop + 6, backZ + 12),
		ROOF,
		Enum.Material.Metal
	)
	add(
		arena,
		"RoofPillar",
		Vector3.new(1.5, mainTop + 6, 1.5),
		CFrame.new(-mainWidth / 2, (mainTop + 6) / 2, backZ + 4),
		METAL,
		Enum.Material.Metal
	)
	add(
		arena,
		"RoofPillar",
		Vector3.new(1.5, mainTop + 6, 1.5),
		CFrame.new(mainWidth / 2, (mainTop + 6) / 2, backZ + 4),
		METAL,
		Enum.Material.Metal
	)

	-- Jumbotron above the main stand.
	buildJumbotron(arena, mainTop + 13, backZ + 14)

	-- Side stands along the touchlines, packed. Left faces +X, right faces -X.
	local leftFront = CFrame.new(-44, 0, 4) * CFrame.Angles(0, math.pi / 2, 0)
	local rightFront = CFrame.new(44, 0, 4) * CFrame.Angles(0, -math.pi / 2, 0)
	buildStand(arena, leftFront, 80, 5)
	buildStand(arena, rightFront, 80, 5)
	buildCrowd(arena, leftFront, 80, 5)
	buildCrowd(arena, rightFront, 80, 5)

	-- Corner infills (also packed) so the bowl reads continuous behind the goal.
	local leftCorner = CFrame.new(-40, 0, -10) * CFrame.Angles(0, math.pi / 4, 0)
	local rightCorner = CFrame.new(40, 0, -10) * CFrame.Angles(0, -math.pi / 4, 0)
	buildStand(arena, leftCorner, 30, 6)
	buildStand(arena, rightCorner, 30, 6)
	buildCrowd(arena, leftCorner, 30, 6)
	buildCrowd(arena, rightCorner, 30, 6)

	-- National-flag festoon (banner + overhead ring).
	buildFlags(arena, mainTop, backZ)

	-- Floodlight towers at the four corners.
	buildFloodlight(arena, -46, backZ)
	buildFloodlight(arena, 46, backZ)
	buildFloodlight(arena, -46, 40)
	buildFloodlight(arena, 46, 40)

	arena.WorldPivot = CFrame.identity
	return arena
end

function World.ensureArenaTemplate(): Model
	local existing = ServerStorage:FindFirstChild("ArenaTemplate")
	if existing and existing:IsA("Model") then
		return existing
	end
	local template = World.buildArenaTemplate()
	template.Parent = ServerStorage
	return template
end

-- ============================== SHOWCASE STADIUM ==============================

-- A permanent stadium at the origin used as the cinematic menu backdrop. It is
-- just a clone of the same template matches use. Players don't roam here -- the
-- client locks a hero camera onto it (see client/MenuCamera).
function World.buildShowcase(): Model
	local existing = workspace:FindFirstChild("Showcase")
	if existing then
		existing:Destroy()
	end

	local showcase = Instance.new("Model")
	showcase.Name = "Showcase"

	-- Wide ground so there's no void around the stadium in the hero shot.
	add(
		showcase,
		"Ground",
		Vector3.new(400, 1, 400),
		CFrame.new(0, -0.6, 0),
		Color3.fromRGB(70, 120, 72),
		Enum.Material.Grass
	)

	-- One valid spawn (characters only load during matches; this keeps Roblox
	-- happy and is out of the hero shot anyway).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MenuSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 85)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = showcase

	-- The menu backdrop: a clone of ServerStorage.ArenaTemplate -- your
	-- Studio-built stadium if you've placed one there, else the procedural one.
	local stadium = World.ensureArenaTemplate():Clone()
	stadium.Name = "Stadium"
	stadium.WorldPivot = CFrame.identity
	stadium:PivotTo(CFrame.identity)
	stadium.Parent = showcase

	showcase.Parent = workspace
	return showcase
end

return World
