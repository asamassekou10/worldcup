--!strict
-- HubService: builds the plaza activity props around the pre-game lobby -- a
-- trophy photo booth, a predictions kiosk, and physical Shop/Ranks/Store stalls
-- (each with a named ProximityPrompt the client reacts to). Also records match
-- predictions. All geometry is anchored to the Ball/Keeper markers + raycast to
-- the ground, so it fits the hand-built stadium.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local HubService = {}

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

local function sign(parent: BasePart, text: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	billboard.MaxDistance = 45 -- fade out up close so they don't blast the screen
	billboard.AlwaysOnTop = false -- occlude properly + shrink with distance
	billboard.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = billboard
end

local function prompt(parent: BasePart, name: string, action: string, object: string)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
end

local function build()
	local ball, keeper = findPart("Ball"), findPart("Keeper")
	if not ball or not keeper then
		return
	end
	local existing = workspace:FindFirstChild("HubProps")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "HubProps"
	folder.Parent = workspace

	local flat =
		Vector3.new(keeper.Position.X - ball.Position.X, 0, keeper.Position.Z - ball.Position.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	local dir = flat.Unit -- ball -> goal
	local right = dir:Cross(Vector3.yAxis)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { folder }
	local function ground(xz: Vector3): Vector3
		local origin = Vector3.new(xz.X, ball.Position.Y + 80, xz.Z)
		local hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), rayParams)
		local y = if hit then hit.Position.Y else ball.Position.Y - 0.8
		return Vector3.new(xz.X, y, xz.Z)
	end
	-- Field length from the optional "Center" marker (goal -> halfway), so the hub
	-- scales to the real pitch. Falls back to an estimate until it's placed.
	local goalXZ = Vector3.new(keeper.Position.X, ball.Position.Y, keeper.Position.Z)
	local center = findPart("Center")
	local halfLen = 30
	if center then
		halfLen = Vector3.new(
			center.Position.X - keeper.Position.X,
			0,
			center.Position.Z - keeper.Position.Z
		)
			:Dot(-dir)
	end
	-- A spot at field fraction `frac` from the goal (1 = midfield) and `side` across.
	local function atFrac(frac: number, side: number): Vector3
		return goalXZ - dir * (frac * halfLen) + right * side
	end
	-- A plaza-slot anchor from the shared MapLayout -> a grounded CFrame (facing the
	-- pitch). Falls back to the goal area if the layout can't resolve the markers.
	local function plazaCF(slot: string): CFrame
		return MapLayout.plaza(slot) or CFrame.new(goalXZ)
	end

	-- Same, for the activities row on the far (-side) touchline.
	local function activityCF(slot: string): CFrame
		return MapLayout.activity(slot) or CFrame.new(goalXZ)
	end

	-- ---- a stand at a plaza anchor: a mesh model if it loads, else a built counter ----
	local function stall(
		anchor: CFrame,
		modelId: number,
		label: string,
		name: string,
		action: string,
		color: Color3
	)
		local base = ground(Vector3.new(anchor.Position.X, 0, anchor.Position.Z))
		local rot = anchor.Rotation
		local anchorPart: BasePart? = nil
		local placed = Assets.place(folder, modelId, CFrame.new(base) * rot, 6)
		if placed then
			anchorPart = Assets.anchor(placed)
		end
		if not anchorPart then
			-- Fallback built counter.
			anchorPart = part(
				folder,
				Vector3.new(5, 3, 1.6),
				CFrame.new(base + Vector3.new(0, 1.5, 0)) * rot,
				color,
				Enum.Material.SmoothPlastic
			)
			part(
				folder,
				Vector3.new(5.6, 0.4, 2.2),
				CFrame.new(base + Vector3.new(0, 3.1, 0)) * rot,
				Color3.fromRGB(245, 245, 245),
				Enum.Material.SmoothPlastic
			)
		end
		sign(anchorPart :: BasePart, label, Color3.fromRGB(255, 255, 255))
		prompt(anchorPart :: BasePart, name, action, "")
	end

	-- Shop / Ranks / Store stands in a tidy row down the plaza touchline (positions
	-- come from the shared MapLayout so the whole map stays coherent).
	stall(
		plazaCF("shop"),
		Config.Models.StandShop,
		"🛒 SHOP",
		"ShopPrompt",
		"Open Shop",
		Color3.fromRGB(46, 110, 70)
	)
	stall(
		plazaCF("ranks"),
		Config.Models.StandRanks,
		"🏆 RANKS",
		"RanksPrompt",
		"Open Ranks",
		Color3.fromRGB(60, 70, 110)
	)
	stall(
		plazaCF("store"),
		Config.Models.StandStore,
		"💎 STORE",
		"StorePrompt",
		"Open Store",
		Color3.fromRGB(110, 70, 130)
	)

	-- The ice-cream cart is a FREE TREAT stand on the activities (-side) row: walk up
	-- for a quick scoop (a few coins + a short 2x XP boost, on a per-player cooldown)
	-- -- a fun little freebie to come back for between matches.
	do
		local acf = activityCF("icecream")
		local base = ground(Vector3.new(acf.Position.X, 0, acf.Position.Z))
		local placed =
			Assets.place(folder, Config.Models.StandDeco, CFrame.new(base) * acf.Rotation, 6)
		local anchorPart: BasePart? = if placed then Assets.anchor(placed) else nil
		if anchorPart then
			sign(anchorPart, "🍦 FREE TREAT", Color3.fromRGB(255, 225, 245))
			prompt(anchorPart, "TreatPrompt", "Grab a treat", "🍦 Ice Cream Cart")
			local tp = anchorPart:FindFirstChild("TreatPrompt")
			if tp and tp:IsA("ProximityPrompt") then
				tp.Triggered:Connect(function(player: Player)
					DataService.claimTreat(player)
				end)
			end
		end
	end

	-- Predictions booth on the activities (-side) row: a referee mans the desk.
	do
		local acf = activityCF("predict")
		local base = ground(Vector3.new(acf.Position.X, 0, acf.Position.Z))
		Assets.place(folder, Config.Models.PredictKiosk, CFrame.new(base) * acf.Rotation, 5.6)
		-- A small desk in front of the ref to hold the prompt + sign.
		local desk = part(
			folder,
			Vector3.new(4, 3, 1.4),
			CFrame.new(base + Vector3.new(0, 1.5, 0)) * acf.Rotation * CFrame.new(0, 0, -2),
			Color3.fromRGB(40, 60, 110),
			Enum.Material.SmoothPlastic
		)
		sign(desk, "🔮 PREDICT", Color3.fromRGB(230, 200, 255))
		prompt(desk, "PredictPrompt", "Predict Matches", "🔮 Match Predictor")
	end

	-- Trophy photo booth REMOVED — the Warm-Up treadmills sit at this plaza spot now
	-- (placed by TriviaParkourService). The old build is gated off below.
	local SHOW_PHOTO_BOOTH = false
	if SHOW_PHOTO_BOOTH then
		local base =
			ground(Vector3.new(plazaCF("photo").Position.X, 0, plazaCF("photo").Position.Z))
		local pedestal = part(
			folder,
			Vector3.new(3.4, 2, 3.4),
			CFrame.new(base + Vector3.new(0, 1, 0)),
			Color3.fromRGB(40, 42, 52),
			Enum.Material.Marble
		)
		pedestal.Shape = Enum.PartType.Cylinder
		pedestal.CFrame = CFrame.new(base + Vector3.new(0, 1, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		local topY = base.Y + 2

		-- Collect EVERY World Cup trophy already in the Workspace -- the user's own model
		-- plus any copies accidentally saved into the place on earlier runs -- keep ONE
		-- and destroy the rest, so no stray trophy is ever left out on the pitch.
		local placedTrophy: Instance? = nil
		local trophies: { Model } = {}
		for _, d in workspace:GetDescendants() do
			if
				d:IsA("Model")
				and (d.Name == "World Cup Trophy" or d.Name == "PhotoTrophy")
				and not d:IsDescendantOf(folder)
			then
				table.insert(trophies, d)
			end
		end
		local keep = trophies[1]
		for i = 2, #trophies do
			trophies[i]:Destroy()
		end
		if keep then
			for _, d in keep:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			local _, sz = keep:GetBoundingBox()
			if sz.Y > 0.1 then
				pcall(function()
					keep:ScaleTo(keep:GetScale() * (5 / sz.Y))
				end)
			end
			-- Sit the trophy's BASE on the pedestal top, correcting for its pivot offset
			-- (its pivot is NOT its centre -- that's why it floated before).
			local boxCF, scaled = keep:GetBoundingBox()
			local pivotOffset = keep:GetPivot().Position - boxCF.Position
			local boxCentre = Vector3.new(base.X, base.Y + 2 + scaled.Y / 2, base.Z)
			keep:PivotTo(CFrame.new(boxCentre + pivotOffset))
			placedTrophy = keep
		else
			-- No model in the Workspace: place the trophy asset directly on the pedestal.
			placedTrophy = Assets.place(
				folder,
				Config.Models.Trophy,
				CFrame.new(base + Vector3.new(0, 2, 0)),
				5
			)
		end
		if not placedTrophy then
			-- Fallback if neither is available: a simple built trophy.
			local GOLD = Color3.fromRGB(240, 200, 70)
			local cup = part(
				folder,
				Vector3.new(2.2, 2.4, 2.2),
				CFrame.new(base + Vector3.new(0, 4, 0)),
				GOLD,
				Enum.Material.Neon
			)
			cup.Shape = Enum.PartType.Ball
			part(
				folder,
				Vector3.new(0.5, 1.2, 0.5),
				CFrame.new(base + Vector3.new(0, 3, 0)),
				GOLD,
				Enum.Material.Neon
			)
		end

		local signPart = part(
			folder,
			Vector3.new(1, 1, 1),
			CFrame.new(base + Vector3.new(0, topY, 0)),
			Color3.fromRGB(255, 255, 255),
			Enum.Material.SmoothPlastic
		)
		signPart.Transparency = 1
		sign(signPart, "📸 PHOTO BOOTH", Color3.fromRGB(255, 230, 140))
		prompt(pedestal, "PhotoPrompt", "Pose for a photo", "🏆 World Cup Trophy")
	end

	-- Free-roam kickabout: a few loose balls around midfield to knock about while
	-- waiting. Physics-driven; a touch kicks them; they reset if they drift off.
	-- Uses the mesh ball if it's a single part, else a plain sphere.
	local ballTemplate = Assets.template(Config.Models.Ball)
	for i = 1, 4 do
		-- Spread along the field + alternating sides so they're not on the spawn.
		local frac = 0.65 + (i - 1) * 0.22
		local side = (if i % 2 == 0 then 1 else -1) * 14
		local home = ground(atFrac(frac, side)) + Vector3.new(0, 2, 0)
		local b: BasePart
		if ballTemplate and ballTemplate:IsA("BasePart") then
			b = (ballTemplate :: BasePart):Clone()
			b.Size = b.Size * (2 / math.max(b.Size.Y, 0.1)) -- ~2 studs across
		else
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(2, 2, 2)
			p.Color = Color3.fromRGB(245, 245, 245)
			p.Material = Enum.Material.SmoothPlastic
			b = p
		end
		b.Name = "KickaboutBall"
		b.Position = home
		b.Anchored = false
		b.CanCollide = true
		b.CanQuery = true
		b.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.4, 0.55)
		b.Parent = folder
		local lastKick = 0
		b.Touched:Connect(function(hit: BasePart)
			local char = hit.Parent
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not humanoid or not root then
				return
			end
			local now = os.clock()
			if now - lastKick < 0.25 then
				return
			end
			lastKick = now
			local push = b.Position - root.Position
			push = Vector3.new(push.X, 0, push.Z)
			if push.Magnitude > 0.1 then
				b.AssemblyLinearVelocity = push.Unit * 34 + Vector3.new(0, 10, 0)
			end
		end)
		task.spawn(function()
			while b.Parent do
				task.wait(3)
				-- Keep each ball in its midfield zone (and off the spawn).
				if b.Position.Y < home.Y - 25 or (b.Position - home).Magnitude > 55 then
					b.AssemblyLinearVelocity = Vector3.zero
					b.AssemblyAngularVelocity = Vector3.zero
					b.CFrame = CFrame.new(home)
				end
			end
		end)
	end
end

function HubService.start()
	task.spawn(function()
		for _ = 1, 30 do
			if findPart("Ball") and findPart("Keeper") then
				build()
				return
			end
			task.wait(1)
		end
	end)

	-- (Predict picks are handled by PredictService, which also tracks the crowd-consensus tally.)
end

return HubService
