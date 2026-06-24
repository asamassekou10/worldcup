--!strict
-- WatchPartyService: big-screen live schedule + social watch zone in the plaza.
-- Creates a WatchScreen Part (SurfaceGui with today's fixtures and fan count) and
-- a WatchZone Part (invisible gathering area). The fan count updates every
-- POLL_SECONDS; the fixture list rebuilds if the date changes (past midnight).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldCup = require(Shared:WaitForChild("WorldCup"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))

local WatchPartyService = {}

local SCREEN_W      = 20  -- studs
local SCREEN_H      = 12  -- studs
local ZONE_RADIUS   = 20  -- studs from zone centre to count as "watching"
local POLL_SECONDS    = 6
local REFRESH_SECONDS = 60

-- Placement: 40 studs to the right sideline from the pitch Centre marker
-- (-62.2, 5.4, -25.7), perpendicular to the pitch axis.
local SCREEN_POS = Vector3.new(-41.9, 8.4, -60.2)
local ZONE_POS   = Vector3.new(-49.5, 3.0, -47.3)

local screenPart: BasePart?
local countLabel: TextLabel?
local lastCount = -1
local lastDate  = ""

local function buildGui(part: BasePart)
	for _, c in part:GetChildren() do
		if c:IsA("SurfaceGui") then
			c:Destroy()
		end
	end

	local sg = Instance.new("SurfaceGui")
	sg.Name          = "WatchScreen"
	sg.Face          = Enum.NormalId.Front
	sg.SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 48
	sg.Parent        = part

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(6, 12, 24)
	bg.BorderSizePixel  = 0
	bg.Parent           = sg

	-- Green title bar
	local topBar = Instance.new("Frame")
	topBar.Size             = UDim2.fromScale(1, 0.11)
	topBar.BackgroundColor3 = Color3.fromRGB(22, 90, 38)
	topBar.BorderSizePixel  = 0
	topBar.Parent           = bg

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size                 = UDim2.fromScale(1, 1)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font                 = Enum.Font.GothamBold
	titleLbl.TextScaled           = true
	titleLbl.TextColor3           = Color3.fromRGB(255, 255, 255)
	titleLbl.Text                 = "⚽  WORLD CUP 2026"
	titleLbl.Parent               = topBar

	-- Fixture list area (78% of height)
	local listFrame = Instance.new("Frame")
	listFrame.Name                   = "FixtureList"
	listFrame.Size                   = UDim2.fromScale(1, 0.78)
	listFrame.Position               = UDim2.fromScale(0, 0.11)
	listFrame.BackgroundTransparency = 1
	listFrame.Parent                 = bg

	-- Fan count bar at bottom
	local botBar = Instance.new("Frame")
	botBar.Size             = UDim2.fromScale(1, 0.11)
	botBar.Position         = UDim2.fromScale(0, 0.89)
	botBar.BackgroundColor3 = Color3.fromRGB(14, 20, 40)
	botBar.BorderSizePixel  = 0
	botBar.Parent           = bg

	local fans = Instance.new("TextLabel")
	fans.Name                   = "FansLabel"
	fans.Size                   = UDim2.fromScale(1, 1)
	fans.BackgroundTransparency = 1
	fans.Font                   = Enum.Font.Gotham
	fans.TextScaled             = true
	fans.TextColor3             = Color3.fromRGB(180, 210, 180)
	fans.Text                   = "👥 0 fans watching"
	fans.Parent                 = botBar
	countLabel = fans

	-- Fixture rows
	local today = WorldCup.todayISO()
	local fixtures = WorldCup.fixturesOn(today)
	local headerText = "TODAY  ·  " .. today
	if #fixtures == 0 then
		fixtures = WorldCup.upcoming(6)
		headerText = "COMING UP"
	end
	lastDate = today

	local hdrLbl = Instance.new("TextLabel")
	hdrLbl.Size                   = UDim2.fromScale(1, 0.11)
	hdrLbl.Position               = UDim2.fromScale(0, 0.01)
	hdrLbl.BackgroundTransparency = 1
	hdrLbl.Font                   = Enum.Font.GothamBold
	hdrLbl.TextScaled             = true
	hdrLbl.TextColor3             = Color3.fromRGB(140, 210, 140)
	hdrLbl.Text                   = headerText
	hdrLbl.Parent                 = listFrame

	local maxRows = math.min(#fixtures, 6)
	for i = 1, maxRows do
		local f = fixtures[i]

		local row = Instance.new("Frame")
		row.Size             = UDim2.fromScale(0.98, 0.13)
		row.Position         = UDim2.fromScale(0.01, 0.13 + (i - 1) * 0.137)
		row.BackgroundColor3 = if i % 2 == 0
			then Color3.fromRGB(12, 18, 36)
			else Color3.fromRGB(18, 26, 50)
		row.BorderSizePixel  = 0
		row.Parent           = listFrame

		local matchLbl = Instance.new("TextLabel")
		matchLbl.Size                   = UDim2.fromScale(0.73, 1)
		matchLbl.BackgroundTransparency = 1
		matchLbl.Font                   = Enum.Font.Gotham
		matchLbl.TextScaled             = true
		matchLbl.TextXAlignment         = Enum.TextXAlignment.Left
		matchLbl.TextColor3             = Color3.fromRGB(240, 240, 255)
		matchLbl.Text                   = "  " .. WorldCup.sideLabel(f.home)
			.. "  vs  " .. WorldCup.sideLabel(f.away)
		matchLbl.Parent                 = row

		local cityLbl = Instance.new("TextLabel")
		cityLbl.Size                   = UDim2.fromScale(0.27, 1)
		cityLbl.Position               = UDim2.fromScale(0.73, 0)
		cityLbl.BackgroundTransparency = 1
		cityLbl.Font                   = Enum.Font.Gotham
		cityLbl.TextScaled             = true
		cityLbl.TextXAlignment         = Enum.TextXAlignment.Right
		cityLbl.TextColor3             = Color3.fromRGB(140, 170, 200)
		cityLbl.Text                   = f.city .. "  "
		cityLbl.Parent                 = row
	end

	if maxRows == 0 then
		local noMatch = Instance.new("TextLabel")
		noMatch.Size                   = UDim2.fromScale(1, 0.8)
		noMatch.Position               = UDim2.fromScale(0, 0.12)
		noMatch.BackgroundTransparency = 1
		noMatch.Font                   = Enum.Font.Gotham
		noMatch.TextScaled             = true
		noMatch.TextColor3             = Color3.fromRGB(160, 160, 160)
		noMatch.Text                   = "No upcoming matches"
		noMatch.Parent                 = listFrame
	end
end

local function build()
	-- Position from the shared MapLayout (activities row, far touchline). The screen
	-- sits at the touchline edge; the watch zone sits in front of it toward the pitch.
	local acf = MapLayout.activity("watch")
	local screenXZ: Vector3, zoneXZ: Vector3
	if acf then
		local p = acf.Position
		local fwd = acf.LookVector -- horizontal, toward the pitch
		screenXZ = Vector3.new(p.X, 0, p.Z)
		zoneXZ   = screenXZ + Vector3.new(fwd.X, 0, fwd.Z).Unit * 10
	else
		screenXZ = Vector3.new(SCREEN_POS.X, 0, SCREEN_POS.Z)
		zoneXZ   = Vector3.new(ZONE_POS.X, 0, ZONE_POS.Z)
	end

	-- Ground the screen on support poles so it reads as a mounted jumbotron instead
	-- of a floating panel. Face the zone using a same-height target so it stays
	-- perfectly upright (a full 3D lookAt to the lower zone tilted it forward).
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(screenXZ + Vector3.new(0, 80, 0), Vector3.new(0, -400, 0), rp)
	local groundY = if hit then hit.Position.Y else 2.4
	local BASE_CLEAR = 2.5 -- gap from the ground to the screen's bottom edge
	local centreY = groundY + BASE_CLEAR + SCREEN_H / 2
	local centre = Vector3.new(screenXZ.X, centreY, screenXZ.Z)

	local screen = Instance.new("Part")
	screen.Name       = "WatchScreen"
	screen.Size       = Vector3.new(SCREEN_W, SCREEN_H, 0.4)
	screen.CFrame     = CFrame.lookAt(centre, Vector3.new(zoneXZ.X, centreY, zoneXZ.Z))
	screen.Anchored   = true
	screen.CanCollide = true
	screen.Material   = Enum.Material.SmoothPlastic
	screen.Color      = Color3.fromRGB(20, 20, 30)
	screen.CastShadow = false
	screen.Parent     = Workspace
	screenPart = screen

	buildGui(screen)

	-- Two support legs (screen edges) running from the ground up the sides, plus a
	-- base bar, so the board is visibly mounted.
	local screenCF = screen.CFrame
	for _, legSign in { -1, 1 } do
		local foot = centre + screenCF.RightVector * (legSign * SCREEN_W * 0.44)
			- screenCF.LookVector * 0.3
		local leg = Instance.new("Part")
		leg.Name       = "WatchScreenLeg"
		leg.Anchored   = true
		leg.CanCollide = true
		leg.Size       = Vector3.new(1.4, BASE_CLEAR + SCREEN_H, 1.4)
		leg.CFrame     = CFrame.new(Vector3.new(foot.X, groundY + (BASE_CLEAR + SCREEN_H) / 2, foot.Z))
		leg.Material   = Enum.Material.Metal
		leg.Color      = Color3.fromRGB(36, 40, 50)
		leg.CastShadow = false
		leg.Parent     = Workspace
	end

	local zone = Instance.new("Part")
	zone.Name         = "WatchZone"
	zone.Size         = Vector3.new(22, 5, 16)
	zone.CFrame       = CFrame.new(Vector3.new(zoneXZ.X, groundY + 2.5, zoneXZ.Z))
	zone.Anchored     = true
	zone.CanCollide   = false
	zone.CanQuery     = false -- invisible trigger: raycasts (e.g. decor grounding) pass through
	zone.Transparency = 1
	zone.CastShadow   = false
	zone.Parent       = Workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Hang Out"
	prompt.ObjectText            = "⚽ Watch Party"
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration          = 0
	prompt.Parent                = zone
end

local function pollZone()
	local zone = Workspace:FindFirstChild("WatchZone") :: BasePart?
	if not zone then return end
	local centre = zone.Position

	local count = 0
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - centre).Magnitude <= ZONE_RADIUS then
			count += 1
		end
	end

	if count == lastCount then return end
	lastCount = count

	local lbl = countLabel
	if lbl and lbl.Parent then
		lbl.Text = "👥 " .. count
			.. (if count == 1 then " fan watching" else " fans watching")
	end
end

function WatchPartyService.start()
	local existing = Workspace:FindFirstChild("WatchScreen") :: BasePart?
	if existing then
		screenPart = existing
		local sg = existing:FindFirstChildOfClass("SurfaceGui")
		countLabel = if sg
			then sg:FindFirstChild("FansLabel", true) :: TextLabel?
			else nil
		if not countLabel then
			buildGui(existing)
		end
	else
		build()
	end

	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			pollZone()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			local today = WorldCup.todayISO()
			if today ~= lastDate then
				local part = screenPart
				if part and part.Parent then
					buildGui(part)
				end
			end
		end
	end)
end

return WatchPartyService
