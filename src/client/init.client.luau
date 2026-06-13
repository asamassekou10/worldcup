--!strict
-- Client bootstrap (Slice 2: PvP). Owns no game logic -- it wires the HUD to
-- the matchmaking remotes and renders whatever the server sends back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

-- ===== Branded loading screen (shown immediately, faded out once ready) =====
local function buildLoadingScreen(): ScreenGui
	local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
	local gui = Instance.new("ScreenGui")
	gui.Name = "PenaltyKingsLoading"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ResetOnSpawn = false
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Theme.Bg
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(22, 30, 46), Theme.Bg)
	grad.Rotation = 90
	grad.Parent = bg
	local logo = Instance.new("TextLabel")
	logo.Size = UDim2.fromScale(0.7, 0.14)
	logo.Position = UDim2.fromScale(0.15, 0.4)
	logo.BackgroundTransparency = 1
	logo.Font = Theme.FontTitle
	logo.TextScaled = true
	logo.TextColor3 = Color3.fromRGB(255, 255, 255)
	logo.Text = "⚽ PENALTY KINGS 👑"
	logo.Parent = bg
	local lg = Instance.new("UIGradient")
	lg.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), Theme.Gold)
	lg.Rotation = 90
	lg.Parent = logo
	local loading = Instance.new("TextLabel")
	loading.Size = UDim2.fromScale(0.5, 0.04)
	loading.Position = UDim2.fromScale(0.25, 0.56)
	loading.BackgroundTransparency = 1
	loading.Font = Theme.FontBody
	loading.TextScaled = true
	loading.TextColor3 = Theme.Subtext
	loading.Text = "Loading the stadium…"
	loading.Parent = bg
	gui.Parent = player:WaitForChild("PlayerGui")
	-- Gentle pulse on the loading text.
	TweenService:Create(
		loading,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ TextTransparency = 0.5 }
	):Play()
	return gui
end
local loadingScreen = buildLoadingScreen()
Debris:AddItem(loadingScreen, 12) -- hard safety: never let it get stuck on screen

-- A subtle cinematic vignette (edge gradients -> no asset needed). Sits behind the
-- HUD; Frames don't capture input, so it never blocks gameplay.
local function buildVignette()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Vignette"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1
	gui.ResetOnSpawn = false
	local function edge(size: UDim2, pos: UDim2, rotation: number, fadeIn: boolean)
		local f = Instance.new("Frame")
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		f.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		local a, b = 0.45, 1 -- edge opacity -> transparent toward centre
		g.Transparency = if fadeIn then NumberSequence.new(a, b) else NumberSequence.new(b, a)
		g.Parent = f
		f.Parent = gui
	end
	edge(UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0), 90, true) -- top
	edge(UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0.84), 90, false) -- bottom
	edge(UDim2.fromScale(0.12, 1), UDim2.fromScale(0, 0), 0, true) -- left
	edge(UDim2.fromScale(0.12, 1), UDim2.fromScale(0.88, 0), 0, false) -- right
	gui.Parent = player:WaitForChild("PlayerGui")
end
buildVignette()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))

local UI = require(script:WaitForChild("UI"))
local ShotAnimator = require(script:WaitForChild("ShotAnimator"))
local DecorFX = require(script:WaitForChild("DecorFX"))
local Sound = require(script:WaitForChild("Sound"))
local Camera = require(script:WaitForChild("Camera"))
local Warmup = require(script:WaitForChild("Warmup"))
local Hub = require(script:WaitForChild("Hub"))

local hud = UI.create(player)

local joinQueue = Net.getEvent(Net.Events.JoinQueue)
local leaveQueue = Net.getEvent(Net.Events.LeaveQueue)
local submitInput = Net.getEvent(Net.Events.SubmitInput)
local buyCosmetic = Net.getEvent(Net.Events.BuyCosmetic)
local equipCosmetic = Net.getEvent(Net.Events.EquipCosmetic)
local challengePlayer = Net.getEvent(Net.Events.ChallengePlayer)
local challengeRespond = Net.getEvent(Net.Events.ChallengeRespond)
local emote = Net.getEvent(Net.Events.Emote)

local inQueue = false

hud.onQueueButton = function()
	if inQueue then
		leaveQueue:FireServer()
	else
		joinQueue:FireServer()
	end
end

hud.onSubmit = function()
	submitInput:FireServer(hud.getInput())
end

hud.onBackToLobby = function()
	hud.showLobby()
end

hud.onBuy = function(id: string)
	buyCosmetic:FireServer({ id = id })
end

hud.onEquip = function(id: string)
	equipCosmetic:FireServer({ id = id })
end

hud.onChallenge = function(targetUserId: number)
	challengePlayer:FireServer({ targetUserId = targetUserId })
end

hud.onChallengeRespond = function(fromUserId: number, accept: boolean)
	challengeRespond:FireServer({ fromUserId = fromUserId, accept = accept })
end

hud.onEmote = function(emoji: string)
	emote:FireServer({ emoji = emoji })
end

-- Pop a broadcast emote above the sender's head (floats up + fades).
local function showEmote(userId: number, emoji: string)
	local from = Players:GetPlayerByUserId(userId)
	local character = from and from.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = emoji
	label.Parent = bb
	TweenService:Create(bb, TweenInfo.new(1.2), { StudsOffset = Vector3.new(0, 5.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
	Debris:AddItem(bb, 1.3)
end

hud.onBuyCoins = function(productId: number)
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	else
		hud.notify("That pack isn't set up yet")
	end
end

hud.onBuyDoubler = function()
	local id = Config.Monetization.CoinDoublerGamepassId
	if id > 0 then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		hud.notify("Not available yet")
	end
end

Net.getEvent(Net.Events.QueueUpdate).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: Types.QueueInfo
	inQueue = info.inQueue
	hud.setQueue(info.inQueue, info.size)
end)

Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function(payload: unknown)
	inQueue = false
	local info = payload :: Types.RoundStartInfo
	Warmup.cancel() -- drop the practice mini-game if a match starts
	Sound.stopMusic() -- entrance song off; crowd ambience carries the match
	Camera.toMatch(info.role == "Keeper") -- goalkeeper view on your turn to keep
	hud.startRound(info)
end)

Net.getEvent(Net.Events.RoundResult).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: Types.RoundResultInfo
	hud.showRoundResult(info)
	ShotAnimator.play(info)
end)

Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function(payload: unknown)
	Sound.playMusic() -- back to the lobby tune
	Camera.toLobby() -- hand control back to the walk-around camera
	hud.showMatchOver(payload :: Types.MatchOverInfo)
end)

Net.getEvent(Net.Events.ProfileUpdate).OnClientEvent:Connect(function(payload: unknown)
	hud.setProfile(payload :: Types.ProfileData)
end)

Net.getEvent(Net.Events.Notify).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { message: string }
	hud.notify(info.message)
end)

Net.getEvent(Net.Events.LeaderboardUpdate).OnClientEvent:Connect(function(payload: unknown)
	hud.setLeaderboard(payload :: Types.LeaderboardData)
end)

Net.getEvent(Net.Events.MonetizationInfo).OnClientEvent:Connect(function(payload: unknown)
	hud.setMonetization(payload :: Types.MonetizationInfo)
end)

Net.getEvent(Net.Events.ChallengeInvite).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { fromUserId: number, fromName: string }
	hud.showChallengeInvite(info.fromUserId, info.fromName)
end)

Net.getEvent(Net.Events.EmoteShown).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { userId: number, emoji: string }
	showEmote(info.userId, info.emoji)
end)

hud.showLobby()
Camera.toLobby() -- start on the default walk-around camera in the plaza
Warmup.start() -- enable the practice-range prompt
Hub.start(hud) -- photo booth, stalls, prediction kiosk prompts
DecorFX.start()
Sound.startCrowd() -- stadium ambience loop
Sound.playMusic() -- lobby entrance song

-- Everything's ready: fade the loading screen out and clean it up.
task.delay(0.6, function()
	local info = TweenInfo.new(0.5)
	for _, d in loadingScreen:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 })
				:Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.wait(0.55)
	loadingScreen:Destroy()
end)

print("[PenaltyKings] Client ready (PvP).")
