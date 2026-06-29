--!strict
-- Decor: World Cup dressing for the hand-built stadium, anchored to the `Ball`
-- and `Keeper` markers so it lands correctly without us seeing the stadium.
-- Static dressing (banner, ad boards, bunting, corner flags, pitch logo, smoke)
-- is placed once; fireworks + the winner trophy-lift are celebration moments.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local Decor = {}

local HOST = {
	Color3.fromRGB(60, 110, 200),
	Color3.fromRGB(214, 64, 64),
	Color3.fromRGB(60, 168, 96),
}
local NATIONS = {
	Color3.fromRGB(0, 82, 180),
	Color3.fromRGB(206, 17, 38),
	Color3.fromRGB(255, 205, 0),
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(0, 140, 80),
	Color3.fromRGB(247, 127, 0),
	Color3.fromRGB(120, 45, 150),
	Color3.fromRGB(0, 165, 180),
}

type Geo = {
	ball: Vector3,
	goal: Vector3,
	dir: Vector3,
	right: Vector3,
	standY: number,
	groundY: number,
}

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
		groundY = ball.Position.Y - 0.8, -- the ball rests on the pitch
	}
end

local function part(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

-- ============================ STATIC DRESSING ============================

function Decor.setup()
	local g = geo()
	if not g then
		return
	end
	local existing = workspace:FindFirstChild("WorldCupDecor")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "WorldCupDecor"
	folder.Parent = workspace

	local height = Config.Goal.Height
	local halfWidth = Config.Goal.Width / 2

	-- Field length: prefer the "FarGoal" marker (exact: near goal -> far goal, so
	-- half = /2); else the "Center" marker (goal -> halfway); else an estimate. The
	-- half-width is proportional (real pitches are ~0.65x as wide as long) -- bump
	-- the factor if your stands sit wider than the crowd lands.
	local farGoal = findPart("FarGoal")
	local centerPart = findPart("Center")
	local halfLen = 30
	if farGoal then
		halfLen = Vector3.new(farGoal.Position.X - g.goal.X, 0, farGoal.Position.Z - g.goal.Z).Magnitude
			/ 2
	elseif centerPart then
		halfLen = Vector3.new(centerPart.Position.X - g.goal.X, 0, centerPart.Position.Z - g.goal.Z)
			:Dot(-g.dir)
	end
	-- Turf measured 143.92 studs wide → half = 71.96 ≈ 72 (Config.Pitch.HalfWidth).
	local pitchHalf = math.max(halfWidth + 22, Config.Pitch.HalfWidth)

	-- Find the real pitch surface by raycasting straight down, so nothing floats
	-- regardless of the stadium's heights. Ignore the decor + the markers, AND the hub activity
	-- props -- otherwise the crowd/decor lands ON TOP of the gym equipment, stalls, etc. instead of
	-- passing through to the turf (which is why fans were appearing inside the Training Zone).
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludes: { Instance } = { folder }
	local hubProps = workspace:FindFirstChild("HubProps")
	if hubProps then
		table.insert(excludes, hubProps)
	end
	for _, name in { "Ball", "Keeper" } do
		local marker = workspace:FindFirstChild(name, true)
		if marker then
			table.insert(excludes, marker)
		end
	end
	rayParams.FilterDescendantsInstances = excludes

	-- `ground(xz, y)` keeps X/Z and returns `y` studs above the turf beneath it.
	local function ground(xz: Vector3, y: number): Vector3
		local origin = Vector3.new(xz.X, g.ball.Y + 80, xz.Z)
		local hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), rayParams)
		local surfaceY = if hit then hit.Position.Y else g.groundY
		return Vector3.new(xz.X, surfaceY + y, xz.Z)
	end

	-- Advertising boards on the ground behind the goal line.
	for i = -1, 1 do
		local pos = ground(g.goal + g.dir * 3 + g.right * (i * (halfWidth - 2)), 0.8)
		part(
			folder,
			Vector3.new(6, 1.6, 0.4),
			CFrame.lookAt(pos, pos - g.dir),
			HOST[i + 2],
			Enum.Material.SmoothPlastic
		)
	end

	-- Flag bunting strung in an arc above the crossbar.
	local flagCount = 11
	for i = 0, flagCount - 1 do
		local t = (i / (flagCount - 1)) * 2 - 1
		local lift = (1 - t * t) * 2
		local pos = ground(g.goal + g.right * (t * (halfWidth + 1)), height + 1.5 + lift)
		local flag = part(
			folder,
			Vector3.new(1.6, 1.1, 0.15),
			CFrame.new(pos),
			NATIONS[(i % #NATIONS) + 1],
			Enum.Material.Fabric
		)
		CollectionService:AddTag(flag, "WCFlag")
	end

	-- Corner flags standing on the ground at the goalposts.
	for _, side in { -1, 1 } do
		local foot = g.goal + g.right * (halfWidth * side)
		part(
			folder,
			Vector3.new(0.3, 7, 0.3),
			CFrame.new(ground(foot, 3.5)),
			Color3.fromRGB(235, 235, 235),
			Enum.Material.SmoothPlastic
		)
		local flag = part(
			folder,
			Vector3.new(2.4, 1.5, 0.15),
			CFrame.new(ground(foot + g.dir * 0.2, 6)),
			HOST[1],
			Enum.Material.Fabric
		)
		CollectionService:AddTag(flag, "WCFlag")
	end

	-- Pitch-side advertising boards lining both touchlines, the full field length.
	local sideX = pitchHalf - 1
	for _, side in { -1, 1 } do
		local boards = math.clamp(math.floor((2 * halfLen) / 9), 4, 30)
		for j = 0, boards do
			local pos = ground(g.goal + g.right * (sideX * side) - g.dir * (j * 9 + 3), 0.8)
			part(
				folder,
				Vector3.new(8, 1.6, 0.4),
				CFrame.lookAt(pos, pos - g.right * side),
				HOST[(j % #HOST) + 1],
				Enum.Material.SmoothPlastic
			)
		end
	end

	-- Fan-poster banners of the icon players, raised on poles ABOVE the touchline activity row so
	-- they read as proper framed posters (gold border + name) and never block the stalls/signs.
	do
		local POSTERS = {
			{ img = Config.Icons.StickerMessi, name = "MESSI" },
			{ img = Config.Icons.StickerRonaldo, name = "RONALDO" },
			{ img = Config.Icons.StickerMbappe, name = "MBAPPÉ" },
			{ img = Config.Icons.StickerNeymar, name = "NEYMAR" },
		}
		local idx = 0
		for _, side in { -1, 1 } do
			for _, frac in { 0.5, 1.5 } do
				idx += 1
				local p = POSTERS[idx]
				if p.img and p.img ~= "" then
					local base = g.goal
						+ g.right * ((pitchHalf + 9) * side)
						- g.dir * (halfLen * frac)
					-- a support pole from the turf up to the banner
					part(
						folder,
						Vector3.new(0.8, 17, 0.8),
						CFrame.new(ground(base, 8.5)),
						Color3.fromRGB(60, 66, 78),
						Enum.Material.Metal
					)
					local centre = ground(base, 18)
					local board = part(
						folder,
						Vector3.new(11, 14, 0.6),
						CFrame.lookAt(centre, centre - g.right * side),
						Color3.fromRGB(18, 24, 46),
						Enum.Material.SmoothPlastic
					)
					-- both broad faces, so it reads from either direction
					for _, f in { Enum.NormalId.Front, Enum.NormalId.Back } do
						local sg = Instance.new("SurfaceGui")
						sg.Face = f
						sg.CanvasSize = Vector2.new(440, 560)
						sg.Parent = board
						local frame = Instance.new("Frame")
						frame.Size = UDim2.fromScale(1, 1)
						frame.BackgroundColor3 = Color3.fromRGB(26, 40, 86)
						frame.Parent = sg
						local grad = Instance.new("UIGradient")
						grad.Color = ColorSequence.new(
							Color3.fromRGB(42, 66, 140),
							Color3.fromRGB(14, 20, 44)
						)
						grad.Rotation = 90
						grad.Parent = frame
						local border = Instance.new("UIStroke")
						border.Color = Color3.fromRGB(255, 210, 90)
						border.Thickness = 9
						border.Parent = frame
						local pic = Instance.new("ImageLabel")
						pic.Size = UDim2.fromScale(0.9, 0.74)
						pic.Position = UDim2.fromScale(0.05, 0.04)
						pic.BackgroundTransparency = 1
						pic.ScaleType = Enum.ScaleType.Fit
						pic.Image = p.img
						pic.Parent = frame
						local nm = Instance.new("TextLabel")
						nm.Size = UDim2.fromScale(0.92, 0.16)
						nm.Position = UDim2.fromScale(0.04, 0.8)
						nm.BackgroundTransparency = 1
						nm.Font = Enum.Font.GothamBlack
						nm.TextScaled = true
						nm.TextColor3 = Color3.fromRGB(255, 215, 100)
						nm.Text = p.name
						nm.Parent = frame
					end
				end
			end
		end
	end

	-- Atmosphere: colored smoke rising from the ground behind the goal corners.
	for _, side in { -1, 1 } do
		local emitterPart = part(
			folder,
			Vector3.new(1, 1, 1),
			CFrame.new(ground(g.goal + g.dir * 4 + g.right * (halfWidth * side), 0)),
			Color3.fromRGB(255, 255, 255),
			Enum.Material.SmoothPlastic
		)
		emitterPart.Transparency = 1
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(HOST[if side == -1 then 1 else 2])
		smoke.Lifetime = NumberRange.new(2.5, 4)
		smoke.Rate = 6
		smoke.Speed = NumberRange.new(2, 4)
		smoke.Size = NumberSequence.new(3, 7)
		smoke.Transparency = NumberSequence.new(0.6, 1)
		smoke.Acceleration = Vector3.new(0, 3, 0)
		smoke.Parent = emitterPart
	end

	-- ===================== CROWD + FLOODLIGHTS =====================
	-- Seated on the real turf (raycast, like the rest of the decor) and tiered
	-- upward, so the stands fill with fans without floating.
	local SKIN = {
		Color3.fromRGB(255, 224, 189),
		Color3.fromRGB(241, 194, 125),
		Color3.fromRGB(198, 134, 90),
		Color3.fromRGB(141, 85, 55),
		Color3.fromRGB(94, 58, 37),
	}
	local crowdRng = Random.new()
	local function fan(pos: Vector3)
		-- Per-fan variance (facing, height, jitter) so the stands don't look like a
		-- perfect grid of identical figures.
		local rot = CFrame.Angles(0, crowdRng:NextNumber(-0.7, 0.7), 0)
		local h = crowdRng:NextNumber(0.84, 1.14)
		local jitter =
			Vector3.new(crowdRng:NextNumber(-0.3, 0.3), 0, crowdRng:NextNumber(-0.3, 0.3))
		local body = part(
			folder,
			Vector3.new(1.4, 1.9 * h, 0.9),
			CFrame.new(pos + jitter) * rot,
			NATIONS[crowdRng:NextInteger(1, #NATIONS)],
			Enum.Material.SmoothPlastic
		)
		body.CanQuery = false
		local head = part(
			folder,
			Vector3.new(0.95, 0.95, 0.95),
			CFrame.new(pos + jitter + Vector3.new(0, 0.95 * h + 0.5, 0)) * rot,
			SKIN[crowdRng:NextInteger(1, #SKIN)],
			Enum.Material.SmoothPlastic
		)
		head.Shape = Enum.PartType.Ball
		head.CanQuery = false
	end

	local goalXZ0 = Vector3.new(g.goal.X, 0, g.goal.Z)
	local crowdMesh = Assets.template(Config.Models.Crowd)
	if crowdMesh then
		-- Mesh crowd: tile section models around the stands (cheap vs. per-fan), two
		-- tiers, each facing the pitch centre.
		local centre = Vector3.new(goalXZ0.X, g.standY, goalXZ0.Z) - g.dir * halfLen
		local secW = 12
		local function place(p: Vector3)
			Assets.place(
				folder,
				Config.Models.Crowd,
				CFrame.lookAt(p, Vector3.new(centre.X, p.Y, centre.Z)),
				6
			)
		end
		local function line(start: Vector3, step: Vector3, count: number)
			for k = 0, count do
				local xz = start + step * k
				local gy = math.min(ground(Vector3.new(xz.X, 0, xz.Z), 0).Y, g.standY + 2)
				place(Vector3.new(xz.X, gy + 0.5, xz.Z))
				place(Vector3.new(xz.X, gy + 4.5, xz.Z))
			end
		end
		local widthCount = math.clamp(math.floor((2 * pitchHalf) / secW), 2, 20)
		local lenCount = math.clamp(math.floor((2 * halfLen) / secW), 2, 26)
		line(goalXZ0 + g.dir * 9 - g.right * pitchHalf, g.right * secW, widthCount) -- behind near goal
		line(goalXZ0 - g.dir * (2 * halfLen + 7) - g.right * pitchHalf, g.right * secW, widthCount) -- far goal
		line(goalXZ0 - g.right * (pitchHalf + 10), -g.dir * secW, lenCount) -- left touchline
		line(goalXZ0 + g.right * (pitchHalf + 10), -g.dir * secW, lenCount) -- right touchline
	else
		-- Blocky-fan fallback: fill fans onto the REAL stand surfaces on all four
		-- sides. At each grid point we raycast and place a fan ONLY where the ground
		-- is raised (an actual stand deck/tier -- the stands here rise 20-40 studs),
		-- skipping flat turf and the empty baseplate beyond the stands. This climbs
		-- the crowd up the stands and across the whole bowl instead of bunching them
		-- in a thin strip at the touchline.
		local STEP = 4.5
		local FLOOR = 7 -- min ground height (studs) to count as a stand; turf is ~2-3
		local function fan_if_stand(xz: Vector3)
			local gy = ground(Vector3.new(xz.X, 0, xz.Z), 0).Y
			if gy > FLOOR then
				fan(Vector3.new(xz.X, gy + 1.1, xz.Z))
			end
		end
		-- Long sides (touchlines): sweep outward across the stand depth + along it.
		for _, side in { -1, 1 } do
			local d = pitchHalf + 2
			while d <= pitchHalf + 80 do
				local a = -(halfLen + 20)
				while a <= halfLen + 20 do
					fan_if_stand(goalXZ0 + g.right * (d * side) - g.dir * a)
					a += STEP
				end
				d += STEP
			end
		end
		-- Behind both goals.
		local farLine = goalXZ0 - g.dir * (2 * halfLen)
		for _, endCfg in { { base = goalXZ0, out = g.dir }, { base = farLine, out = -g.dir } } do
			local d = 8
			while d <= 72 do
				local a = -(pitchHalf + 20)
				while a <= pitchHalf + 20 do
					fan_if_stand(endCfg.base + endCfg.out * d + g.right * a)
					a += STEP
				end
				d += STEP
			end
		end
	end

	-- A subtle World Cup crest painted on the centre circle (a gold ring + emblem,
	-- flat on the pitch -- no image asset needed).
	do
		-- sit flush on the turf (the SurfaceGui is on the Top face): a thin slab with its top a hair
		-- above the grass, so the crest reads as painted on the pitch -- not floating above it.
		local crestPos = ground(goalXZ0 - g.dir * halfLen, 0.03)
		local crestPart = part(
			folder,
			Vector3.new(18, 0.1, 18),
			CFrame.new(crestPos),
			Color3.fromRGB(255, 255, 255),
			Enum.Material.SmoothPlastic
		)
		crestPart.Transparency = 1
		crestPart.Name = "MidfieldCrest"
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Top
		sg.CanvasSize = Vector2.new(400, 400)
		sg.Parent = crestPart
		local ring = Instance.new("Frame")
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundTransparency = 1
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = ring
		local rs = Instance.new("UIStroke")
		rs.Color = Color3.fromRGB(255, 210, 90)
		rs.Thickness = 8
		rs.Transparency = 0.15
		rs.Parent = ring
		ring.Parent = sg
		local logo = Config.Icons.WorldCupLogo
		if logo and logo ~= "" then
			-- the real World Cup logo painted in the centre circle
			local emblem = Instance.new("ImageLabel")
			emblem.Size = UDim2.fromScale(0.74, 0.74)
			emblem.Position = UDim2.fromScale(0.13, 0.13)
			emblem.BackgroundTransparency = 1
			emblem.ScaleType = Enum.ScaleType.Fit
			emblem.Image = logo
			emblem.Parent = sg
		else
			local emblem = Instance.new("TextLabel")
			emblem.Size = UDim2.fromScale(0.7, 0.7)
			emblem.Position = UDim2.fromScale(0.15, 0.15)
			emblem.BackgroundTransparency = 1
			emblem.Font = Enum.Font.GothamBlack
			emblem.TextScaled = true
			emblem.TextColor3 = Color3.fromRGB(255, 215, 100)
			emblem.Text = "🏆\n2026"
			emblem.Parent = sg
		end
	end

	-- Floodlight pylons down both touchlines. In daylight they're mostly structural
	-- (a faint warm glow), so they don't blow out the exposure.
	local pitchCenter = Vector3.new(g.goal.X, g.standY, g.goal.Z) - g.dir * halfLen -- true centre
	local function floodlight(corner: Vector3)
		local foot = ground(Vector3.new(corner.X, 0, corner.Z), 0)
		local poleH = 26
		part(
			folder,
			Vector3.new(1.3, poleH, 1.3),
			CFrame.new(foot + Vector3.new(0, poleH / 2, 0)),
			Color3.fromRGB(55, 60, 70),
			Enum.Material.Metal
		)
		local bankPos = foot + Vector3.new(0, poleH, 0)
		local bank = part(
			folder,
			Vector3.new(7, 2.4, 1.2),
			CFrame.lookAt(bankPos, pitchCenter),
			Color3.fromRGB(255, 255, 245),
			Enum.Material.Neon
		)
		bank.CanQuery = false
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 90
		light.Brightness = 0.5
		light.Range = 35
		light.Color = Color3.fromRGB(255, 250, 235)
		light.Parent = bank
	end
	local sideX2 = pitchHalf + 6
	local goalXZ = Vector3.new(g.goal.X, g.standY, g.goal.Z)
	for _, side in { -1, 1 } do
		floodlight(goalXZ - g.dir * 4 + g.right * (sideX2 * side)) -- goal end
		floodlight(goalXZ - g.dir * halfLen + g.right * (sideX2 * side)) -- midfield
		floodlight(goalXZ - g.dir * (2 * halfLen - 4) + g.right * (sideX2 * side)) -- far end
	end
end

-- ============================ CELEBRATIONS ============================

local function firework(at: Vector3, color: Color3)
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
	emitter.Lifetime = NumberRange.new(1.2, 1.8)
	emitter.Speed = NumberRange.new(20, 34)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Size = NumberSequence.new(0.6)
	emitter.Rate = 0
	emitter.LightEmission = 0.6
	emitter.Parent = att
	emitter:Emit(80)
	Debris:AddItem(fx, 2.5)
end

-- A single firework above the goal -- fired on every goal (server-side so it's
-- synced for all players).
function Decor.goalBurst()
	local g = geo()
	if not g then
		return
	end
	firework(g.goal + Vector3.new(0, g.goal.Y + 8, 0), NATIONS[math.random(1, #NATIONS)])
end

-- A volley of fireworks above the goal + a trophy that rises in front of the winner.
function Decor.celebrate(winner: Player)
	local g = geo()
	if not g then
		return
	end

	task.spawn(function()
		for _ = 1, 6 do
			local jitter = g.right * math.random(-12, 12) + Vector3.new(0, math.random(0, 6), 0)
			firework(
				g.goal + Vector3.new(0, g.goal.Y + 12, 0) + jitter,
				NATIONS[math.random(1, #NATIONS)]
			)
			task.wait(0.35)
		end
	end)

	-- Confetti raining down over the penalty area.
	local rainPart = Instance.new("Part")
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(40, 1, 30)
	rainPart.CFrame = CFrame.new(g.ball - g.dir * 6 + Vector3.new(0, g.goal.Y + 26, 0))
	rainPart.Parent = workspace
	local rain = Instance.new("ParticleEmitter")
	rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rain.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, NATIONS[1]),
		ColorSequenceKeypoint.new(0.5, NATIONS[2]),
		ColorSequenceKeypoint.new(1, NATIONS[3]),
	})
	rain.Lifetime = NumberRange.new(3, 4.5)
	rain.Rate = 120
	rain.Speed = NumberRange.new(2, 6)
	rain.SpreadAngle = Vector2.new(40, 40)
	rain.Acceleration = Vector3.new(0, -10, 0)
	rain.Rotation = NumberRange.new(0, 360)
	rain.RotSpeed = NumberRange.new(-200, 200)
	rain.Size = NumberSequence.new(0.5)
	rain.Parent = rainPart
	task.delay(4.5, function()
		rain.Enabled = false
	end)
	Debris:AddItem(rainPart, 9)

	local character = winner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	-- Use the placed World Cup Trophy if present, else a simple gold pillar.
	local trophy: Instance
	local source = workspace:FindFirstChild("World Cup Trophy")
	if source and source:IsA("Model") then
		trophy = source:Clone()
		for _, d in trophy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
	else
		local pillar = Instance.new("Part")
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.Size = Vector3.new(2, 5, 2)
		pillar.Color = Color3.fromRGB(235, 200, 70)
		pillar.Material = Enum.Material.Metal
		trophy = pillar
	end

	local inFront = root.Position + root.CFrame.LookVector * 4
	local lowCFrame = CFrame.new(inFront - Vector3.new(0, 1, 0))
	local highCFrame = CFrame.new(inFront + Vector3.new(0, 3, 0))
	if trophy:IsA("Model") then
		trophy:PivotTo(lowCFrame)
	elseif trophy:IsA("BasePart") then
		trophy.CFrame = lowCFrame
	end
	trophy.Parent = workspace

	local riser = Instance.new("CFrameValue")
	riser.Value = lowCFrame
	local conn = riser:GetPropertyChangedSignal("Value"):Connect(function()
		if trophy:IsA("Model") then
			trophy:PivotTo(riser.Value)
		elseif trophy:IsA("BasePart") then
			trophy.CFrame = riser.Value
		end
	end)
	local tween = TweenService:Create(
		riser,
		TweenInfo.new(1.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = highCFrame }
	)
	tween:Play()
	tween.Completed:Connect(function()
		conn:Disconnect()
		riser:Destroy()
	end)
	Debris:AddItem(trophy, 6)
end

return Decor
