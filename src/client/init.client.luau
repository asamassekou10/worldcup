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

	-- Rotating TIPS so the unavoidable load doubles as onboarding (teaches new players what to do).
	local tip = Instance.new("TextLabel")
	tip.Size = UDim2.fromScale(0.74, 0.06)
	tip.Position = UDim2.fromScale(0.13, 0.63)
	tip.BackgroundTransparency = 1
	tip.Font = Theme.FontBody
	tip.TextScaled = true
	tip.TextWrapped = true
	tip.TextColor3 = Theme.Text
	tip.Text = ""
	tip.Parent = bg
	local tips = {
		"💡 Tap 🎮 PLAY at the top to pick a mode!",
		"💡 Run the 🤔 WOULD YOU RATHER portal — transform into Messi, the mascot & more!",
		"💡 Collect legends to unlock rare glowing auras ✨",
		"💡 Clear today's 🗓️ Daily 5 for bonus coins!",
		"💡 Play with a friend for a daily Squad Bonus 👥",
		"💡 Score in the World Cup penalty shootout ⚽",
	}
	task.spawn(function()
		local i = 0
		while gui.Parent do
			i = i % #tips + 1
			tip.Text = tips[i]
			task.wait(2.5)
		end
	end)
	return gui
end
local loadingScreen = buildLoadingScreen()
Debris:AddItem(loadingScreen, 12) -- hard safety: never let it get stuck on screen

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
local Juggle = require(script:WaitForChild("Juggle"))
local Onboarding = require(script:WaitForChild("Onboarding"))

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

hud.onBuySeasonPass = function()
	local id = Config.Monetization.SeasonPassId
	if id > 0 then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		hud.notify("Season Pass coming soon!")
	end
end

Net.getEvent(Net.Events.QueueUpdate).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: Types.QueueInfo
	inQueue = info.inQueue
	hud.setQueue(info.inQueue, info.size)
end)

-- Growth nudge (Like/Favorite reminder + Invite button), assigned by the do-block near the end
-- of this file and fired after positive moments (win / Choices finish). Self-throttled.
local showGrowthNudge: (() -> ())? = nil

Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function(payload: unknown)
	inQueue = false
	local info = payload :: Types.RoundStartInfo
	Warmup.cancel() -- drop the practice mini-game if a match starts
	Sound.stopMusic() -- entrance song off; crowd ambience carries the match
	Camera.toMatch(info.role == "Keeper") -- goalkeeper view on your turn to keep
	-- Anticipation: dip the crowd to a tense hush as the kicker steps up, so the roar
	-- (or groan) on the result lands with real contrast. Pairs with the camera dolly.
	Sound.setCrowdIntensity(0.22, 0.7)
	Sound.play("StepUp") -- optional tension tick (no-op until an id is set)
	hud.startRound(info)
end)

Net.getEvent(Net.Events.RoundResult).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: Types.RoundResultInfo
	hud.showRoundResult(info)
	ShotAnimator.play(info)
	-- Reactive crowd: roar on goal, cheer on save, quiet groan on miss.
	if info.outcome == "Goal" then
		Sound.crowdGoalReact()
		DecorFX.billow(info.shotX, info.shotY)
	elseif info.outcome == "Save" then
		Sound.crowdSaveReact()
	else
		Sound.crowdMissReact()
	end
end)

Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: Types.MatchOverInfo
	if info.won then
		Sound.play("WinFanfare") -- victory fanfare (no-op until an id is set)
	end
	Sound.playMusic() -- back to the lobby tune
	Camera.toLobby() -- hand control back to the walk-around camera
	hud.showMatchOver(info)
	if info.won and showGrowthNudge then
		task.delay(3, showGrowthNudge) -- after the win screen lands
	end
end)

Net.getEvent(Net.Events.ProfileUpdate).OnClientEvent:Connect(function(payload: unknown)
	local profile = payload :: Types.ProfileData
	hud.setProfile(profile)
	Onboarding.start(profile) -- first-time welcome (shows once, self-guards)
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
	Sound.play("Challenge") -- "why are you challenging me?" taunt on an incoming challenge
	hud.showChallengeInvite(info.fromUserId, info.fromName)
end)

-- Trivia Gauntlet: swap THIS client's Lighting to a scary sky + red haze while in the
-- course, and restore it on exit. Local-only changes, so the stadium stays normal for
-- everyone else. The server parks the scary Sky in ReplicatedStorage.GauntletSky.
do
	local Lighting = game:GetService("Lighting")
	local saved: { Instance } = {} -- stadium Lighting children hidden during the run
	local added: { Instance } = {} -- scary children we added, destroyed on exit
	local active = false

	local function hide(inst: Instance?)
		if inst then
			inst.Parent = nil
			table.insert(saved, inst)
		end
	end

	local function applyScary()
		if active then
			return
		end
		active = true
		-- Only blank out the stadium sky if we actually have the scary sky to put in its
		-- place -- otherwise the screen just goes black (the "dark sky" bug). If the asset
		-- didn't load, we keep the stadium sky and just tint it red below.
		local src = ReplicatedStorage:FindFirstChild("GauntletSky")
		if src then
			hide(Lighting:FindFirstChildOfClass("Sky"))
			hide(Lighting:FindFirstChildOfClass("Atmosphere"))
			local sky = src:Clone()
			sky.Parent = Lighting
			table.insert(added, sky)
			local atm = Instance.new("Atmosphere")
			atm.Density = 0.42
			atm.Color = Color3.fromRGB(200, 90, 60)
			atm.Decay = Color3.fromRGB(120, 40, 30)
			atm.Haze = 2.5
			atm.Parent = Lighting
			table.insert(added, atm)
		end
		local cc = Instance.new("ColorCorrectionEffect")
		cc.TintColor = Color3.fromRGB(255, 150, 130)
		cc.Brightness = -0.05
		cc.Contrast = 0.15
		cc.Parent = Lighting
		table.insert(added, cc)
	end

	local function revert()
		if not active then
			return
		end
		active = false
		for _, p in added do
			p:Destroy()
		end
		added = {}
		for _, p in saved do
			p.Parent = Lighting
		end
		saved = {}
	end

	Net.getEvent(Net.Events.GauntletAtmosphere).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: { active: boolean }
		if info.active then
			applyScary()
		else
			revert()
		end
	end)
end

-- Choices runner audio: a looping track during a run + one-shot SFX. All graceful -- a
-- private/unowned id just plays silent, never errors. Shared by the Choices blocks below.
local choicesMusic = Instance.new("Sound")
choicesMusic.Name = "ChoicesMusic"
choicesMusic.SoundId = Config.ChoicesMusic or ""
choicesMusic.Looped = true
choicesMusic.Volume = 0.4
choicesMusic.Parent = workspace:FindFirstChildOfClass("SoundService")
	or game:GetService("SoundService")
local function choicesSfx(soundId: string?)
	if not soundId or soundId == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = 0.7
	s.Parent = game:GetService("SoundService")
	s:Play()
	Debris:AddItem(s, 6)
end

-- A transient FOV "punch" (a quick zoom-in kick) set when you cross a door and decayed by the
-- choices camera loop -- shared across the two do-blocks below so each pick lands as a beat.
local cameraPunch = 0

-- Choices runner: after you walk through a door, the server sends the GLOBAL vote split
-- (or, on a World Cup trivia gate, which door was correct). This pops the video's
-- "62% chose X / 38% chose Y" splash on the left, then fades.
do
	type Result = {
		prompt: string,
		aText: string,
		bText: string,
		aPct: number,
		bPct: number,
		picked: string, -- "a" | "b"
		correct: string?, -- set on trivia gates: "a" | "b"
		index: number?, -- which gate (1..total)
		total: number?, -- gates in the run
	}

	local gui = Instance.new("ScreenGui")
	gui.Name = "ChoiceSplash"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 18
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 24, 0.5, 0)
	panel.Size = UDim2.fromOffset(330, 150)
	panel.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -20, 0, 26)
	header.Position = UDim2.fromOffset(10, 8)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextScaled = true
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(180, 190, 210)
	header.Text = ""
	header.Parent = panel

	local progress = Instance.new("TextLabel")
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Size = UDim2.fromOffset(96, 22)
	progress.Position = UDim2.new(1, -10, 0, 10)
	progress.BackgroundTransparency = 1
	progress.Font = Enum.Font.GothamBold
	progress.TextScaled = true
	progress.TextXAlignment = Enum.TextXAlignment.Right
	progress.TextColor3 = Color3.fromRGB(255, 220, 120)
	progress.Text = ""
	progress.Parent = panel

	local function bar(y: number): (TextLabel, Frame)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, -20, 0, 44)
		holder.Position = UDim2.fromOffset(10, y)
		holder.BackgroundColor3 = Color3.fromRGB(28, 34, 50)
		holder.BorderSizePixel = 0
		holder.Parent = panel
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 8)
		hc.Parent = holder
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0.5, 1)
		fill.BackgroundColor3 = Color3.fromRGB(60, 130, 230)
		fill.BorderSizePixel = 0
		fill.Parent = holder
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(0, 8)
		fc.Parent = fill
		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, -16, 1, 0)
		txt.Position = UDim2.fromOffset(8, 0)
		txt.BackgroundTransparency = 1
		txt.Font = Enum.Font.GothamBlack
		txt.TextScaled = true
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextColor3 = Color3.fromRGB(255, 255, 255)
		txt.TextStrokeTransparency = 0.4
		txt.ZIndex = 2
		txt.Text = ""
		txt.Parent = holder
		return txt, fill
	end
	local txtA, fillA = bar(40)
	local txtB, fillB = bar(92)

	local token = 0
	Net.getEvent(Net.Events.ChoiceResult).OnClientEvent:Connect(function(payload: unknown)
		local r = payload :: Result
		token += 1
		local mine = token
		local trivia = r.correct ~= nil
		choicesSfx(Config.Sounds.DoorWhoosh) -- door whoosh every pick
		-- a quick "transformation" burst on your character so every pick FEELS like a change
		do
			local ch = player.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp then
				local fx = Instance.new("Part")
				fx.Anchored = true
				fx.CanCollide = false
				fx.CanQuery = false
				fx.Transparency = 1
				fx.Size = Vector3.new(1, 1, 1)
				fx.CFrame = (hrp :: BasePart).CFrame
				fx.Parent = workspace
				local burst = Instance.new("ParticleEmitter")
				burst.Color =
					ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(120, 200, 255))
				burst.LightEmission = 1
				burst.Lifetime = NumberRange.new(0.4, 0.6)
				burst.Speed = NumberRange.new(14, 20)
				burst.SpreadAngle = Vector2.new(180, 180)
				burst.Size = NumberSequence.new(1.6)
				burst.Rate = 0
				burst.Parent = fx
				burst:Emit(40)
				Debris:AddItem(fx, 1)
			end
		end
		cameraPunch = 13 -- a quick zoom-in kick so the transformation lands as a beat
		if trivia then
			choicesSfx(
				if r.picked == r.correct
					then Config.Sounds.AnswerCorrect
					else Config.Sounds.AnswerWrong
			)
			header.Text = (if r.picked == r.correct then "✅ Correct!" else "❌ Wrong!")
			local greenA = r.correct == "a"
			fillA.Size = UDim2.fromScale(1, 1)
			fillB.Size = UDim2.fromScale(1, 1)
			fillA.BackgroundColor3 = if greenA
				then Color3.fromRGB(70, 190, 110)
				else Color3.fromRGB(150, 60, 60)
			fillB.BackgroundColor3 = if greenA
				then Color3.fromRGB(150, 60, 60)
				else Color3.fromRGB(70, 190, 110)
			txtA.Text = r.aText
			txtB.Text = r.bText
		else
			header.Text = "🌍 What everyone picked"
			fillA.BackgroundColor3 = Color3.fromRGB(60, 130, 230)
			fillB.BackgroundColor3 = Color3.fromRGB(235, 120, 55)
			fillA.Size = UDim2.fromScale(math.max(0.06, r.aPct / 100), 1)
			fillB.Size = UDim2.fromScale(math.max(0.06, r.bPct / 100), 1)
			txtA.Text = string.format("%d%%  %s", r.aPct, r.aText)
			txtB.Text = string.format("%d%%  %s", r.bPct, r.bText)
		end
		-- highlight the door you chose
		txtA.TextColor3 = if r.picked == "a"
			then Color3.fromRGB(255, 240, 150)
			else Color3.fromRGB(255, 255, 255)
		txtB.TextColor3 = if r.picked == "b"
			then Color3.fromRGB(255, 240, 150)
			else Color3.fromRGB(255, 255, 255)
		progress.Text = if r.index and r.total
			then string.format("Gate %d/%d", r.index, r.total)
			else ""
		gui.Enabled = true
		-- slide in from off the left edge for a bit of juice
		panel.Position = UDim2.new(0, -360, 0.5, 0)
		TweenService
			:Create(panel, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, 24, 0.5, 0),
			})
			:Play()
		task.delay(3.2, function()
			if token == mine then
				gui.Enabled = false
			end
		end)
	end)
end

-- Choices runner: hide the penalty-game HUD on entry (clean screen), and as you approach
-- each gate "zoom" toward the two doors so you can read the choice. We do the zoom with
-- FieldOfView only -- NOT a Scriptable camera takeover -- so the normal follow-cam stays
-- in control and you can still run left/right and switch lanes.
do
	local RunService = game:GetService("RunService")

	type CourseGate = {
		z: number,
		prompt: string,
		a: string,
		b: string,
		aPct: number?,
		bPct: number?,
	}
	local gates: { CourseGate } = {}
	local active = false
	local defaultFov = 70 -- captured from the camera on entry
	local ZOOM_FOV = 48 -- narrower = zoomed in on the doors ahead

	local function easeFov(target: number)
		local cam = workspace.CurrentCamera
		if cam then
			cam.FieldOfView += (target - cam.FieldOfView) * 0.15
		end
	end

	-- Sneak Peek perk: a small overlay that reveals the global vote % of the door ahead
	-- BEFORE you choose. Only populated for owners (the server includes aPct in the course).
	local peekGui = Instance.new("ScreenGui")
	peekGui.Name = "ChoicesSneakPeek"
	peekGui.ResetOnSpawn = false
	peekGui.IgnoreGuiInset = true
	peekGui.DisplayOrder = 19
	peekGui.Enabled = false
	peekGui.Parent = player:WaitForChild("PlayerGui")
	local peekLbl = Instance.new("TextLabel")
	peekLbl.AnchorPoint = Vector2.new(0.5, 0)
	peekLbl.Position = UDim2.new(0.5, 0, 0, 160)
	peekLbl.Size = UDim2.fromOffset(280, 34)
	peekLbl.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
	peekLbl.BackgroundTransparency = 0.2
	peekLbl.Font = Enum.Font.GothamBold
	peekLbl.TextScaled = true
	peekLbl.TextColor3 = Color3.fromRGB(200, 230, 255)
	peekLbl.Text = ""
	peekLbl.Parent = peekGui
	local peekCorner = Instance.new("UICorner")
	peekCorner.CornerRadius = UDim.new(0, 8)
	peekCorner.Parent = peekLbl

	-- Gate progress bar across the top: how far down the course you are (X / N).
	local progGui = Instance.new("ScreenGui")
	progGui.Name = "ChoicesProgress"
	progGui.ResetOnSpawn = false
	progGui.IgnoreGuiInset = true
	progGui.DisplayOrder = 18
	progGui.Enabled = false
	progGui.Parent = player:WaitForChild("PlayerGui")
	local progBack = Instance.new("Frame")
	progBack.AnchorPoint = Vector2.new(0.5, 0)
	progBack.Position = UDim2.new(0.5, 0, 0, 14)
	progBack.Size = UDim2.fromOffset(340, 22)
	progBack.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
	progBack.BackgroundTransparency = 0.25
	progBack.Parent = progGui
	local progBackCorner = Instance.new("UICorner")
	progBackCorner.CornerRadius = UDim.new(1, 0)
	progBackCorner.Parent = progBack
	local progFill = Instance.new("Frame")
	progFill.Size = UDim2.fromScale(0, 1)
	progFill.BackgroundColor3 = Color3.fromRGB(90, 220, 140)
	progFill.BorderSizePixel = 0
	progFill.Parent = progBack
	local progFillCorner = Instance.new("UICorner")
	progFillCorner.CornerRadius = UDim.new(1, 0)
	progFillCorner.Parent = progFill
	local progLbl = Instance.new("TextLabel")
	progLbl.Size = UDim2.fromScale(1, 1)
	progLbl.BackgroundTransparency = 1
	progLbl.Font = Enum.Font.GothamBold
	progLbl.TextScaled = true
	progLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	progLbl.TextStrokeTransparency = 0.5
	progLbl.ZIndex = 2
	progLbl.Text = ""
	progLbl.Parent = progBack

	-- BRAND WATERMARK: a small corner stamp shown the whole run, so any clip someone records
	-- carries the game name (free marketing for every shared transformation).
	local markGui = Instance.new("ScreenGui")
	markGui.Name = "ChoicesWatermark"
	markGui.ResetOnSpawn = false
	markGui.IgnoreGuiInset = true
	markGui.DisplayOrder = 17
	markGui.Enabled = false
	markGui.Parent = player:WaitForChild("PlayerGui")
	local mark = Instance.new("TextLabel")
	mark.AnchorPoint = Vector2.new(1, 1)
	mark.Position = UDim2.new(1, -16, 1, -14)
	mark.Size = UDim2.fromOffset(250, 26)
	mark.BackgroundTransparency = 1
	mark.Font = Enum.Font.GothamBlack
	mark.TextScaled = true
	mark.TextXAlignment = Enum.TextXAlignment.Right
	mark.TextColor3 = Color3.fromRGB(255, 235, 150)
	mark.TextTransparency = 0.25
	mark.TextStrokeTransparency = 0.4
	mark.Text = "⚽ PENALTY KINGS · Roblox"
	mark.Parent = markGui

	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: { active: boolean }
		active = info.active
		hud.setChoicesMode(active)
		progGui.Enabled = active
		markGui.Enabled = active
		local cam = workspace.CurrentCamera
		if active then
			if cam then
				defaultFov = cam.FieldOfView -- remember the player's normal FOV
			end
			Sound.stopMusic() -- silence the lobby track so only the runner track plays
			choicesMusic:Play() -- runner track on
		else
			gates = {}
			peekGui.Enabled = false
			choicesMusic:Stop() -- runner track off
			Sound.playMusic() -- bring the lobby track back
			cameraPunch = 0
			if cam then
				cam.FieldOfView = defaultFov -- restore on exit
			end
		end
	end)

	Net.getEvent(Net.Events.ChoicesCourse).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: { gates: { CourseGate } }
		gates = info.gates or {}
	end)

	RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local pz = root.Position.Z
		-- zoom in while a gate is just ahead of us (the choice we're walking up to)
		local near: CourseGate? = nil
		local passed = 0
		for _, g in gates do
			local ahead = g.z - pz
			if ahead <= 1 then
				passed += 1
			end
			if ahead > 1 and ahead < 26 and (not near or g.z < near.z) then
				near = g
			end
		end
		-- gate progress bar
		local n = #gates
		if n > 0 then
			progLbl.Text = string.format("🚪 Gate %d / %d", math.min(passed + 1, n), n)
			progFill.Size = UDim2.fromScale(math.clamp(passed / n, 0, 1), 1)
		end
		-- ease toward the zoom target, punched down briefly each time you cross a door
		easeFov((if near then ZOOM_FOV else defaultFov) - cameraPunch)
		cameraPunch = if cameraPunch > 0.2 then cameraPunch * 0.82 else 0
		-- Sneak Peek overlay (only if the server sent vote % for this gate)
		if near and near.aPct then
			peekLbl.Text = string.format(
				"👀  🔵 %d%%   /   %d%% 🟠",
				near.aPct,
				near.bPct or (100 - near.aPct)
			)
			peekGui.Enabled = true
		else
			peekGui.Enabled = false
		end
	end)
end

-- Choices runner: the shareable end-of-run "personality card" -- how often you sided with
-- the crowd (Sheep <-> Rebel) + your legend-collection progress. Screenshot-bait.
do
	type Summary = {
		agreed: number,
		dilemmas: number,
		points: number,
		legendsUnlocked: number,
		legendsTotal: number,
		newLegends: { string },
		title: string?, -- a shareable earned title (e.g. "🔥 The Rebel"); server-computed
	}

	local gui = Instance.new("ScreenGui")
	gui.Name = "ChoicesSummary"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 19
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- full-screen dim that also closes the card on tap (works on mobile)
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = gui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(420, 440)
	card.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	card.BorderSizePixel = 0
	card.Parent = backdrop
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 18)
	cc.Parent = card
	local cs = Instance.new("UIStroke")
	cs.Color = Color3.fromRGB(255, 200, 70)
	cs.Thickness = 3
	cs.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local function mk(order: number, height: number, font: Enum.Font, color: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, height)
		t.BackgroundTransparency = 1
		t.Font = font
		t.TextScaled = true
		t.TextWrapped = true
		t.TextColor3 = color
		t.LayoutOrder = order
		t.Text = ""
		t.Parent = card
		return t
	end
	local title = mk(1, 30, Enum.Font.GothamBold, Color3.fromRGB(180, 190, 210))
	title.Text = "RUN COMPLETE 🏆"
	local verdict = mk(2, 64, Enum.Font.GothamBlack, Color3.fromRGB(255, 235, 150))
	local crowdLine = mk(3, 28, Enum.Font.GothamBold, Color3.fromRGB(225, 230, 240))
	local legendsLine = mk(4, 34, Enum.Font.GothamBold, Color3.fromRGB(120, 220, 255))
	local newLine = mk(5, 48, Enum.Font.GothamBold, Color3.fromRGB(255, 220, 120))
	local pointsLine = mk(6, 28, Enum.Font.GothamBold, Color3.fromRGB(225, 230, 240))
	local shareLine = mk(7, 26, Enum.Font.GothamBold, Color3.fromRGB(255, 235, 150))
	shareLine.Text = "📸 Screenshot & share  ·  ⚽ PENALTY KINGS on Roblox"

	local function verdictFor(rebel: number): (string, Color3)
		if rebel >= 70 then
			return "🔥 TOTAL REBEL", Color3.fromRGB(255, 120, 90)
		elseif rebel >= 55 then
			return "😎 FREE THINKER", Color3.fromRGB(255, 180, 90)
		elseif rebel >= 45 then
			return "⚖️ PERFECTLY BALANCED", Color3.fromRGB(255, 235, 150)
		elseif rebel >= 30 then
			return "🙂 MOSTLY BASIC", Color3.fromRGB(160, 220, 255)
		else
			return "🐑 TOTAL SHEEP", Color3.fromRGB(150, 200, 255)
		end
	end

	local token = 0
	local function close()
		gui.Enabled = false
	end
	backdrop.Activated:Connect(close)

	Net.getEvent(Net.Events.ChoicesSummary).OnClientEvent:Connect(function(payload: unknown)
		local s = payload :: Summary
		token += 1
		local mine = token
		local crowd = if s.dilemmas > 0 then math.floor(s.agreed / s.dilemmas * 100 + 0.5) else 50
		local rebel = 100 - crowd
		local label, color = verdictFor(rebel)
		verdict.Text = s.title or label -- the earned title is the shareable headline
		verdict.TextColor3 = color
		crowdLine.Text =
			string.format("You sided with the crowd %d/%d  (%d%%)", s.agreed, s.dilemmas, crowd)
		legendsLine.Text =
			string.format("⭐ Legends collected: %d / %d", s.legendsUnlocked, s.legendsTotal)
		if #s.newLegends > 0 then
			newLine.Text = "🆕 New: " .. table.concat(s.newLegends, ", ")
			choicesSfx(Config.Sounds.LegendChime) -- celebrate a fresh unlock
		else
			newLine.Text = ""
		end
		pointsLine.Text = string.format("🏆 %d points this run", s.points)
		gui.Enabled = true
		card.Size = UDim2.fromOffset(380, 440)
		TweenService
			:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(420, 440),
			})
			:Play()
		task.delay(8, function()
			if token == mine then
				close()
			end
			if showGrowthNudge then
				showGrowthNudge() -- nudge after the shareable card closes
			end
		end)
	end)
end

-- Choices runner: a browsable "Become a Legend" collection + a button showing X/Y progress.
-- Reads the replicated profile (LegendsUnlocked) and ChoiceBank -- no extra server calls.
do
	local ChoiceBank = require(Shared:WaitForChild("ChoiceBank"))
	local total = ChoiceBank.legendCount()
	local unlocked: { [string]: boolean } = {}

	local function countUnlocked(): number
		local n = 0
		for _ in unlocked do
			n += 1
		end
		return n
	end

	-- floating open button (left edge, clear of the mobile move/jump controls)
	local btnGui = Instance.new("ScreenGui")
	btnGui.Name = "LegendsButton"
	btnGui.ResetOnSpawn = false
	btnGui.DisplayOrder = 12
	btnGui.Parent = player:WaitForChild("PlayerGui")
	local openBtn = Instance.new("TextButton")
	openBtn.AnchorPoint = Vector2.new(0, 0.5)
	openBtn.Position = UDim2.new(0, 8, 0.4, 0)
	openBtn.Size = UDim2.fromOffset(118, 42)
	openBtn.BackgroundColor3 = Color3.fromRGB(28, 34, 54)
	openBtn.Font = Enum.Font.GothamBold
	openBtn.TextScaled = true
	openBtn.TextColor3 = Color3.fromRGB(255, 230, 140)
	openBtn.Text = "🏅 0/" .. total
	openBtn.Parent = btnGui
	local obc = Instance.new("UICorner")
	obc.CornerRadius = UDim.new(0, 10)
	obc.Parent = openBtn
	local obp = Instance.new("UIPadding")
	obp.PaddingLeft = UDim.new(0, 8)
	obp.PaddingRight = UDim.new(0, 8)
	obp.PaddingTop = UDim.new(0, 7)
	obp.PaddingBottom = UDim.new(0, 7)
	obp.Parent = openBtn

	-- the collection modal
	local panelGui = Instance.new("ScreenGui")
	panelGui.Name = "LegendsPanel"
	panelGui.ResetOnSpawn = false
	panelGui.IgnoreGuiInset = true
	panelGui.DisplayOrder = 17
	panelGui.Enabled = false
	panelGui.Parent = player:WaitForChild("PlayerGui")
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = panelGui
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(470, 470)
	card.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	card.BorderSizePixel = 0
	card.Parent = backdrop
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 18)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 200, 70)
	cardStroke.Thickness = 3
	cardStroke.Parent = card
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -24, 0, 34)
	titleLbl.Position = UDim2.fromOffset(12, 12)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextScaled = true
	titleLbl.TextColor3 = Color3.fromRGB(255, 235, 150)
	titleLbl.Text = "🏅 BECOME A LEGEND"
	titleLbl.Parent = card
	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(1, -24, 0, 22)
	subLbl.Position = UDim2.fromOffset(12, 48)
	subLbl.BackgroundTransparency = 1
	subLbl.Font = Enum.Font.GothamBold
	subLbl.TextScaled = true
	subLbl.TextColor3 = Color3.fromRGB(180, 190, 210)
	subLbl.Text = ""
	subLbl.Parent = card
	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.new(1, -24, 1, -120)
	scroller.Position = UDim2.fromOffset(12, 78)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 5
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = card
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(102, 92)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -10)
	hint.Size = UDim2.new(1, -24, 0, 22)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextScaled = true
	hint.TextColor3 = Color3.fromRGB(150, 160, 180)
	hint.Text = "Run the Choices and pick a legend's door to unlock it!"
	hint.Parent = card

	type Cell = { swatch: Frame, name: TextLabel, lock: TextLabel }
	local cells: { [string]: Cell } = {}
	for order, id in ChoiceBank.LegendOrder do
		local cell = Instance.new("Frame")
		cell.BackgroundColor3 = Color3.fromRGB(26, 30, 46)
		cell.BorderSizePixel = 0
		cell.LayoutOrder = order
		cell.Parent = scroller
		local cco = Instance.new("UICorner")
		cco.CornerRadius = UDim.new(0, 10)
		cco.Parent = cell
		local swatch = Instance.new("Frame")
		swatch.AnchorPoint = Vector2.new(0.5, 0)
		swatch.Position = UDim2.new(0.5, 0, 0, 8)
		swatch.Size = UDim2.fromOffset(44, 44)
		swatch.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
		swatch.BorderSizePixel = 0
		swatch.Parent = cell
		local sco = Instance.new("UICorner")
		sco.CornerRadius = UDim.new(1, 0)
		sco.Parent = swatch
		local lock = Instance.new("TextLabel")
		lock.Size = UDim2.fromScale(1, 1)
		lock.BackgroundTransparency = 1
		lock.Font = Enum.Font.GothamBold
		lock.TextScaled = true
		lock.Text = "🔒"
		lock.Parent = swatch
		local name = Instance.new("TextLabel")
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -6)
		name.Size = UDim2.new(1, -8, 0, 30)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextWrapped = true
		name.TextColor3 = Color3.fromRGB(140, 150, 170)
		name.Text = "???"
		name.Parent = cell
		cells[id] = { swatch = swatch, name = name, lock = lock }
	end

	local function refresh()
		local have = countUnlocked()
		openBtn.Text = string.format("🏅 %d/%d", have, total)
		subLbl.Text = string.format("Collected %d of %d legends", have, total)
		for id, c in cells do
			local un = unlocked[id] == true
			c.swatch.BackgroundColor3 = if un
				then ChoiceBank.LegendColor[id] or Color3.fromRGB(120, 120, 120)
				else Color3.fromRGB(40, 44, 58)
			c.lock.Visible = not un
			c.name.Text = if un then ChoiceBank.Legends[id] else "???"
			c.name.TextColor3 = if un
				then Color3.fromRGB(255, 255, 255)
				else Color3.fromRGB(120, 128, 145)
		end
	end

	openBtn.Activated:Connect(function()
		panelGui.Enabled = true
		refresh()
	end)
	backdrop.Activated:Connect(function()
		panelGui.Enabled = false
	end)

	Net.getEvent(Net.Events.ProfileUpdate).OnClientEvent:Connect(function(payload: unknown)
		local data = payload :: { LegendsUnlocked: { [string]: boolean }? }
		unlocked = data.LegendsUnlocked or {}
		refresh()
	end)

	-- hide the button while running a course (the screen is meant to be clean there)
	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: { active: boolean }
		btnGui.Enabled = not info.active
		if info.active then
			panelGui.Enabled = false
		end
	end)

	refresh()
end

-- Treadmill "Training Grounds": a small "+coins / +XP" pop on each training tick.
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "TrainingTicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 16
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0)
	lbl.Position = UDim2.new(0.5, 0, 0, 120)
	lbl.Size = UDim2.fromOffset(300, 40)
	lbl.BackgroundColor3 = Color3.fromRGB(16, 24, 18)
	lbl.BackgroundTransparency = 0.2
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(150, 245, 170)
	lbl.Text = ""
	lbl.Parent = gui
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 10)
	tc.Parent = lbl

	local token = 0
	Net.getEvent(Net.Events.TreadmillTick).OnClientEvent:Connect(function(payload: unknown)
		local t = payload :: { coins: number, xp: number, energy: boolean }
		token += 1
		local mine = token
		lbl.Text =
			string.format("%s🏃 +%d 💰  +%d XP", if t.energy then "⚡ " else "", t.coins, t.xp)
		gui.Enabled = true
		task.delay(1.6, function()
			if token == mine then
				gui.Enabled = false
			end
		end)
	end)
end

-- Choices runner: per-player WEATHER + one-shot sounds from a door's effect. Reuses the
-- "only this client's Lighting changes" trick so the shared course can show YOUR rain while
-- another runner has their heatwave. "clear" (sent at the finish) reverts everything.
do
	local Lighting = game:GetService("Lighting")
	local RunService = game:GetService("RunService")
	local SoundService = game:GetService("SoundService")

	local cc: ColorCorrectionEffect? = nil
	local weatherPart: BasePart? = nil
	local follow: RBXScriptConnection? = nil
	local addedSky: Instance? = nil -- the lava sky we swapped in (heat)
	local hiddenSky: Instance? = nil -- the stadium sky we parked while heat is on
	local stormToken = 0
	local savedFogEnd, savedFogColor = Lighting.FogEnd, Lighting.FogColor

	local function clearWeather()
		stormToken += 1
		if cc then
			cc:Destroy()
			cc = nil
		end
		if weatherPart then
			weatherPart:Destroy()
			weatherPart = nil
		end
		if follow then
			follow:Disconnect()
			follow = nil
		end
		if addedSky then
			addedSky:Destroy()
			addedSky = nil
		end
		if hiddenSky then
			hiddenSky.Parent = Lighting -- restore the stadium sky
			hiddenSky = nil
		end
		Lighting.FogEnd, Lighting.FogColor = savedFogEnd, savedFogColor
	end

	local function rainEmitter(): ParticleEmitter
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(46, 1, 46)
		part.Parent = workspace
		weatherPart = part
		follow = RunService.RenderStepped:Connect(function()
			local ch = player.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp and weatherPart then
				weatherPart.CFrame = CFrame.new((hrp :: BasePart).Position + Vector3.new(0, 26, 0))
			end
		end)
		local em = Instance.new("ParticleEmitter")
		em.EmissionDirection = Enum.NormalId.Bottom
		em.Parent = part
		return em
	end

	Net.getEvent(Net.Events.ChoicesEffect).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: { weather: string?, sound: string? }
		if info.sound and info.sound ~= "" then
			local s = Instance.new("Sound")
			s.SoundId = info.sound
			s.Volume = 0.6
			s.Parent = SoundService
			s:Play()
			Debris:AddItem(s, 6)
		end
		local w = info.weather
		clearWeather()
		if not w or w == "clear" then
			return
		end
		cc = Instance.new("ColorCorrectionEffect")
		cc.Parent = Lighting
		local c = cc :: ColorCorrectionEffect
		if w == "rain" then
			c.TintColor, c.Brightness, c.Contrast = Color3.fromRGB(150, 175, 200), -0.06, -0.05
			Lighting.FogColor, Lighting.FogEnd = Color3.fromRGB(120, 135, 150), 400
			local em = rainEmitter()
			local fx = ReplicatedStorage:FindFirstChild("ChoicesRainFX")
			if fx and weatherPart then
				-- real "Realistic Rain" particles
				em:Destroy()
				for _, e in fx:GetChildren() do
					if e:IsA("ParticleEmitter") then
						e:Clone().Parent = weatherPart
					end
				end
			else
				em.Color = ColorSequence.new(Color3.fromRGB(170, 195, 225))
				em.Rate, em.Lifetime, em.Speed =
					320, NumberRange.new(0.5, 0.7), NumberRange.new(90, 110)
				em.Acceleration, em.Size = Vector3.new(0, -160, 0), NumberSequence.new(0.22)
				em.Transparency, em.SpreadAngle = NumberSequence.new(0.3), Vector2.new(7, 7)
			end
		elseif w == "heat" then
			c.TintColor, c.Brightness, c.Saturation = Color3.fromRGB(255, 200, 150), 0.08, 0.12
			local lava = ReplicatedStorage:FindFirstChild("ChoicesLavaSky")
			if lava then
				-- swap THIS client's sky to the lava skybox (stadium sky parked + restored)
				hiddenSky = Lighting:FindFirstChildOfClass("Sky")
				if hiddenSky then
					hiddenSky.Parent = nil
				end
				addedSky = lava:Clone()
				addedSky.Parent = Lighting
			end
		elseif w == "fog" then
			c.TintColor, c.Brightness = Color3.fromRGB(190, 195, 205), -0.03
			Lighting.FogColor, Lighting.FogEnd = Color3.fromRGB(180, 185, 195), 130
		elseif w == "night" then
			c.TintColor, c.Brightness, c.Contrast = Color3.fromRGB(120, 135, 185), -0.18, 0.08
			Lighting.FogColor, Lighting.FogEnd = Color3.fromRGB(20, 26, 45), 500
		elseif w == "snow" then
			c.TintColor, c.Brightness = Color3.fromRGB(205, 218, 238), 0.04
			Lighting.FogColor, Lighting.FogEnd = Color3.fromRGB(210, 220, 235), 600
			local em = rainEmitter()
			em.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			em.Rate, em.Lifetime, em.Speed = 120, NumberRange.new(2, 3), NumberRange.new(6, 12)
			em.Acceleration, em.Size = Vector3.new(2, -10, 0), NumberSequence.new(0.5)
			em.SpreadAngle = Vector2.new(25, 25)
		elseif w == "storm" then
			c.TintColor, c.Brightness = Color3.fromRGB(130, 145, 170), -0.12
			Lighting.FogColor, Lighting.FogEnd = Color3.fromRGB(80, 90, 110), 350
			local em = rainEmitter()
			em.Color = ColorSequence.new(Color3.fromRGB(160, 180, 210))
			em.Rate, em.Lifetime, em.Speed =
				380, NumberRange.new(0.4, 0.6), NumberRange.new(110, 130)
			em.Acceleration, em.Size = Vector3.new(-20, -190, 0), NumberSequence.new(0.22)
			stormToken += 1
			local mine = stormToken
			task.spawn(function()
				while stormToken == mine and cc do
					task.wait(math.random(3, 7))
					if stormToken == mine and cc then
						local b = (cc :: ColorCorrectionEffect).Brightness;
						(cc :: ColorCorrectionEffect).Brightness = 0.7
						task.wait(0.08)
						if stormToken == mine and cc then
							(cc :: ColorCorrectionEffect).Brightness = b
						end
					end
				end
			end)
		end
	end)
end

Net.getEvent(Net.Events.EmoteShown).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { userId: number, emoji: string }
	showEmote(info.userId, info.emoji)
end)

-- Walk-Off 1v1 queue state (mirrors inQueue for the main queue).
local inWalkOffQueue = false
local joinWalkOffQueue = Net.getEvent(Net.Events.JoinWalkOffQueue)
local leaveWalkOffQueue = Net.getEvent(Net.Events.LeaveWalkOffQueue)

hud.onJoinWalkOff = function()
	if inWalkOffQueue then
		leaveWalkOffQueue:FireServer()
	else
		joinWalkOffQueue:FireServer()
	end
end

Net.getEvent(Net.Events.WalkOffQueueUpdate).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { inQueue: boolean, size: number }
	inWalkOffQueue = info.inQueue
	hud.setWalkOffQueue(info.inQueue, info.size)
end)

-- Gauntlet: the server fires GauntletStart for each shot (same shape as
-- RoundStartInfo + isGauntlet=true). RoundResult and MatchOver are shared.
-- GauntletStart is handled identically to RoundStart on the client — the
-- keeper-view camera + dive UI activate automatically via role="Keeper".
Net.getEvent(Net.Events.GauntletStart).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: Types.RoundStartInfo
	Warmup.cancel()
	Sound.stopMusic()
	Camera.toMatch(true) -- always keeper view in the gauntlet
	hud.startRound(info)
end)

Net.getEvent(Net.Events.GauntletOver).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { saves: number, totalShots: number, reward: number }
	hud.notify(
		string.format(
			"Gauntlet done! %d / %d saves  •  +%d coins",
			info.saves,
			info.totalShots,
			info.reward
		)
	)
end)

-- Trivia Kiosk: show question panel, wire answer button, handle result + over.
local triviaSubmit = Net.getEvent(Net.Events.TriviaSubmit)

hud.onTriviaAnswer = function(answer: string)
	triviaSubmit:FireServer({ answer = answer })
end

Net.getEvent(Net.Events.TriviaQuestion).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: UI.TriviaQuestionInfo
	hud.showTriviaQuestion(info)
end)

Net.getEvent(Net.Events.TriviaResult).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: {
		correct: boolean,
		correctAnswer: string,
		timedOut: boolean,
		yourScore: number?,
		oppScore: number?,
	}
	hud.showTriviaResult(
		info.correct,
		info.correctAnswer,
		info.timedOut,
		info.yourScore,
		info.oppScore
	)
end)

Net.getEvent(Net.Events.TriviaOver).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: {
		isDuel: boolean,
		correct: number,
		total: number,
		totalCoins: number,
		won: boolean?,
		tie: boolean?,
		yourScore: number?,
		oppScore: number?,
		opponentName: string?,
	}
	hud.hideTriviaPanel()
	if info.isDuel then
		local opp = info.opponentName or "rival"
		local headline
		if info.tie then
			headline = string.format("🤝 Trivia TIE vs %s", opp)
		elseif info.won then
			headline = string.format("🏆 Trivia WIN vs %s!", opp)
		else
			headline = string.format("Trivia: lost to %s", opp)
		end
		hud.notify(
			string.format(
				"%s   %d–%d  •  +%d coins",
				headline,
				info.yourScore or 0,
				info.oppScore or 0,
				info.totalCoins
			)
		)
	else
		local perfect = info.correct == info.total
		hud.notify(
			string.format(
				"Trivia done!  %d / %d correct%s  •  +%d coins",
				info.correct,
				info.total,
				if perfect then "  PERFECT!" else "",
				info.totalCoins
			)
		)
	end
end)

-- Free Kick Challenge: FreekickStart fires before each RoundStart so the
-- client can show which target zone to aim at as a notify toast.
-- RoundStart/RoundResult/MatchOver reuse the existing handlers unchanged.
Net.getEvent(Net.Events.FreekickStart).OnClientEvent:Connect(function(payload: unknown)
	local info =
		payload :: { shotIndex: number, totalShots: number, targetLabel: string, deadline: number }
	Warmup.cancel()
	Sound.stopMusic()
	Camera.toMatch(false) -- shooter view
	hud.notify(
		string.format(
			"Shot %d / %d  —  AIM %s!",
			info.shotIndex,
			info.totalShots,
			info.targetLabel
		)
	)
end)

Net.getEvent(Net.Events.FreekickOver).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { hits: number, totalShots: number, totalCoins: number }
	local perfect = info.hits == info.totalShots
	hud.notify(
		string.format(
			"Free Kick done!  %d / %d targets%s  •  +%d coins",
			info.hits,
			info.totalShots,
			if perfect then "  PERFECT!" else "",
			info.totalCoins
		)
	)
end)

-- Juggling Pitch: show minigame UI, relay taps, handle result.
local juggleHit = Net.getEvent(Net.Events.JuggleHit)

Net.getEvent(Net.Events.JuggleStart).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { duration: number, startTime: number, freq: number }
	Juggle.show(info, function()
		if Juggle.active then
			juggleHit:FireServer()
		end
	end)
end)

Net.getEvent(Net.Events.JuggleUpdate).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { count: number, streak: number, freq: number }
	Juggle.update(info)
end)

Net.getEvent(Net.Events.JuggleOver).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: { count: number, totalCoins: number }
	Juggle.hide()
	hud.notify(
		string.format("Juggling done!  %d juggles  •  +%d coins", info.count, info.totalCoins)
	)
end)

-- Season Pass: update local HUD state whenever tier progresses.
Net.getEvent(Net.Events.SeasonUpdate).OnClientEvent:Connect(function(payload: unknown)
	local info = payload :: {
		SeasonXP: number,
		SeasonTierGranted: number,
		HasPremiumPass: boolean,
		EquippedTitle: string,
	}
	hud.setSeasonPass(info)
end)

hud.showLobby()
Camera.toLobby() -- start on the default walk-around camera in the plaza
Warmup.start(hud) -- enable the practice-range prompt (hud lets it hide the lobby)
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

-- ===== Record Mode: one tap/key hides ALL HUD + Roblox core UI for clean clip capture (keeps
-- the brand watermark). For making TikTok/Shorts transformation clips. Toggle: the 🎥 button or
-- the ] key. =====
do
	local UserInputService = game:GetService("UserInputService")
	local StarterGui = game:GetService("StarterGui")
	local pg = player:WaitForChild("PlayerGui")
	local KEEP = { ChoicesWatermark = true, RecordToggle = true } -- never hide these
	local recording = false
	local hidden: { [ScreenGui]: boolean } = {}

	local toggleGui = Instance.new("ScreenGui")
	toggleGui.Name = "RecordToggle"
	toggleGui.ResetOnSpawn = false
	toggleGui.IgnoreGuiInset = true
	toggleGui.DisplayOrder = 50
	toggleGui.Parent = pg

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, 96)
	btn.Size = UDim2.fromOffset(42, 42)
	btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
	btn.BackgroundTransparency = 0.35
	btn.Text = "🎥"
	btn.TextScaled = true
	btn.AutoButtonColor = true
	btn.Parent = toggleGui
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = btn

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(1, 0.5)
	hint.Position = UDim2.new(1, -62, 0, 117)
	hint.Size = UDim2.fromOffset(220, 26)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextColor3 = Color3.fromRGB(255, 120, 120)
	hint.TextStrokeTransparency = 0.4
	hint.TextTransparency = 1
	hint.Text = "● REC — press ] or 🎥 to exit"
	hint.Parent = toggleGui

	local function setCore(on: boolean)
		for _, e in
			{
				Enum.CoreGuiType.Backpack,
				Enum.CoreGuiType.PlayerList,
				Enum.CoreGuiType.Chat,
				Enum.CoreGuiType.EmotesMenu,
			}
		do
			pcall(function()
				StarterGui:SetCoreGuiEnabled(e, on)
			end)
		end
	end

	local function setRecording(on: boolean)
		if on == recording then
			return
		end
		recording = on
		if on then
			hidden = {}
			for _, g in pg:GetChildren() do
				if g:IsA("ScreenGui") and not KEEP[g.Name] and g.Enabled then
					hidden[g] = true
					g.Enabled = false
				end
			end
			setCore(false)
			btn.BackgroundColor3 = Color3.fromRGB(210, 55, 55)
			hint.TextTransparency = 0
			TweenService:Create(hint, TweenInfo.new(2.5), { TextTransparency = 1 }):Play()
		else
			for g in hidden do
				if g and g.Parent then
					g.Enabled = true
				end
			end
			hidden = {}
			setCore(true)
			btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
		end
	end

	btn.Activated:Connect(function()
		setRecording(not recording)
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.RightBracket then
			setRecording(not recording)
		end
	end)
end

-- ===== "PLAY" menu: a prominent launcher so new/solo players instantly find every mode (esp.
-- Would You Rather) and teleport straight to it -- not stuck on a PvP-only Find Match button. =====
do
	local activities = {
		{
			key = "choices",
			emoji = "🤔",
			label = "Would You Rather",
			desc = "Pick doors → transform into legends!",
			featured = true,
		},
		{ key = "freekick", emoji = "🎯", label = "Free Kicks", desc = "Solo target practice" },
		{
			key = "gauntlet",
			emoji = "🧤",
			label = "Keeper Gauntlet",
			desc = "Save 10 shots in a row",
		},
		{
			key = "trivia",
			emoji = "🧠",
			label = "World Cup Trivia",
			desc = "Test your football IQ",
		},
		{
			key = "training",
			emoji = "🏋️",
			label = "Training Grounds",
			desc = "Run to earn coins + XP",
		},
	}

	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 25
	gui.Parent = pg

	local function corner(g: GuiObject, r: number)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = g
	end

	-- modal backdrop + panel (hidden until the launcher is tapped)
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 92 + #activities * 74)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	corner(panel, 18)
	local pstroke = Instance.new("UIStroke")
	pstroke.Color = Color3.fromRGB(255, 200, 70)
	pstroke.Thickness = 3
	pstroke.Parent = panel
	local ppad = Instance.new("UIPadding")
	ppad.PaddingTop = UDim.new(0, 14)
	ppad.PaddingLeft = UDim.new(0, 14)
	ppad.PaddingRight = UDim.new(0, 14)
	ppad.Parent = panel
	local plist = Instance.new("UIListLayout")
	plist.Padding = UDim.new(0, 10)
	plist.SortOrder = Enum.SortOrder.LayoutOrder
	plist.Parent = panel

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 36)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextScaled = true
	heading.TextColor3 = Color3.fromRGB(255, 235, 150)
	heading.Text = "🎮 PICK A MODE"
	heading.LayoutOrder = 0
	heading.Parent = panel

	for i, a in activities do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = if a.featured
			then Color3.fromRGB(40, 70, 50)
			else Color3.fromRGB(28, 32, 46)
		row.AutoButtonColor = true
		row.Text = ""
		row.LayoutOrder = i
		row.Parent = panel
		corner(row, 12)
		if a.featured then
			local rs = Instance.new("UIStroke")
			rs.Color = Color3.fromRGB(120, 230, 150)
			rs.Thickness = 2
			rs.Parent = row
		end
		local em = Instance.new("TextLabel")
		em.Size = UDim2.fromOffset(56, 64)
		em.BackgroundTransparency = 1
		em.Font = Enum.Font.GothamBlack
		em.TextScaled = true
		em.Text = a.emoji
		em.Parent = row
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -150, 0, 30)
		name.Position = UDim2.fromOffset(60, 8)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Color3.fromRGB(255, 255, 255)
		name.Text = a.label .. (if a.featured then "  ⭐" else "")
		name.Parent = row
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -150, 0, 20)
		desc.Position = UDim2.fromOffset(60, 38)
		desc.BackgroundTransparency = 1
		desc.Font = Enum.Font.Gotham
		desc.TextScaled = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextColor3 = Color3.fromRGB(180, 190, 210)
		desc.Text = a.desc
		desc.Parent = row
		local go = Instance.new("TextLabel")
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -12, 0.5, 0)
		go.Size = UDim2.fromOffset(60, 30)
		go.BackgroundTransparency = 1
		go.Font = Enum.Font.GothamBlack
		go.TextScaled = true
		go.TextColor3 = Color3.fromRGB(120, 230, 150)
		go.Text = "GO ▶"
		go.Parent = row
		row.Activated:Connect(function()
			Net.getEvent(Net.Events.GotoActivity):FireServer({ key = a.key })
			backdrop.Visible = false
		end)
	end

	-- the prominent launcher button (top-center, gently pulsing so new players notice it)
	local launch = Instance.new("TextButton")
	launch.AnchorPoint = Vector2.new(0.5, 0)
	launch.Position = UDim2.new(0.5, 0, 0, 92)
	launch.Size = UDim2.fromOffset(280, 50)
	launch.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	launch.Font = Enum.Font.GothamBlack
	launch.TextScaled = true
	launch.TextColor3 = Color3.fromRGB(12, 18, 14)
	launch.Text = "🎮 PLAY — pick a mode"
	launch.Parent = gui
	corner(launch, 12)
	local lstroke = Instance.new("UIStroke")
	lstroke.Color = Color3.fromRGB(255, 255, 255)
	lstroke.Thickness = 2
	lstroke.Transparency = 0.3
	lstroke.Parent = launch
	TweenService:Create(
		launch,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = UDim2.fromOffset(296, 54) }
	):Play()

	launch.Activated:Connect(function()
		backdrop.Visible = true
	end)
	backdrop.Activated:Connect(function()
		backdrop.Visible = false
	end)

	-- hide the launcher during runs / matches so it never clutters those screens
	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		gui.Enabled = not (payload :: { active: boolean }).active
	end)
	Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function()
		gui.Enabled = false
	end)
	Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function()
		gui.Enabled = true
	end)
end

-- ===== Live event banner: an always-on event (Double Coins / XP / Pack Frenzy / Weekend) with a
-- live countdown, top-center, so there's always a "play NOW" reason. =====
do
	local current: { emoji: string, label: string, endsAt: number, key: string }? = nil
	local COLORS = {
		coins = Color3.fromRGB(255, 200, 70),
		xp = Color3.fromRGB(70, 160, 255),
		packs = Color3.fromRGB(190, 100, 255),
		weekend = Color3.fromRGB(255, 90, 120),
	}

	local gui = Instance.new("ScreenGui")
	gui.Name = "LiveEventBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 23
	gui.Parent = player:WaitForChild("PlayerGui")

	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 150)
	pill.Size = UDim2.fromOffset(340, 34)
	pill.BackgroundColor3 = Color3.fromRGB(16, 20, 32)
	pill.BackgroundTransparency = 0.1
	pill.Visible = false
	pill.Parent = gui
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = pill
	local pstroke = Instance.new("UIStroke")
	pstroke.Thickness = 2
	pstroke.Color = Color3.fromRGB(255, 200, 70)
	pstroke.Parent = pill
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = ""
	lbl.Parent = pill
	TweenService:Create(
		pstroke,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.5 }
	):Play()

	local function fmt(sec: number): string
		sec = math.max(0, math.floor(sec))
		local h = math.floor(sec / 3600)
		local m = math.floor((sec % 3600) / 60)
		local s = sec % 60
		return if h > 0
			then string.format("%d:%02d:%02d", h, m, s)
			else string.format("%d:%02d", m, s)
	end

	Net.getEvent(Net.Events.LiveEvent).OnClientEvent:Connect(function(payload: unknown)
		current = payload :: typeof(current)
		if current then
			local color = COLORS[current.key] or Color3.fromRGB(255, 200, 70)
			pstroke.Color = color
			lbl.TextColor3 = color
			pill.Visible = true
		end
	end)

	task.spawn(function()
		while true do
			if current and pill.Visible then
				lbl.Text = string.format(
					"%s %s · ends in %s",
					current.emoji,
					current.label,
					fmt(current.endsAt - os.time())
				)
			end
			task.wait(1)
		end
	end)

	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		gui.Enabled = not (payload :: { active: boolean }).active
	end)
	Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function()
		gui.Enabled = false
	end)
	Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function()
		gui.Enabled = true
	end)
end

-- ===== Idle Football Club: a passive coin earner (the daily return hook). The button flips to a
-- green "💰 +X" when coins have piled up; the panel banks them + upgrades the earn rate. =====
do
	local pg = player:WaitForChild("PlayerGui")
	local info = { level = 1, ratePerHr = 0, pending = 0, cap = 0, upgradeCost = 0, coins = 0 }
	local syncClock = os.clock()

	local function rounded(g: GuiObject, r: number)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = g
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "FootballClub"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 24
	gui.Parent = pg

	-- the launcher button (top-right, under the 🎥 record button)
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, 150)
	btn.Size = UDim2.fromOffset(140, 42)
	btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
	btn.BackgroundTransparency = 0.1
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.fromRGB(255, 235, 150)
	btn.Text = "🏟️ CLUB"
	btn.Parent = gui
	rounded(btn, 10)

	-- modal panel
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 340)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	rounded(panel, 18)
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(255, 200, 70)
	ps.Thickness = 3
	ps.Parent = panel

	local function mk(
		y: number,
		h: number,
		font: Enum.Font,
		color: Color3,
		scaled: boolean
	): TextLabel
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -28, 0, h)
		t.Position = UDim2.fromOffset(14, y)
		t.BackgroundTransparency = 1
		t.Font = font
		t.TextScaled = scaled
		t.TextColor3 = color
		t.Text = ""
		t.Parent = panel
		return t
	end
	local titleLbl = mk(14, 30, Enum.Font.GothamBlack, Color3.fromRGB(255, 235, 150), true)
	titleLbl.Text = "🏟️ MY FOOTBALL CLUB"
	local levelLbl = mk(50, 24, Enum.Font.GothamBold, Color3.fromRGB(210, 218, 230), true)
	local pendingLbl = mk(86, 56, Enum.Font.GothamBlack, Color3.fromRGB(120, 230, 150), true)
	local capLbl = mk(146, 20, Enum.Font.Gotham, Color3.fromRGB(160, 170, 190), true)

	local claimBtn = Instance.new("TextButton")
	claimBtn.Position = UDim2.fromOffset(14, 182)
	claimBtn.Size = UDim2.new(1, -28, 0, 52)
	claimBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	claimBtn.Font = Enum.Font.GothamBlack
	claimBtn.TextScaled = true
	claimBtn.TextColor3 = Color3.fromRGB(12, 18, 14)
	claimBtn.Text = "💰 CLAIM"
	claimBtn.Parent = panel
	rounded(claimBtn, 12)

	local upgradeBtn = Instance.new("TextButton")
	upgradeBtn.Position = UDim2.fromOffset(14, 244)
	upgradeBtn.Size = UDim2.new(1, -28, 0, 46)
	upgradeBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 230)
	upgradeBtn.Font = Enum.Font.GothamBold
	upgradeBtn.TextScaled = true
	upgradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	upgradeBtn.Text = "⬆️ Upgrade"
	upgradeBtn.Parent = panel
	rounded(upgradeBtn, 12)

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -10, 0, 10)
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.fromRGB(220, 226, 236)
	closeBtn.Text = "✕"
	closeBtn.Parent = panel
	rounded(closeBtn, 8)

	local function ratePerSec(): number
		return info.ratePerHr / 3600
	end
	local function livePending(): number
		return math.min(info.pending + (os.clock() - syncClock) * ratePerSec(), info.cap)
	end
	local function refresh()
		levelLbl.Text =
			string.format("Level %d  ·  Earning %d 🪙/hr", info.level, info.ratePerHr)
		pendingLbl.Text = "💰 " .. tostring(math.floor(livePending()))
		capLbl.Text = string.format("banked at %d max — claim before it fills!", info.cap)
		upgradeBtn.Text = string.format("⬆️ Upgrade earn rate — %d 🪙", info.upgradeCost)
	end

	Net.getEvent(Net.Events.ClubState).OnClientEvent:Connect(function(payload: unknown)
		info = payload :: typeof(info)
		syncClock = os.clock()
		refresh()
	end)
	claimBtn.Activated:Connect(function()
		Net.getEvent(Net.Events.ClubAction):FireServer({ action = "claim" })
	end)
	upgradeBtn.Activated:Connect(function()
		Net.getEvent(Net.Events.ClubAction):FireServer({ action = "upgrade" })
	end)
	btn.Activated:Connect(function()
		refresh()
		backdrop.Visible = true
	end)
	backdrop.Activated:Connect(function()
		backdrop.Visible = false
	end)
	closeBtn.Activated:Connect(function()
		backdrop.Visible = false
	end)

	-- ticking loop: flip the button to a green "💰 +X" when a worthwhile pile has built up
	task.spawn(function()
		while true do
			local p = math.floor(livePending())
			local worth = math.max(200, info.ratePerHr / 12) -- ~5 minutes of earnings
			if p >= worth then
				btn.Text = if p >= 1000
					then string.format("💰 +%.1fk", p / 1000)
					else ("💰 +" .. tostring(p))
				btn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
				btn.TextColor3 = Color3.fromRGB(12, 18, 14)
			else
				btn.Text = "🏟️ CLUB"
				btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
				btn.TextColor3 = Color3.fromRGB(255, 235, 150)
			end
			if backdrop.Visible then
				refresh()
			end
			task.wait(1)
		end
	end)

	-- hide during runs / matches
	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		gui.Enabled = not (payload :: { active: boolean }).active
	end)
	Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function()
		gui.Enabled = false
	end)
	Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function()
		gui.Enabled = true
	end)
end

-- ===== Collectible cards: a 🃏 CARDS button (badge when packs are ready) opens a collection grid
-- with an OPEN PACK button + a reveal. Earning + completing the set keeps players grinding. =====
do
	local CardBank = require(Shared:WaitForChild("CardBank"))
	local pg = player:WaitForChild("PlayerGui")
	local owned: { [string]: number } = {}
	local packs = 0

	local function rounded(g: GuiObject, r: number)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = g
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Cards"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 24
	gui.Parent = pg

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, 202)
	btn.Size = UDim2.fromOffset(140, 42)
	btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
	btn.BackgroundTransparency = 0.1
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.fromRGB(255, 235, 150)
	btn.Text = "🃏 CARDS"
	btn.Parent = gui
	rounded(btn, 10)

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(470, 520)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	rounded(panel, 18)
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(255, 200, 70)
	ps.Thickness = 3
	ps.Parent = panel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -28, 0, 30)
	titleLbl.Position = UDim2.fromOffset(14, 12)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextScaled = true
	titleLbl.TextColor3 = Color3.fromRGB(255, 235, 150)
	titleLbl.Text = "🃏 MY CARDS"
	titleLbl.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(14, 52)
	scroll.Size = UDim2.new(1, -28, 1, -126)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(102, 78)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	type Tile = { frame: Frame, name: TextLabel, count: TextLabel }
	local tiles: { [string]: Tile } = {}
	for i, c in CardBank.Cards do
		local rarity = CardBank.RarityColor[c.rarity] or Color3.fromRGB(150, 150, 150)
		local tile = Instance.new("Frame")
		tile.BackgroundColor3 = Color3.fromRGB(26, 30, 44)
		tile.LayoutOrder = (CardBank.RarityOrder[c.rarity] or 9) * 100 + i
		tile.Parent = scroll
		rounded(tile, 8)
		local ts = Instance.new("UIStroke")
		ts.Color = rarity
		ts.Thickness = 2
		ts.Parent = tile
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.fromScale(0.92, 0.7)
		nm.Position = UDim2.fromScale(0.04, 0.06)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold
		nm.TextScaled = true
		nm.TextWrapped = true
		nm.TextColor3 = Color3.fromRGB(255, 255, 255)
		nm.Text = c.name
		nm.Parent = tile
		local rl = Instance.new("TextLabel")
		rl.Size = UDim2.fromScale(0.92, 0.22)
		rl.Position = UDim2.fromScale(0.04, 0.76)
		rl.BackgroundTransparency = 1
		rl.Font = Enum.Font.GothamBold
		rl.TextScaled = true
		rl.TextColor3 = rarity
		rl.Text = CardBank.RarityLabel[c.rarity] or ""
		rl.Parent = tile
		local cnt = Instance.new("TextLabel")
		cnt.AnchorPoint = Vector2.new(1, 0)
		cnt.Position = UDim2.fromScale(0.97, 0.04)
		cnt.Size = UDim2.fromScale(0.3, 0.22)
		cnt.BackgroundTransparency = 1
		cnt.Font = Enum.Font.GothamBlack
		cnt.TextScaled = true
		cnt.TextXAlignment = Enum.TextXAlignment.Right
		cnt.TextColor3 = Color3.fromRGB(255, 235, 150)
		cnt.Text = ""
		cnt.Visible = false
		cnt.Parent = tile
		tiles[c.id] = { frame = tile, name = nm, count = cnt }
	end

	local openBtn = Instance.new("TextButton")
	openBtn.AnchorPoint = Vector2.new(0.5, 1)
	openBtn.Position = UDim2.new(0.5, 0, 1, -14)
	openBtn.Size = UDim2.new(1, -28, 0, 52)
	openBtn.Font = Enum.Font.GothamBlack
	openBtn.TextScaled = true
	openBtn.TextColor3 = Color3.fromRGB(12, 18, 14)
	openBtn.Text = "🎁 OPEN PACK"
	openBtn.Parent = panel
	rounded(openBtn, 12)

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -10, 0, 10)
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.fromRGB(220, 226, 236)
	closeBtn.Text = "✕"
	closeBtn.Parent = panel
	rounded(closeBtn, 8)

	local function refresh()
		local distinct = 0
		for _ in owned do
			distinct += 1
		end
		titleLbl.Text = string.format("🃏 MY CARDS  (%d/%d)", distinct, CardBank.count())
		for id, t in tiles do
			local n = owned[id] or 0
			t.frame.BackgroundTransparency = if n > 0 then 0.05 else 0.65
			t.name.TextTransparency = if n > 0 then 0 else 0.55
			t.count.Text = "x" .. tostring(n)
			t.count.Visible = n > 1
		end
		if packs > 0 then
			openBtn.Text = string.format("🎁 OPEN PACK  (%d)", packs)
			openBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
			btn.Text = "🃏 OPEN " .. tostring(packs)
			btn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
			btn.TextColor3 = Color3.fromRGB(12, 18, 14)
		else
			openBtn.Text = "No packs — play to earn one!"
			openBtn.BackgroundColor3 = Color3.fromRGB(50, 54, 70)
			btn.Text = "🃏 CARDS"
			btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
			btn.TextColor3 = Color3.fromRGB(255, 235, 150)
		end
	end

	-- pack-open reveal overlay
	local revealBg = Instance.new("TextButton")
	revealBg.Size = UDim2.fromScale(1, 1)
	revealBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	revealBg.BackgroundTransparency = 0.3
	revealBg.Text = ""
	revealBg.AutoButtonColor = false
	revealBg.Visible = false
	revealBg.ZIndex = 5
	revealBg.Parent = gui
	local revealRow = Instance.new("Frame")
	revealRow.AnchorPoint = Vector2.new(0.5, 0.5)
	revealRow.Position = UDim2.fromScale(0.5, 0.5)
	revealRow.Size = UDim2.fromOffset(360, 200)
	revealRow.BackgroundTransparency = 1
	revealRow.ZIndex = 6
	revealRow.Parent = revealBg
	local revealLayout = Instance.new("UIListLayout")
	revealLayout.FillDirection = Enum.FillDirection.Horizontal
	revealLayout.Padding = UDim.new(0, 10)
	revealLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	revealLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	revealLayout.Parent = revealRow
	revealBg.Activated:Connect(function()
		revealBg.Visible = false
	end)

	local function showReveal(rolled: { string }, newIds: { [string]: boolean })
		for _, ch in revealRow:GetChildren() do
			if ch:IsA("Frame") then
				ch:Destroy()
			end
		end
		for _, id in rolled do
			local c = CardBank.byId(id)
			if c then
				local rarity = CardBank.RarityColor[c.rarity] or Color3.fromRGB(150, 150, 150)
				local card = Instance.new("Frame")
				card.Size = UDim2.fromOffset(108, 150)
				card.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
				card.ZIndex = 6
				card.Parent = revealRow
				rounded(card, 10)
				local cs = Instance.new("UIStroke")
				cs.Color = rarity
				cs.Thickness = 3
				cs.Parent = card
				local nm = Instance.new("TextLabel")
				nm.Size = UDim2.fromScale(0.9, 0.6)
				nm.Position = UDim2.fromScale(0.05, 0.08)
				nm.BackgroundTransparency = 1
				nm.Font = Enum.Font.GothamBold
				nm.TextScaled = true
				nm.TextWrapped = true
				nm.TextColor3 = Color3.fromRGB(255, 255, 255)
				nm.Text = c.name
				nm.ZIndex = 7
				nm.Parent = card
				local rl = Instance.new("TextLabel")
				rl.Size = UDim2.fromScale(0.9, 0.16)
				rl.Position = UDim2.fromScale(0.05, 0.74)
				rl.BackgroundTransparency = 1
				rl.Font = Enum.Font.GothamBlack
				rl.TextScaled = true
				rl.TextColor3 = rarity
				rl.Text = if newIds[id] then "✨ NEW" else CardBank.RarityLabel[c.rarity]
				rl.ZIndex = 7
				rl.Parent = card
				card.Size = UDim2.fromOffset(10, 150)
				TweenService:Create(
					card,
					TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(108, 150) }
				):Play()
			end
		end
		revealBg.Visible = true
		task.delay(4, function()
			revealBg.Visible = false
		end)
	end

	Net.getEvent(Net.Events.CardState).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: { owned: { [string]: number }, packs: number }
		owned = info.owned or {}
		packs = info.packs or 0
		refresh()
	end)
	Net.getEvent(Net.Events.CardOpened).OnClientEvent:Connect(function(payload: unknown)
		local r = payload :: { rolled: { string }, newIds: { [string]: boolean } }
		showReveal(r.rolled or {}, r.newIds or {})
	end)
	openBtn.Activated:Connect(function()
		if packs > 0 then
			Net.getEvent(Net.Events.CardOpen):FireServer()
		end
	end)
	btn.Activated:Connect(function()
		refresh()
		backdrop.Visible = true
	end)
	backdrop.Activated:Connect(function()
		backdrop.Visible = false
	end)
	closeBtn.Activated:Connect(function()
		backdrop.Visible = false
	end)

	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		gui.Enabled = not (payload :: { active: boolean }).active
	end)
	Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function()
		gui.Enabled = false
	end)
	Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function()
		gui.Enabled = true
	end)
end

-- ===== Daily Deals store: a 🛒 DEALS button opens a rotating coin store (3 deals, resets daily).
-- A live "resets in Xh" countdown drives the FOMO; deals already bought today show "CLAIMED". =====
do
	type Deal = {
		id: string,
		label: string,
		emoji: string,
		desc: string,
		price: number,
		tag: string?,
	}
	local pg = player:WaitForChild("PlayerGui")
	local myCoins = 0
	local resetsAt = 0
	local deals: { Deal } = {}
	local bought: { [string]: boolean } = {}

	local function rounded(g: GuiObject, r: number)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = g
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DailyDeals"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 24
	gui.Parent = pg

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, 254)
	btn.Size = UDim2.fromOffset(140, 42)
	btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
	btn.BackgroundTransparency = 0.1
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.fromRGB(140, 230, 170)
	btn.Text = "🛒 DEALS"
	btn.Parent = gui
	rounded(btn, 10)

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 470)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	rounded(panel, 18)
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(140, 230, 170)
	ps.Thickness = 3
	ps.Parent = panel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -28, 0, 30)
	titleLbl.Position = UDim2.fromOffset(14, 12)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextScaled = true
	titleLbl.TextColor3 = Color3.fromRGB(140, 230, 170)
	titleLbl.Text = "🛒 DAILY DEALS"
	titleLbl.Parent = panel

	local timerLbl = Instance.new("TextLabel")
	timerLbl.Size = UDim2.new(1, -28, 0, 20)
	timerLbl.Position = UDim2.fromOffset(14, 44)
	timerLbl.BackgroundTransparency = 1
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.TextScaled = true
	timerLbl.TextXAlignment = Enum.TextXAlignment.Left
	timerLbl.TextColor3 = Color3.fromRGB(255, 200, 90)
	timerLbl.Text = ""
	timerLbl.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -10, 0, 10)
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Text = "✕"
	closeBtn.Parent = panel
	rounded(closeBtn, 8)

	local list = Instance.new("Frame")
	list.Position = UDim2.fromOffset(14, 76)
	list.Size = UDim2.new(1, -28, 1, -90)
	list.BackgroundTransparency = 1
	list.Parent = panel
	local vlist = Instance.new("UIListLayout")
	vlist.Padding = UDim.new(0, 12)
	vlist.SortOrder = Enum.SortOrder.LayoutOrder
	vlist.Parent = list

	-- One row per deal. Rebuilt whenever a fresh StoreState arrives.
	local function render()
		for _, c in list:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, deal in deals do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 118)
			row.BackgroundColor3 = Color3.fromRGB(26, 30, 44)
			row.LayoutOrder = i
			row.Parent = list
			rounded(row, 12)

			local emoji = Instance.new("TextLabel")
			emoji.Position = UDim2.fromOffset(12, 0)
			emoji.Size = UDim2.fromOffset(64, 118)
			emoji.BackgroundTransparency = 1
			emoji.Font = Enum.Font.GothamBlack
			emoji.TextScaled = true
			emoji.Text = deal.emoji
			emoji.Parent = row

			local name = Instance.new("TextLabel")
			name.Position = UDim2.fromOffset(84, 14)
			name.Size = UDim2.new(1, -200, 0, 26)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBlack
			name.TextScaled = true
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextColor3 = Color3.fromRGB(255, 255, 255)
			name.Text = deal.label
			name.Parent = row

			local desc = Instance.new("TextLabel")
			desc.Position = UDim2.fromOffset(84, 44)
			desc.Size = UDim2.new(1, -200, 0, 22)
			desc.BackgroundTransparency = 1
			desc.Font = Enum.Font.GothamMedium
			desc.TextScaled = true
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextColor3 = Color3.fromRGB(180, 188, 205)
			desc.Text = deal.desc
			desc.Parent = row

			if deal.tag then
				local tag = Instance.new("TextLabel")
				tag.AnchorPoint = Vector2.new(1, 0)
				tag.Position = UDim2.new(1, -12, 0, 12)
				tag.Size = UDim2.fromOffset(96, 22)
				tag.BackgroundColor3 = Color3.fromRGB(255, 90, 120)
				tag.Font = Enum.Font.GothamBlack
				tag.TextScaled = true
				tag.TextColor3 = Color3.fromRGB(255, 255, 255)
				tag.Text = deal.tag
				tag.Parent = row
				rounded(tag, 6)
			end

			local buy = Instance.new("TextButton")
			buy.AnchorPoint = Vector2.new(1, 1)
			buy.Position = UDim2.new(1, -12, 1, -12)
			buy.Size = UDim2.fromOffset(150, 40)
			buy.Font = Enum.Font.GothamBlack
			buy.TextScaled = true
			buy.Parent = row
			rounded(buy, 10)

			local function paint()
				if bought[deal.id] then
					buy.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
					buy.TextColor3 = Color3.fromRGB(150, 158, 170)
					buy.Text = "✓ CLAIMED"
					buy.AutoButtonColor = false
				elseif myCoins < deal.price then
					buy.BackgroundColor3 = Color3.fromRGB(54, 40, 44)
					buy.TextColor3 = Color3.fromRGB(255, 150, 150)
					buy.Text = string.format("🪙 %d", deal.price)
					buy.AutoButtonColor = false
				else
					buy.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
					buy.TextColor3 = Color3.fromRGB(255, 255, 255)
					buy.Text = string.format("🪙 %d", deal.price)
					buy.AutoButtonColor = true
				end
			end
			paint()

			buy.Activated:Connect(function()
				if bought[deal.id] or myCoins < deal.price then
					return
				end
				buy.Text = "..."
				buy.AutoButtonColor = false
				Net.getEvent(Net.Events.StoreBuy):FireServer({ id = deal.id })
			end)
		end
	end

	local function fmt(sec: number): string
		sec = math.max(0, math.floor(sec))
		local h = math.floor(sec / 3600)
		local m = math.floor((sec % 3600) / 60)
		return string.format("⏳ New deals in %dh %02dm", h, m)
	end

	Net.getEvent(Net.Events.StoreState).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: {
			coins: number,
			bought: { [string]: boolean },
			resetsAt: number,
			deals: { Deal },
		}
		myCoins = info.coins or 0
		bought = info.bought or {}
		resetsAt = info.resetsAt or 0
		deals = info.deals or {}
		render()
	end)

	task.spawn(function()
		while true do
			if resetsAt > 0 then
				timerLbl.Text = fmt(resetsAt - os.time())
			end
			task.wait(20)
		end
	end)

	btn.Activated:Connect(function()
		backdrop.Visible = true
	end)
	backdrop.Activated:Connect(function()
		backdrop.Visible = false
	end)
	closeBtn.Activated:Connect(function()
		backdrop.Visible = false
	end)

	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		gui.Enabled = not (payload :: { active: boolean }).active
	end)
	Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function()
		gui.Enabled = false
	end)
	Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function()
		gui.Enabled = true
	end)
end

-- ===== Weekly tournament: a 🏆 RANKED button opens the live ladder -- your points + rank, the top
-- 10, the prize ladder, and a countdown to the weekly reset. Top finishers are paid coins/packs. ==
do
	type Row = { name: string, value: number }
	type Prize = { rank: number, coins: number, packs: number }
	local pg = player:WaitForChild("PlayerGui")
	local resetsAt = 0
	local myPoints = 0
	local myRank = 0
	local standings: { Row } = {}
	local prizes: { Prize } = {}
	local medals = { "🥇", "🥈", "🥉" }

	local function rounded(g: GuiObject, r: number)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = g
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Tournament"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 24
	gui.Parent = pg

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, 306)
	btn.Size = UDim2.fromOffset(140, 42)
	btn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
	btn.BackgroundTransparency = 0.1
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.fromRGB(255, 215, 120)
	btn.Text = "🏆 RANKED"
	btn.Parent = gui
	rounded(btn, 10)

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 540)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	rounded(panel, 18)
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(255, 215, 120)
	ps.Thickness = 3
	ps.Parent = panel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -28, 0, 28)
	titleLbl.Position = UDim2.fromOffset(14, 12)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextScaled = true
	titleLbl.TextColor3 = Color3.fromRGB(255, 215, 120)
	titleLbl.Text = "🏆 WEEKLY TOURNAMENT"
	titleLbl.Parent = panel

	local timerLbl = Instance.new("TextLabel")
	timerLbl.Size = UDim2.new(1, -28, 0, 18)
	timerLbl.Position = UDim2.fromOffset(14, 42)
	timerLbl.BackgroundTransparency = 1
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.TextScaled = true
	timerLbl.TextColor3 = Color3.fromRGB(255, 150, 150)
	timerLbl.Text = ""
	timerLbl.Parent = panel

	local youLbl = Instance.new("TextLabel")
	youLbl.Size = UDim2.new(1, -28, 0, 32)
	youLbl.Position = UDim2.fromOffset(14, 66)
	youLbl.BackgroundColor3 = Color3.fromRGB(30, 36, 54)
	youLbl.Font = Enum.Font.GothamBlack
	youLbl.TextScaled = true
	youLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	youLbl.Text = ""
	youLbl.Parent = panel
	rounded(youLbl, 8)

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -10, 0, 10)
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Text = "✕"
	closeBtn.Parent = panel
	rounded(closeBtn, 8)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(14, 108)
	scroll.Size = UDim2.new(1, -28, 1, -122)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	local vlist = Instance.new("UIListLayout")
	vlist.Padding = UDim.new(0, 6)
	vlist.SortOrder = Enum.SortOrder.LayoutOrder
	vlist.Parent = scroll

	local function render()
		for _, c in scroll:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		if myRank > 0 then
			youLbl.Text = string.format("YOU: #%d  ·  %d pts", myRank, myPoints)
		else
			youLbl.Text = string.format("YOU: unranked  ·  %d pts — keep playing!", myPoints)
		end
		-- One row per top-N entry, with the prize for that rank if any.
		local count = math.max(#standings, #prizes)
		for i = 1, count do
			local row = standings[i]
			local prize = prizes[i]
			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(1, 0, 0, 40)
			frame.BackgroundColor3 = Color3.fromRGB(26, 30, 44)
			frame.LayoutOrder = i
			frame.Parent = scroll
			rounded(frame, 8)
			if myRank == i then
				local hs = Instance.new("UIStroke")
				hs.Color = Color3.fromRGB(255, 215, 120)
				hs.Thickness = 2
				hs.Parent = frame
			end

			local rankLbl = Instance.new("TextLabel")
			rankLbl.Position = UDim2.fromOffset(8, 0)
			rankLbl.Size = UDim2.fromOffset(44, 40)
			rankLbl.BackgroundTransparency = 1
			rankLbl.Font = Enum.Font.GothamBlack
			rankLbl.TextScaled = true
			rankLbl.TextColor3 = Color3.fromRGB(255, 215, 120)
			rankLbl.Text = medals[i] or ("#" .. i)
			rankLbl.Parent = frame

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Position = UDim2.fromOffset(56, 0)
			nameLbl.Size = UDim2.new(1, -210, 1, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextScaled = true
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextColor3 = Color3.fromRGB(235, 240, 250)
			nameLbl.Text = if row then row.name else "—"
			nameLbl.Parent = frame

			local ptsLbl = Instance.new("TextLabel")
			ptsLbl.AnchorPoint = Vector2.new(1, 0)
			ptsLbl.Position = UDim2.new(1, -110, 0, 0)
			ptsLbl.Size = UDim2.fromOffset(90, 40)
			ptsLbl.BackgroundTransparency = 1
			ptsLbl.Font = Enum.Font.GothamBold
			ptsLbl.TextScaled = true
			ptsLbl.TextXAlignment = Enum.TextXAlignment.Right
			ptsLbl.TextColor3 = Color3.fromRGB(180, 188, 205)
			ptsLbl.Text = if row then string.format("%d", row.value) else ""
			ptsLbl.Parent = frame

			if prize then
				local prizeLbl = Instance.new("TextLabel")
				prizeLbl.AnchorPoint = Vector2.new(1, 0.5)
				prizeLbl.Position = UDim2.new(1, -8, 0.5, 0)
				prizeLbl.Size = UDim2.fromOffset(98, 34)
				prizeLbl.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
				prizeLbl.Font = Enum.Font.GothamBlack
				prizeLbl.TextScaled = true
				prizeLbl.TextColor3 = Color3.fromRGB(140, 230, 170)
				local packTxt = if prize.packs > 0 then "+" .. prize.packs .. "🃏" else ""
				prizeLbl.Text = string.format("🪙%d %s", prize.coins, packTxt)
				prizeLbl.Parent = frame
				rounded(prizeLbl, 6)
			end
		end
	end

	local function fmt(sec: number): string
		sec = math.max(0, math.floor(sec))
		local d = math.floor(sec / 86400)
		local h = math.floor((sec % 86400) / 3600)
		local m = math.floor((sec % 3600) / 60)
		if d > 0 then
			return string.format("⏳ Resets in %dd %dh", d, h)
		end
		return string.format("⏳ Resets in %dh %02dm", h, m)
	end

	Net.getEvent(Net.Events.TournamentState).OnClientEvent:Connect(function(payload: unknown)
		local info = payload :: {
			points: number,
			rank: number,
			resetsAt: number,
			standings: { Row },
			prizes: { Prize },
		}
		myPoints = info.points or 0
		myRank = info.rank or 0
		resetsAt = info.resetsAt or 0
		standings = info.standings or {}
		prizes = info.prizes or {}
		if backdrop.Visible then
			render()
		end
	end)

	task.spawn(function()
		while true do
			if resetsAt > 0 then
				timerLbl.Text = fmt(resetsAt - os.time())
			end
			task.wait(30)
		end
	end)

	btn.Activated:Connect(function()
		render()
		backdrop.Visible = true
	end)
	backdrop.Activated:Connect(function()
		backdrop.Visible = false
	end)
	closeBtn.Activated:Connect(function()
		backdrop.Visible = false
	end)

	Net.getEvent(Net.Events.ChoicesMode).OnClientEvent:Connect(function(payload: unknown)
		gui.Enabled = not (payload :: { active: boolean }).active
	end)
	Net.getEvent(Net.Events.RoundStart).OnClientEvent:Connect(function()
		gui.Enabled = false
	end)
	Net.getEvent(Net.Events.MatchOver).OnClientEvent:Connect(function()
		gui.Enabled = true
	end)
end

-- ===== Growth nudge: after a win / Choices finish, a small reminder to Like + Favorite (boosts
-- Roblox discovery) and a one-tap Invite Friends button (social/viral loop). No reward is tied to
-- liking (Roblox policy) -- it's a pure reminder. Self-throttled so it never spams. =====
do
	local SocialService = game:GetService("SocialService")
	local COOLDOWN = 200 -- seconds between nudges
	local lastShown = -math.huge

	local gui = Instance.new("ScreenGui")
	gui.Name = "GrowthNudge"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 22
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -170)
	panel.Size = UDim2.fromOffset(380, 110)
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
	panel.BackgroundTransparency = 0.08
	panel.Parent = gui
	local pcorner = Instance.new("UICorner")
	pcorner.CornerRadius = UDim.new(0, 14)
	pcorner.Parent = panel
	local pstroke = Instance.new("UIStroke")
	pstroke.Color = Color3.fromRGB(255, 200, 70)
	pstroke.Thickness = 2
	pstroke.Parent = panel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -20, 0, 24)
	titleLbl.Position = UDim2.fromOffset(12, 8)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextScaled = true
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextColor3 = Color3.fromRGB(255, 235, 150)
	titleLbl.Text = "Enjoying Penalty Kings? ⚽"
	titleLbl.Parent = panel

	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(1, -20, 0, 22)
	subLbl.Position = UDim2.fromOffset(12, 34)
	subLbl.BackgroundTransparency = 1
	subLbl.Font = Enum.Font.GothamMedium
	subLbl.TextScaled = true
	subLbl.TextXAlignment = Enum.TextXAlignment.Left
	subLbl.TextColor3 = Color3.fromRGB(210, 218, 230)
	subLbl.Text = "Smash 👍 Like & ⭐ Favorite — it really helps us grow!"
	subLbl.Parent = panel

	local inviteBtn = Instance.new("TextButton")
	inviteBtn.AnchorPoint = Vector2.new(0, 1)
	inviteBtn.Position = UDim2.new(0, 12, 1, -10)
	inviteBtn.Size = UDim2.fromOffset(214, 34)
	inviteBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	inviteBtn.Font = Enum.Font.GothamBold
	inviteBtn.TextScaled = true
	inviteBtn.TextColor3 = Color3.fromRGB(15, 20, 15)
	inviteBtn.Text = "🎁 Invite Friends"
	inviteBtn.Parent = panel
	local ibc = Instance.new("UICorner")
	ibc.CornerRadius = UDim.new(0, 8)
	ibc.Parent = inviteBtn

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 1)
	closeBtn.Position = UDim2.new(1, -12, 1, -10)
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.fromRGB(220, 226, 236)
	closeBtn.Text = "✕"
	closeBtn.Parent = panel
	local cbc = Instance.new("UICorner")
	cbc.CornerRadius = UDim.new(0, 8)
	cbc.Parent = closeBtn

	inviteBtn.Activated:Connect(function()
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end)
	closeBtn.Activated:Connect(function()
		gui.Enabled = false
	end)

	showGrowthNudge = function()
		if os.clock() - lastShown < COOLDOWN then
			return
		end
		lastShown = os.clock()
		gui.Enabled = true
		local shownAt = lastShown
		task.delay(10, function()
			if lastShown == shownAt then
				gui.Enabled = false
			end
		end)
	end
end

print("[PenaltyKings] Client ready (PvP).")
