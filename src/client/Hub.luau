--!strict
-- Hub: client reactions to the plaza activity props (built by HubService). Photo
-- booth -> a framed photo moment; Shop/Ranks/Store stalls -> open the HUD panels;
-- Predict kiosk -> a panel to pick today's real fixture winners. Self-contained.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WorldCup = require(Shared:WaitForChild("WorldCup"))

local Hub = {}
Hub.onPredictClose = nil :: (() -> ())? -- set by init.client to restore the lobby HUD on close

local player = Players.LocalPlayer
local predictEvent = Net.getEvent(Net.Events.Predict)
local predictRequest = Net.getEvent(Net.Events.PredictRequest)

-- crowd-consensus state, fed by PredictState (server): myPicks[key]=team, tallies[key]={home,away}
local predictMyPicks: { [string]: string } = {}
local predictTallies: { [string]: { home: number, away: number } } = {}

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

-- ===== photo booth =====

local photoScreen = Instance.new("ScreenGui")
photoScreen.Name = "PhotoOverlay"
photoScreen.ResetOnSpawn = false
photoScreen.IgnoreGuiInset = true
photoScreen.Enabled = false
photoScreen.Parent = player:WaitForChild("PlayerGui")
local photoTag = Instance.new("TextLabel")
photoTag.Size = UDim2.fromScale(0.5, 0.07)
photoTag.Position = UDim2.fromScale(0.25, 0.86)
photoTag.BackgroundTransparency = 0.2
photoTag.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
photoTag.Font = Enum.Font.GothamBlack
photoTag.TextScaled = true
photoTag.TextColor3 = Color3.fromRGB(255, 220, 90)
photoTag.Text = "📸 #PenaltyKings"
corner(photoTag, 10)
photoTag.Parent = photoScreen

local photoActive = false
local function confetti(at: Vector3)
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.Transparency = 1
	fx.Size = Vector3.one
	fx.CFrame = CFrame.new(at + Vector3.new(0, 6, 0))
	fx.Parent = Workspace
	local att = Instance.new("Attachment")
	att.Parent = fx
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(120, 200, 255))
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(3, 8)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.Size = NumberSequence.new(0.4)
	emitter.Rate = 0
	emitter.Parent = att
	emitter:Emit(60)
	Debris:AddItem(fx, 3)
end

local function photoMoment()
	if photoActive then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = Workspace.CurrentCamera
	if not root or not cam then
		return
	end
	photoActive = true
	photoScreen.Enabled = true
	confetti(root.Position)
	-- Frame the player from the front (booth/trophy behind them).
	local pos = root.Position + root.CFrame.LookVector * 9 + Vector3.new(0, 2.5, 0)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(pos, root.Position + Vector3.new(0, 1.5, 0))
	task.delay(4, function()
		photoActive = false
		photoScreen.Enabled = false
		local c = Workspace.CurrentCamera
		if c then
			c.CameraType = Enum.CameraType.Custom
		end
	end)
end

-- ===== prediction panel =====

local predictScreen = Instance.new("ScreenGui")
predictScreen.Name = "PredictPanel"
predictScreen.ResetOnSpawn = false
predictScreen.IgnoreGuiInset = true
predictScreen.DisplayOrder = 30 -- above the floating lobby banners (so it covers them when open)
predictScreen.Enabled = false
predictScreen.Parent = player:WaitForChild("PlayerGui")

local predictBg = Instance.new("Frame")
predictBg.Size = UDim2.fromScale(1, 1)
predictBg.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
predictBg.BackgroundTransparency = 0.05
predictBg.Parent = predictScreen

-- Keep content clear of the Roblox topbar (this panel ignores the GUI inset).
local predictPad = Instance.new("UIPadding")
predictPad.PaddingTop = UDim.new(0, 48)
predictPad.Parent = predictBg

local predictTitle = Instance.new("TextLabel")
predictTitle.Size = UDim2.fromScale(0.7, 0.08)
predictTitle.Position = UDim2.fromScale(0.06, 0.04)
predictTitle.BackgroundTransparency = 1
predictTitle.Font = Enum.Font.GothamBlack
predictTitle.TextScaled = true
predictTitle.TextXAlignment = Enum.TextXAlignment.Left
predictTitle.TextColor3 = Color3.fromRGB(230, 200, 255)
predictTitle.Text = "🔮 PREDICT TODAY'S WINNERS"
predictTitle.Parent = predictBg

local predictSub = Instance.new("TextLabel")
predictSub.Size = UDim2.fromScale(0.8, 0.035)
predictSub.Position = UDim2.fromScale(0.06, 0.12)
predictSub.BackgroundTransparency = 1
predictSub.Font = Enum.Font.GothamMedium
predictSub.TextScaled = true
predictSub.TextXAlignment = Enum.TextXAlignment.Left
predictSub.TextColor3 = Color3.fromRGB(180, 190, 205)
predictSub.Text =
	"Pick the winners — and see what the whole crowd thinks. +20 coins/day for picking."
predictSub.Parent = predictBg

local predictClose = Instance.new("TextButton")
predictClose.Size = UDim2.fromScale(0.1, 0.07)
predictClose.Position = UDim2.fromScale(0.84, 0.05)
predictClose.BackgroundColor3 = Color3.fromRGB(42, 47, 66)
predictClose.Font = Enum.Font.GothamBold
predictClose.TextScaled = true
predictClose.TextColor3 = Color3.fromRGB(220, 226, 236)
predictClose.Text = "✕"
corner(predictClose, 10)
predictClose.Parent = predictBg
predictClose.Activated:Connect(function()
	predictScreen.Enabled = false
	if Hub.onPredictClose then
		Hub.onPredictClose()
	end
end)

local predictList = Instance.new("ScrollingFrame")
predictList.Size = UDim2.fromScale(0.88, 0.78)
predictList.Position = UDim2.fromScale(0.06, 0.18)
predictList.BackgroundTransparency = 1
predictList.BorderSizePixel = 0
predictList.ScrollBarThickness = 6
predictList.CanvasSize = UDim2.new()
predictList.AutomaticCanvasSize = Enum.AutomaticSize.Y
predictList.Parent = predictBg
local predictLayout = Instance.new("UIListLayout")
predictLayout.Padding = UDim.new(0, 8)
predictLayout.SortOrder = Enum.SortOrder.LayoutOrder
predictLayout.Parent = predictList

local function buildPredictRows()
	for _, child in predictList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local fixtures = WorldCup.fixturesOn(WorldCup.todayISO())
	local shown = 0
	for _, f in fixtures do
		if not WorldCup.isMilestone(f) then
			shown += 1
			local key = WorldCup.fixtureKey(f)
			local mine = predictMyPicks[key]
			local tally = predictTallies[key] or { home = 0, away = 0 }
			local total = tally.home + tally.away
			local homePct = if total > 0 then math.floor(tally.home / total * 100 + 0.5) else 50
			local awayPct = 100 - homePct

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 84)
			row.LayoutOrder = shown
			row.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
			corner(row, 10)
			row.Parent = predictList

			local picks: { [string]: TextButton } = {}
			local function pickButton(nationId: string, xScale: number)
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.fromScale(0.47, 0.52)
				btn.Position = UDim2.fromScale(xScale, 0.08)
				btn.BackgroundColor3 = if mine == nationId
					then Color3.fromRGB(40, 170, 90)
					else Color3.fromRGB(40, 44, 58)
				btn.Font = Enum.Font.GothamBold
				btn.TextScaled = true
				btn.TextColor3 = Color3.fromRGB(235, 235, 235)
				btn.Text = WorldCup.sideLabel(nationId)
				corner(btn, 8)
				btn.Parent = row
				picks[nationId] = btn
				btn.Activated:Connect(function()
					for _, b in picks do
						b.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
					end
					btn.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
					predictEvent:FireServer({ key = key, pick = nationId })
				end)
			end
			pickButton(f.home, 0.02)
			pickButton(f.away, 0.51)

			-- crowd-consensus bar (the social-proof hook): home% (blue) | away% (orange)
			local barBg = Instance.new("Frame")
			barBg.Size = UDim2.fromScale(0.96, 0.26)
			barBg.Position = UDim2.fromScale(0.02, 0.68)
			barBg.BackgroundColor3 = Color3.fromRGB(235, 120, 55) -- away colour shows through the right
			barBg.BorderSizePixel = 0
			corner(barBg, 6)
			barBg.Parent = row
			local homeFill = Instance.new("Frame")
			homeFill.Size = UDim2.fromScale(homePct / 100, 1)
			homeFill.BackgroundColor3 = Color3.fromRGB(60, 130, 230)
			homeFill.BorderSizePixel = 0
			homeFill.Parent = barBg
			corner(homeFill, 6)
			local barText = Instance.new("TextLabel")
			barText.Size = UDim2.new(1, -12, 1, 0)
			barText.Position = UDim2.fromOffset(6, 0)
			barText.BackgroundTransparency = 1
			barText.Font = Enum.Font.GothamBold
			barText.TextScaled = true
			barText.ZIndex = 2
			barText.TextColor3 = Color3.fromRGB(255, 255, 255)
			barText.TextStrokeTransparency = 0.5
			barText.Text = if total > 0
				then string.format("🌍 %d%%  vs  %d%%  ·  %d picks", homePct, awayPct, total)
				else "🌍 Be the first to call it!"
			barText.Parent = barBg
		end
	end
	if shown == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.BackgroundTransparency = 1
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(140, 150, 170)
		label.Text = "No World Cup matches today — check back tomorrow!"
		label.Parent = empty
		empty.Parent = predictList
	end
end

-- crowd state from the server -> redraw bars + update the streak/record header
Net.getEvent(Net.Events.PredictState).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: {
		picks: { [string]: string }?,
		tallies: { [string]: { home: number, away: number } }?,
		stats: { wins: number, streak: number }?,
	}
	predictMyPicks = info.picks or {}
	predictTallies = info.tallies or {}
	local stats = info.stats
	if stats then
		predictSub.Text = string.format(
			"🔥 %d streak  ·  ✅ %d correct  —  pick winners, see the crowd, build your streak!",
			stats.streak,
			stats.wins
		)
	end
	if predictScreen.Enabled then
		buildPredictRows()
	end
end)

-- Open the predictor from anywhere (the MENU, the matchday nudge, the kiosk).
function Hub.openPredict()
	predictRequest:FireServer() -- pull the latest picks + crowd tallies
	buildPredictRows()
	predictScreen.Enabled = true
end

-- ===== wire prompts =====

function Hub.start(hud: { openShop: () -> (), openRanks: () -> (), openStore: () -> () })
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		local name = prompt.Name
		if name == "PhotoPrompt" then
			photoMoment()
		elseif name == "ShopPrompt" then
			hud.openShop()
		elseif name == "RanksPrompt" then
			hud.openRanks()
		elseif name == "StorePrompt" then
			hud.openStore()
		elseif name == "PredictPrompt" then
			Hub.openPredict()
		end
	end)
end

return Hub
