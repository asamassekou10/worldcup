--!strict
-- UI: the whole HUD, built in code. Two screens that toggle:
--   * Lobby  -- FIND MATCH button + queue status
--   * Match  -- scoreboard, round/role banner, countdown, aim grid, power bar
--             (shooter only), and the SHOOT/DIVE button.
-- Mobile-first: big touch targets, scale-based layout, anchored corners.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Progression = require(Shared:WaitForChild("Progression"))
local WorldCup = require(Shared:WaitForChild("WorldCup"))
local Theme = require(Shared:WaitForChild("Theme"))

local Sound = require(script.Parent:WaitForChild("Sound"))
local Venue = require(script.Parent:WaitForChild("Venue"))

local UI = {}

local ACCENT = Theme.Accent
local PANEL = Theme.Panel
local POWER_SPEED = 1.4 -- full sweeps of the power bar per second

export type Hud = {
	onQueueButton: (() -> ())?,
	onSubmit: (() -> ())?,
	onBackToLobby: (() -> ())?,
	onBuy: ((id: string) -> ())?,
	onEquip: ((id: string) -> ())?,
	onBuyCoins: ((productId: number) -> ())?,
	onBuyDoubler: (() -> ())?,
	onChallenge: ((targetUserId: number) -> ())?,
	onChallengeRespond: ((fromUserId: number, accept: boolean) -> ())?,
	onEmote: ((emoji: string) -> ())?,
	openShop: () -> (),
	openRanks: () -> (),
	openStore: () -> (),
	showChallengeInvite: (fromUserId: number, fromName: string) -> (),
	getInput: () -> { x: number, y: number, power: number, curve: number },
	setProfile: (data: Types.ProfileData) -> (),
	setLeaderboard: (data: Types.LeaderboardData) -> (),
	setMonetization: (info: Types.MonetizationInfo) -> (),
	notify: (message: string) -> (),
	showLobby: () -> (),
	setQueue: (inQueue: boolean, size: number) -> (),
	startRound: (info: Types.RoundStartInfo) -> (),
	showRoundResult: (info: Types.RoundResultInfo) -> (),
	showMatchOver: (info: Types.MatchOverInfo) -> (),
}

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

-- A soft drop shadow behind a widget (graceful no-op if the asset can't load).
local function shadow(widget: GuiObject, transparency: number?)
	local img = Instance.new("ImageLabel")
	img.Name = "Shadow"
	img.BackgroundTransparency = 1
	img.Image = Theme.Shadow
	img.ImageColor3 = Color3.fromRGB(0, 0, 0)
	img.ImageTransparency = transparency or 0.55
	img.ScaleType = Enum.ScaleType.Slice
	img.SliceCenter = Rect.new(10, 10, 118, 118)
	img.Size = UDim2.new(1, 30, 1, 30)
	img.Position = UDim2.fromOffset(-15, -15)
	img.ZIndex = widget.ZIndex - 1
	img.Parent = widget
end

-- A vertical gradient (top -> bottom) for depth. Works on frames AND text.
local function gradient(widget: GuiObject, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = widget
	return g
end

-- Add a satisfying press/release scale-pop to a button (mobile + desktop).
local function pressable(button: GuiButton)
	button.AutoButtonColor = false
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function tween(s: number, style: Enum.EasingStyle)
		TweenService
			:Create(scale, TweenInfo.new(0.12, style, Enum.EasingDirection.Out), { Scale = s })
			:Play()
	end
	button.MouseButton1Down:Connect(function()
		tween(0.94, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Up:Connect(function()
		tween(1, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		tween(1, Enum.EasingStyle.Quad)
	end)
end

local function lighten(c: Color3, amt: number): Color3
	return Color3.new(math.min(c.R + amt, 1), math.min(c.G + amt, 1), math.min(c.B + amt, 1))
end

-- Turn a plain TextButton into a polished gradient button: a gradient fill drawn
-- BEHIND the text (so it isn't tinted), a soft shadow, an outline, and press-pop.
-- `primary` uses the accent colours. Idempotent (skips if already done).
local function polish(button: GuiButton, primary: boolean?)
	if button:FindFirstChild("Fill") then
		return
	end
	local base = button.BackgroundColor3
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	if button.ZIndex < 2 then
		button.ZIndex = 2
	end
	local existing = button:FindFirstChildOfClass("UICorner")
	local rad = if existing then existing.CornerRadius.Offset else 12

	local sh = Instance.new("ImageLabel")
	sh.Name = "Shadow"
	sh.BackgroundTransparency = 1
	sh.Image = Theme.Shadow
	sh.ImageColor3 = Color3.fromRGB(0, 0, 0)
	sh.ImageTransparency = if primary then 0.4 else 0.6
	sh.ScaleType = Enum.ScaleType.Slice
	sh.SliceCenter = Rect.new(10, 10, 118, 118)
	sh.Size = UDim2.new(1, 30, 1, 30)
	sh.Position = UDim2.fromOffset(-15, -15)
	sh.ZIndex = button.ZIndex - 2
	sh.Parent = button

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = base
	fill.BorderSizePixel = 0
	fill.ZIndex = button.ZIndex - 1
	corner(fill, rad)
	if primary then
		gradient(fill, Theme.Accent, Theme.AccentDark)
	else
		gradient(fill, lighten(base, 0.06), base)
	end
	local st = Instance.new("UIStroke")
	st.Color = if primary then Color3.fromRGB(255, 255, 255) else Theme.Stroke
	st.Transparency = if primary then 0.65 else 0.35
	st.Thickness = if primary then 2 else 1
	st.Parent = fill
	fill.Parent = button

	pressable(button)
end

-- Consistent panel chrome: an accent underline bar beneath a (left-aligned) title
-- and a polished close button.
local function decoratePanel(panel: GuiObject, title: TextLabel, close: GuiButton?)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0.14, 0.007)
	bar.Position =
		UDim2.fromScale(title.Position.X.Scale, title.Position.Y.Scale + title.Size.Y.Scale + 0.004)
	bar.BackgroundColor3 = Theme.Accent
	bar.BorderSizePixel = 0
	corner(bar, 4)
	gradient(bar, Theme.Accent, Theme.Gold, 0)
	bar.Parent = panel
	if close then
		polish(close, false)
	end
end

-- Show a full-screen panel with a quick centred scale-in pop.
local function showPanel(panel: GuiObject)
	panel.AnchorPoint = Vector2.new(0.5, 0.5) -- so the scale grows from the centre
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Visible = true
	local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = panel
	scale.Scale = 0.96
	TweenService
		:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		:Play()
end

function UI.create(player: Player): Hud
	local self = {
		onQueueButton = nil :: (() -> ())?,
		onSubmit = nil :: (() -> ())?,
		onBackToLobby = nil :: (() -> ())?,
		onBuy = nil :: ((id: string) -> ())?,
		onEquip = nil :: ((id: string) -> ())?,
		onBuyCoins = nil :: ((productId: number) -> ())?,
		onBuyDoubler = nil :: (() -> ())?,
		onChallenge = nil :: ((targetUserId: number) -> ())?,
		onChallengeRespond = nil :: ((fromUserId: number, accept: boolean) -> ())?,
		onEmote = nil :: ((emoji: string) -> ())?,
	}

	local screen = Instance.new("ScreenGui")
	screen.Name = "PenaltyKingsHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = player:WaitForChild("PlayerGui")

	-- ============================ LOBBY HUD ============================
	-- A transparent full-screen container so the festival plaza shows through.
	-- (Plain Frames don't capture input, so walking / the PLAY prompt still work.)
	local lobby = Instance.new("Frame")
	lobby.Name = "Lobby"
	lobby.Size = UDim2.fromScale(1, 1)
	lobby.BackgroundTransparency = 1
	lobby.Parent = screen

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.5, 0.09)
	title.Position = UDim2.fromScale(0.25, 0.04)
	title.BackgroundTransparency = 1
	title.Font = Theme.FontTitle
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "⚽ PENALTY KINGS 👑"
	title.Parent = lobby
	gradient(title, Color3.fromRGB(255, 240, 200), Theme.Gold) -- gold sheen
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(20, 24, 32)
	titleStroke.Thickness = 3
	titleStroke.Parent = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.fromScale(0.46, 0.035)
	subtitle.Position = UDim2.fromScale(0.27, 0.14)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(190, 200, 215)
	subtitle.TextStrokeTransparency = 0.5
	subtitle.Text = "Free-for-all Penalties · up to 8 players"
	subtitle.Parent = lobby

	-- Nation identity: front-and-center so repping your country is the first thing
	-- a new player does. Tapping it opens the nation picker (the shop).
	local nationChip = Instance.new("TextButton")
	nationChip.Size = UDim2.fromScale(0.34, 0.06)
	nationChip.Position = UDim2.fromScale(0.33, 0.185)
	nationChip.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
	nationChip.BackgroundTransparency = 0.1
	nationChip.Font = Enum.Font.GothamBold
	nationChip.TextScaled = true
	nationChip.TextColor3 = Color3.fromRGB(255, 255, 255)
	nationChip.Text = "🌍 Pick your country"
	corner(nationChip, 12)
	local nationChipStroke = Instance.new("UIStroke")
	nationChipStroke.Color = ACCENT
	nationChipStroke.Thickness = 2
	nationChipStroke.Parent = nationChip
	nationChip.Parent = lobby
	shadow(nationChip, 0.6)
	pressable(nationChip)

	-- Matchday spotlight banner (Phase 4 live-ops). Tracks the real World Cup
	-- calendar; tap to open the fixtures panel.
	local featuredBanner = Instance.new("TextButton")
	featuredBanner.Size = UDim2.fromScale(0.6, 0.04)
	featuredBanner.Position = UDim2.fromScale(0.2, 0.25)
	featuredBanner.BackgroundTransparency = 1
	featuredBanner.Font = Enum.Font.GothamBold
	featuredBanner.TextScaled = true
	featuredBanner.TextColor3 = Color3.fromRGB(255, 170, 60)
	featuredBanner.TextStrokeTransparency = 0.5
	featuredBanner.Text = WorldCup.featuredText()
	featuredBanner.Parent = lobby

	-- "Your nation's next match" countdown (set from the equipped nation).
	local nextMatchLabel = Instance.new("TextLabel")
	nextMatchLabel.Size = UDim2.fromScale(0.6, 0.035)
	nextMatchLabel.Position = UDim2.fromScale(0.2, 0.295)
	nextMatchLabel.BackgroundTransparency = 1
	nextMatchLabel.Font = Enum.Font.GothamBold
	nextMatchLabel.TextScaled = true
	nextMatchLabel.TextColor3 = Color3.fromRGB(120, 230, 150)
	nextMatchLabel.TextStrokeTransparency = 0.5
	nextMatchLabel.Text = ""
	nextMatchLabel.Parent = lobby

	-- Coins + win/loss record (filled by ProfileUpdate), top-left HUD.
	local lobbyStats = Instance.new("TextLabel")
	lobbyStats.Size = UDim2.fromScale(0.5, 0.05)
	lobbyStats.Position = UDim2.fromScale(0.02, 0.09) -- below the Roblox topbar buttons
	lobbyStats.BackgroundTransparency = 1
	lobbyStats.Font = Enum.Font.GothamBold
	lobbyStats.TextScaled = true
	lobbyStats.TextXAlignment = Enum.TextXAlignment.Left
	lobbyStats.TextColor3 = Color3.fromRGB(240, 200, 40)
	lobbyStats.TextStrokeTransparency = 0.5
	lobbyStats.Text = "💰 …"
	lobbyStats.Parent = lobby

	local findButton = Instance.new("TextButton")
	findButton.Size = UDim2.fromScale(0.32, 0.1)
	findButton.Position = UDim2.fromScale(0.34, 0.72)
	findButton.BackgroundColor3 = ACCENT
	findButton.Font = Enum.Font.GothamBlack
	findButton.TextScaled = true
	findButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	findButton.Text = "FIND MATCH"
	corner(findButton, 14)
	local findStroke = Instance.new("UIStroke")
	findStroke.Color = Color3.fromRGB(255, 255, 255)
	findStroke.Transparency = 0.7
	findStroke.Thickness = 2
	findStroke.Parent = findButton
	findButton.Parent = lobby
	shadow(findButton, 0.4)
	pressable(findButton)

	local lobbyStatus = Instance.new("TextLabel")
	lobbyStatus.Size = UDim2.fromScale(0.6, 0.04)
	lobbyStatus.Position = UDim2.fromScale(0.2, 0.68)
	lobbyStatus.BackgroundTransparency = 1
	lobbyStatus.Font = Enum.Font.Gotham
	lobbyStatus.TextScaled = true
	lobbyStatus.TextColor3 = Color3.fromRGB(170, 180, 200)
	lobbyStatus.TextStrokeTransparency = 0.5
	lobbyStatus.Text = ""
	lobbyStatus.Parent = lobby

	-- Menu buttons across the bottom of the lobby.
	local function menuButton(text: string, xScale: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromScale(0.22, 0.08)
		btn.Position = UDim2.fromScale(xScale, 0.86)
		btn.BackgroundColor3 = Theme.PanelLight
		btn.Font = Theme.FontBold
		btn.TextScaled = true
		btn.TextColor3 = Theme.Text
		btn.Text = text
		corner(btn, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Stroke
		stroke.Thickness = 1
		stroke.Parent = btn
		btn.Parent = lobby
		shadow(btn, 0.65)
		pressable(btn)
		btn.Activated:Connect(function()
			Sound.play("Click")
		end)
		return btn
	end

	local shopButton = menuButton("🛒 SHOP", 0.03)
	local boardButton = menuButton("🏆 RANKS", 0.265)
	local storeButton = menuButton("💎 STORE", 0.5)
	local challengeButton = menuButton("⚔️ 1V1", 0.735)

	findButton.Activated:Connect(function()
		Sound.play("Click")
		if self.onQueueButton then
			self.onQueueButton()
		end
	end)

	-- Level + XP bar (progression), top-left under the coins/record line.
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.fromScale(0.22, 0.04)
	levelLabel.Position = UDim2.fromScale(0.02, 0.145)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = Enum.Font.GothamBlack
	levelLabel.TextScaled = true
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.TextColor3 = Color3.fromRGB(120, 210, 255)
	levelLabel.TextStrokeTransparency = 0.5
	levelLabel.Text = "⭐ LV 1"
	levelLabel.Parent = lobby

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Size = UDim2.fromScale(0.22, 0.016)
	xpBarBg.Position = UDim2.fromScale(0.02, 0.19)
	xpBarBg.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
	corner(xpBarBg, 6)
	xpBarBg.Parent = lobby
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(120, 210, 255)
	corner(xpFill, 6)
	xpFill.Parent = xpBarBg

	-- Daily quests card (right side): always visible so it drives play sessions.
	local questsCard = Instance.new("Frame")
	questsCard.Size = UDim2.fromScale(0.27, 0.4)
	questsCard.Position = UDim2.fromScale(0.71, 0.28)
	questsCard.BackgroundColor3 = PANEL
	questsCard.BackgroundTransparency = 0.25
	corner(questsCard, 12)
	questsCard.Parent = lobby

	local questsTitle = Instance.new("TextLabel")
	questsTitle.Size = UDim2.fromScale(0.92, 0.13)
	questsTitle.Position = UDim2.fromScale(0.04, 0.04)
	questsTitle.BackgroundTransparency = 1
	questsTitle.Font = Enum.Font.GothamBlack
	questsTitle.TextScaled = true
	questsTitle.TextXAlignment = Enum.TextXAlignment.Left
	questsTitle.TextColor3 = Color3.fromRGB(240, 200, 40)
	questsTitle.Text = "🎯 TODAY'S QUESTS"
	questsTitle.Parent = questsCard

	local streakLabel = Instance.new("TextLabel")
	streakLabel.Size = UDim2.fromScale(0.92, 0.09)
	streakLabel.Position = UDim2.fromScale(0.04, 0.17)
	streakLabel.BackgroundTransparency = 1
	streakLabel.Font = Enum.Font.GothamBold
	streakLabel.TextScaled = true
	streakLabel.TextXAlignment = Enum.TextXAlignment.Left
	streakLabel.TextColor3 = Color3.fromRGB(255, 150, 60)
	streakLabel.Text = "🔥 1 day streak"
	streakLabel.Parent = questsCard

	local questFills: { Frame } = {}
	local questCounts: { TextLabel } = {}
	for i, quest in Progression.Quests do
		local y = 0.3 + (i - 1) * 0.23
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.92, 0.08)
		label.Position = UDim2.fromScale(0.04, y)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(225, 228, 238)
		label.Text = string.format(quest.label, quest.target)
		label.Parent = questsCard

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.fromScale(0.72, 0.05)
		barBg.Position = UDim2.fromScale(0.04, y + 0.09)
		barBg.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
		corner(barBg, 6)
		barBg.Parent = questsCard
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = ACCENT
		corner(fill, 6)
		fill.Parent = barBg
		questFills[i] = fill

		local count = Instance.new("TextLabel")
		count.Size = UDim2.fromScale(0.22, 0.07)
		count.Position = UDim2.fromScale(0.78, y + 0.085)
		count.BackgroundTransparency = 1
		count.Font = Enum.Font.GothamBold
		count.TextScaled = true
		count.TextColor3 = Color3.fromRGB(200, 205, 220)
		count.Text = "0/" .. quest.target
		count.Parent = questsCard
		questCounts[i] = count
	end

	local function questProgress(data: Types.ProfileData, stat: string): number
		if stat == "goals" then
			return data.QuestGoals
		elseif stat == "wins" then
			return data.QuestWins
		end
		return data.QuestSaves
	end

	local function renderProgression(data: Types.ProfileData)
		local _, _, frac = Progression.levelProgress(data.XP)
		levelLabel.Text = if Progression.isBonusWeekend()
			then "⭐ LV " .. Progression.levelFromXp(data.XP) .. "   🔥 2× XP"
			else "⭐ LV " .. Progression.levelFromXp(data.XP)
		xpFill.Size = UDim2.fromScale(frac, 1)
		streakLabel.Text = string.format("🔥 %d day streak", math.max(data.LoginStreak, 1))
		for i, quest in Progression.Quests do
			local prog = math.min(questProgress(data, quest.stat), quest.target)
			questFills[i].Size = UDim2.fromScale(prog / quest.target, 1)
			local done = prog >= quest.target
			questCounts[i].Text = if done then "✓" else string.format("%d/%d", prog, quest.target)
			questCounts[i].TextColor3 = if done
				then Color3.fromRGB(60, 220, 110)
				else Color3.fromRGB(200, 205, 220)
		end
	end

	-- ============================ MATCH SCREEN ===========================
	local match = Instance.new("Frame")
	match.Name = "Match"
	match.Size = UDim2.fromScale(1, 1)
	match.BackgroundTransparency = 1
	match.Visible = false
	match.Parent = screen

	-- Matchup (top center): who's shooting vs keeping this turn.
	local score = Instance.new("TextLabel")
	score.Size = UDim2.fromScale(0.5, 0.08)
	score.Position = UDim2.fromScale(0.25, 0.02)
	score.BackgroundTransparency = 0.35
	score.BackgroundColor3 = PANEL
	score.Font = Enum.Font.GothamBold
	score.TextScaled = true
	score.TextColor3 = Color3.fromRGB(255, 255, 255)
	score.Text = ""
	corner(score)
	score.Parent = match

	-- Turn counter
	local roundLabel = Instance.new("TextLabel")
	roundLabel.Size = UDim2.fromScale(0.5, 0.04)
	roundLabel.Position = UDim2.fromScale(0.25, 0.105)
	roundLabel.BackgroundTransparency = 1
	roundLabel.Font = Enum.Font.GothamMedium
	roundLabel.TextScaled = true
	roundLabel.TextColor3 = Color3.fromRGB(200, 205, 220)
	roundLabel.Text = ""
	roundLabel.Parent = match

	-- Live standings table (top-left): every player ranked by goals.
	local standings = Instance.new("Frame")
	standings.Size = UDim2.fromScale(0.22, 0.32)
	standings.Position = UDim2.fromScale(0.02, 0.16)
	standings.BackgroundTransparency = 0.4
	standings.BackgroundColor3 = PANEL
	corner(standings)
	standings.Parent = match

	local standingsTitle = Instance.new("TextLabel")
	standingsTitle.Size = UDim2.new(1, 0, 0, 22)
	standingsTitle.BackgroundTransparency = 1
	standingsTitle.Font = Enum.Font.GothamBold
	standingsTitle.TextScaled = true
	standingsTitle.TextColor3 = Color3.fromRGB(240, 200, 40)
	standingsTitle.Text = "STANDINGS"
	standingsTitle.Parent = standings

	local standingsList = Instance.new("Frame")
	standingsList.Size = UDim2.new(1, -8, 1, -26)
	standingsList.Position = UDim2.fromOffset(4, 24)
	standingsList.BackgroundTransparency = 1
	standingsList.Parent = standings

	local standingsLayout = Instance.new("UIListLayout")
	standingsLayout.Padding = UDim.new(0, 2)
	standingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	standingsLayout.Parent = standingsList

	-- Repopulate the standings table from a ranked list.
	local function setStandings(entries: { Types.StandingEntry })
		for _, child in standingsList:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for rank, entry in entries do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 18)
			row.LayoutOrder = rank
			row.BackgroundTransparency = if entry.isYou then 0.3 else 1
			row.BackgroundColor3 = Color3.fromRGB(40, 120, 70)
			row.Font = if entry.isYou then Enum.Font.GothamBold else Enum.Font.Gotham
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = Color3.fromRGB(235, 235, 235)
			row.Text = string.format(" %d. %s — %d", rank, entry.name, entry.goals)
			corner(row, 4)
			row.Parent = standingsList
		end
	end

	-- Role banner
	local banner = Instance.new("TextLabel")
	banner.Size = UDim2.fromScale(0.6, 0.08)
	banner.Position = UDim2.fromScale(0.2, 0.18)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack
	banner.TextScaled = true
	banner.TextStrokeTransparency = 0.4
	banner.Text = ""
	banner.Parent = match

	-- Countdown timer
	local timer = Instance.new("TextLabel")
	timer.Size = UDim2.fromScale(0.2, 0.06)
	timer.Position = UDim2.fromScale(0.4, 0.27)
	timer.BackgroundTransparency = 1
	timer.Font = Enum.Font.GothamBold
	timer.TextScaled = true
	timer.TextColor3 = Color3.fromRGB(255, 230, 120)
	timer.Text = ""
	timer.Parent = match

	-- Result flash
	local result = Instance.new("TextLabel")
	result.Size = UDim2.fromScale(0.6, 0.16)
	result.Position = UDim2.fromScale(0.2, 0.36)
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.GothamBlack
	result.TextScaled = true
	result.TextStrokeTransparency = 0.3
	result.TextTransparency = 1
	result.Text = ""
	result.Parent = match
	local resultScale = Instance.new("UIScale")
	resultScale.Scale = 1
	resultScale.Parent = result

	-- Aim hint, kept at the foot of the screen so the goal + keeper stay clear.
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromScale(0.5, 0.035)
	hint.Position = UDim2.fromScale(0.25, 0.9)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextScaled = true
	hint.TextColor3 = Color3.fromRGB(210, 215, 230)
	hint.TextStrokeTransparency = 0.5
	hint.Text = "Drag to aim"
	hint.Parent = match

	-- One-time coach card above the goal: explains the new mechanic on a player's
	-- first shot / first keep, then never nags again this session.
	local coach = Instance.new("TextLabel")
	coach.Size = UDim2.fromScale(0.5, 0.07)
	coach.Position = UDim2.fromScale(0.25, 0.38)
	coach.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	coach.BackgroundTransparency = 0.1
	coach.Font = Enum.Font.GothamBold
	coach.TextScaled = true
	coach.TextColor3 = Color3.fromRGB(255, 240, 180)
	coach.TextWrapped = true
	coach.Text = ""
	coach.Visible = false
	coach.ZIndex = 6
	corner(coach)
	coach.Parent = match
	local coachToken = 0
	local coachedShooter, coachedKeeper = false, false
	local function showCoach(message: string)
		coach.Text = message
		coach.Visible = true
		coachToken += 1
		local myToken = coachToken
		task.delay(4.5, function()
			if coachToken == myToken then
				coach.Visible = false
			end
		end)
	end

	-- Aim directly on the REAL goal. The player drags anywhere on screen; we
	-- raycast the camera ray onto the goal plane to get a continuous (x,y), then
	-- pin a billboard crosshair at that exact spot in the world. The actual goal
	-- and keeper stay fully visible -- no rectangle in the way.
	local aimX, aimY = 0, 0.5
	local curve = 0 -- -1..1 bend on the shot (set by the curve slider, shooter only)

	-- A tiny invisible part the reticle billboard rides on (client-only, so each
	-- player sees only their own crosshair). Billboards track the camera for us,
	-- so there's no projection/GUI-inset math to get wrong.
	local function makeMarkerGui(): BillboardGui
		local part = Instance.new("Part")
		part.Name = "PKAimMarker"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = workspace
		local bb = Instance.new("BillboardGui")
		bb.Name = "PKReticle"
		bb.Adornee = part
		bb.Size = UDim2.fromOffset(56, 56)
		bb.AlwaysOnTop = true
		bb.Enabled = false
		bb.Parent = part
		return bb
	end

	local aimBillboard = makeMarkerGui()
	local aimPart = aimBillboard.Adornee :: Part

	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromScale(1, 1)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundTransparency = 1
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = ACCENT
	ringStroke.Thickness = 3
	ringStroke.Parent = ring
	ring.Parent = aimBillboard

	local ringPulse = Instance.new("UIScale")
	ringPulse.Parent = ring
	TweenService:Create(
		ringPulse,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.18 }
	):Play()

	-- Crosshair ticks (N/S/E/W) for a sharper targeting look.
	local function tick(size: UDim2, pos: UDim2)
		local t = Instance.new("Frame")
		t.Size = size
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = pos
		t.BackgroundColor3 = ACCENT
		t.BorderSizePixel = 0
		t.Parent = aimBillboard
	end
	tick(UDim2.fromOffset(2, 8), UDim2.fromScale(0.5, 0.02))
	tick(UDim2.fromOffset(2, 8), UDim2.fromScale(0.5, 0.98))
	tick(UDim2.fromOffset(8, 2), UDim2.fromScale(0.02, 0.5))
	tick(UDim2.fromOffset(8, 2), UDim2.fromScale(0.98, 0.5))

	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(12, 12)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.BackgroundColor3 = ACCENT
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Color3.fromRGB(255, 255, 255)
	dotStroke.Thickness = 2
	dotStroke.Parent = dot
	dot.Parent = aimBillboard

	local function pinMarker()
		local p = Venue.goalPointWorld(aimX, aimY)
		if p then
			aimPart.Position = p
		end
	end

	local aiming = false
	local aimEnabled = false
	local function setAimEnabled(on: boolean)
		aimEnabled = on
		aimBillboard.Enabled = on
		if on then
			pinMarker()
		end
	end

	-- Screen point -> goal (x,y): intersect the camera ray with the goal plane.
	local function aimFromScreen(px: number, py: number)
		local cam = workspace.CurrentCamera
		local frame = Venue.goalCFrame()
		if not cam or not frame then
			return
		end
		local ray = cam:ViewportPointToRay(px, py)
		local normal = frame.LookVector -- goal plane faces the shooter
		local denom = ray.Direction:Dot(normal)
		if math.abs(denom) < 1e-4 then
			return
		end
		local t = (frame.Position - ray.Origin):Dot(normal) / denom
		if t <= 0 then
			return
		end
		local hit = ray.Origin + ray.Direction * t
		local gx, gy = Venue.worldToGoalPoint(hit)
		if not gx or not gy then
			return
		end
		aimX = math.clamp(gx, -1.25, 1.25)
		aimY = math.clamp(gy, 0, 1.25)
		pinMarker()
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not aimEnabled then
			return -- ignore taps that land on a button (SHOOT/menus)
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			aiming = true
			aimFromScreen(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			aiming
			and aimEnabled
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			aimFromScreen(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			aiming = false
		end
	end)
	local function resetAim()
		aiming = false
		aimX, aimY = 0, 0.5
		pinMarker()
	end

	-- Power bar (only meaningful/visible for the shooter).
	local powerBg = Instance.new("Frame")
	powerBg.Size = UDim2.fromScale(0.4, 0.05)
	powerBg.Position = UDim2.fromScale(0.42, 0.8)
	powerBg.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
	corner(powerBg)
	powerBg.Parent = match

	local powerFill = Instance.new("Frame")
	powerFill.Size = UDim2.fromScale(0.5, 1)
	powerFill.BackgroundColor3 = Color3.fromRGB(240, 200, 40)
	corner(powerFill)
	powerFill.Parent = powerBg

	-- Curve slider (shooter only): drag the handle to bend the shot left/right.
	-- A button so the aim raycast ignores taps that land on it (gameProcessed).
	local curveTrack = Instance.new("TextButton")
	curveTrack.Size = UDim2.fromScale(0.34, 0.04)
	curveTrack.Position = UDim2.fromScale(0.45, 0.72)
	curveTrack.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
	curveTrack.AutoButtonColor = false
	curveTrack.Text = ""
	corner(curveTrack)
	curveTrack.Parent = match

	local curveCaption = Instance.new("TextLabel")
	curveCaption.Size = UDim2.fromScale(1, 0.9)
	curveCaption.Position = UDim2.fromScale(0, 0.05)
	curveCaption.BackgroundTransparency = 1
	curveCaption.Font = Enum.Font.GothamMedium
	curveCaption.TextScaled = true
	curveCaption.TextTransparency = 0.45
	curveCaption.TextColor3 = Color3.fromRGB(210, 215, 230)
	curveCaption.Text = "◀  CURVE  ▶"
	curveCaption.Parent = curveTrack

	local curveHandle = Instance.new("Frame")
	curveHandle.Size = UDim2.fromOffset(14, 22)
	curveHandle.AnchorPoint = Vector2.new(0.5, 0.5)
	curveHandle.Position = UDim2.fromScale(0.5, 0.5)
	curveHandle.BackgroundColor3 = ACCENT
	curveHandle.ZIndex = 2
	corner(curveHandle, 4)
	curveHandle.Parent = curveTrack

	local curving = false
	local function setCurveFromX(px: number)
		local rel = px - curveTrack.AbsolutePosition.X
		local f = math.clamp(rel / math.max(curveTrack.AbsoluteSize.X, 1), 0, 1)
		curve = f * 2 - 1
		curveHandle.Position = UDim2.fromScale(f, 0.5)
	end
	local function resetCurve()
		curving = false
		curve = 0
		curveHandle.Position = UDim2.fromScale(0.5, 0.5)
	end
	curveTrack.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			curving = true
			setCurveFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			curving
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			setCurveFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			curving = false
		end
	end)

	-- Action button (SHOOT / DIVE), bottom right.
	local action = Instance.new("TextButton")
	action.Size = UDim2.fromScale(0.18, 0.12)
	action.Position = UDim2.fromScale(0.78, 0.76)
	action.BackgroundColor3 = ACCENT
	action.Font = Enum.Font.GothamBlack
	action.TextScaled = true
	action.TextColor3 = Color3.fromRGB(255, 255, 255)
	action.Text = "SHOOT"
	corner(action, 12)
	local actionStroke = Instance.new("UIStroke")
	actionStroke.Color = Color3.fromRGB(255, 255, 255)
	actionStroke.Transparency = 0.7
	actionStroke.Thickness = 2
	actionStroke.Parent = action
	action.Parent = match
	shadow(action, 0.45)
	pressable(action)

	-- Waiting-for-opponent label (after you submit)
	local waiting = Instance.new("TextLabel")
	waiting.Size = UDim2.fromScale(0.4, 0.05)
	waiting.Position = UDim2.fromScale(0.42, 0.74)
	waiting.BackgroundTransparency = 1
	waiting.Font = Enum.Font.GothamMedium
	waiting.TextScaled = true
	waiting.TextColor3 = Color3.fromRGB(200, 205, 220)
	waiting.Text = ""
	waiting.Parent = match

	-- Emote bar (everyone, during a match): tap to pop a taunt over your head.
	local emoteBar = Instance.new("Frame")
	emoteBar.Size = UDim2.fromScale(0.4, 0.06)
	emoteBar.Position = UDim2.fromScale(0.02, 0.91)
	emoteBar.BackgroundTransparency = 1
	emoteBar.Parent = match
	local emoteLayout = Instance.new("UIListLayout")
	emoteLayout.FillDirection = Enum.FillDirection.Horizontal
	emoteLayout.Padding = UDim.new(0, 6)
	emoteLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	emoteLayout.Parent = emoteBar
	for _, emoji in Config.Emotes do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(46, 46)
		btn.BackgroundColor3 = Color3.fromRGB(30, 33, 44)
		btn.BackgroundTransparency = 0.2
		btn.Font = Enum.Font.GothamBold
		btn.TextScaled = true
		btn.Text = emoji
		corner(btn, 10)
		btn.Parent = emoteBar
		btn.Activated:Connect(function()
			if self.onEmote then
				self.onEmote(emoji)
			end
		end)
	end

	-- Broadcast "VS" intro: the two names slide in from the sides and clash, then
	-- clear -- played at the top of every turn.
	local vsCard = Instance.new("Frame")
	vsCard.Size = UDim2.fromScale(1, 1)
	vsCard.BackgroundTransparency = 1
	vsCard.Visible = false
	vsCard.ZIndex = 20
	vsCard.Parent = match

	local function vsPlate(anchorX: number): TextLabel
		local p = Instance.new("TextLabel")
		p.Size = UDim2.fromScale(0.4, 0.1)
		p.AnchorPoint = Vector2.new(anchorX, 0.5)
		p.BackgroundColor3 = PANEL
		p.BackgroundTransparency = 0.1
		p.Font = Enum.Font.GothamBlack
		p.TextScaled = true
		p.TextColor3 = Color3.fromRGB(255, 255, 255)
		p.ZIndex = 20
		corner(p, 10)
		p.Parent = vsCard
		return p
	end
	local vsShooter = vsPlate(0)
	local vsKeeper = vsPlate(1)

	local vsLabel = Instance.new("TextLabel")
	vsLabel.Size = UDim2.fromScale(0.12, 0.1)
	vsLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	vsLabel.Position = UDim2.fromScale(0.5, 0.34)
	vsLabel.BackgroundTransparency = 1
	vsLabel.Font = Enum.Font.GothamBlack
	vsLabel.TextScaled = true
	vsLabel.TextColor3 = Color3.fromRGB(255, 210, 60)
	vsLabel.TextStrokeTransparency = 0.2
	vsLabel.Text = "VS"
	vsLabel.ZIndex = 21
	vsLabel.Parent = vsCard
	local vsLabelScale = Instance.new("UIScale")
	vsLabelScale.Parent = vsLabel

	-- ========================= MATCH-OVER PANEL =========================
	local overPanel = Instance.new("Frame")
	overPanel.Size = UDim2.fromScale(1, 1)
	overPanel.BackgroundColor3 = Theme.Bg
	gradient(overPanel, Color3.fromRGB(30, 40, 58), Theme.Bg)
	overPanel.BackgroundTransparency = 0.2
	overPanel.Visible = false
	overPanel.Parent = screen

	local overTitle = Instance.new("TextLabel")
	overTitle.Size = UDim2.fromScale(0.8, 0.12)
	overTitle.Position = UDim2.fromScale(0.1, 0.12)
	overTitle.BackgroundTransparency = 1
	overTitle.Font = Enum.Font.GothamBlack
	overTitle.TextScaled = true
	overTitle.Text = ""
	overTitle.Parent = overPanel

	-- Victory-card line: your nation + your goals this match (a screenshot moment).
	local overNation = Instance.new("TextLabel")
	overNation.Size = UDim2.fromScale(0.8, 0.05)
	overNation.Position = UDim2.fromScale(0.1, 0.235)
	overNation.BackgroundTransparency = 1
	overNation.Font = Enum.Font.GothamBold
	overNation.TextScaled = true
	overNation.TextColor3 = Color3.fromRGB(240, 200, 40)
	overNation.Text = ""
	overNation.Parent = overPanel

	local overShare = Instance.new("TextLabel")
	overShare.Size = UDim2.fromScale(0.8, 0.04)
	overShare.Position = UDim2.fromScale(0.1, 0.71)
	overShare.BackgroundTransparency = 1
	overShare.Font = Enum.Font.GothamMedium
	overShare.TextScaled = true
	overShare.TextColor3 = Color3.fromRGB(160, 200, 255)
	overShare.Text = "📸 Screenshot & share!  #PenaltyKings"
	overShare.Parent = overPanel

	-- Final standings (multi-line, top-aligned so up to 8 rows fit).
	local overScore = Instance.new("TextLabel")
	overScore.Size = UDim2.fromScale(0.5, 0.45)
	overScore.Position = UDim2.fromScale(0.25, 0.27)
	overScore.BackgroundTransparency = 1
	overScore.Font = Enum.Font.GothamMedium
	overScore.TextSize = 22
	overScore.TextWrapped = true
	overScore.TextYAlignment = Enum.TextYAlignment.Top
	overScore.TextColor3 = Color3.fromRGB(210, 215, 228)
	overScore.Text = ""
	overScore.Parent = overPanel

	local backButton = Instance.new("TextButton")
	backButton.Size = UDim2.fromScale(0.36, 0.1)
	backButton.Position = UDim2.fromScale(0.32, 0.78)
	backButton.BackgroundColor3 = ACCENT
	backButton.Font = Enum.Font.GothamBlack
	backButton.TextScaled = true
	backButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	backButton.Text = "BACK TO LOBBY"
	corner(backButton, 12)
	backButton.Parent = overPanel
	polish(backButton, true)

	-- ============================== SHOP ===============================
	local latestProfile: Types.ProfileData? = nil

	local shopPanel = Instance.new("Frame")
	shopPanel.Size = UDim2.fromScale(1, 1)
	shopPanel.BackgroundColor3 = Theme.Bg
	gradient(shopPanel, Color3.fromRGB(28, 36, 52), Theme.Bg)
	shopPanel.BackgroundTransparency = 0.05
	shopPanel.Visible = false
	shopPanel.Parent = screen

	local shopTitle = Instance.new("TextLabel")
	shopTitle.Size = UDim2.fromScale(0.5, 0.09)
	shopTitle.Position = UDim2.fromScale(0.06, 0.04)
	shopTitle.BackgroundTransparency = 1
	shopTitle.Font = Enum.Font.GothamBlack
	shopTitle.TextScaled = true
	shopTitle.TextXAlignment = Enum.TextXAlignment.Left
	shopTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopTitle.Text = "🌍 CHOOSE YOUR COUNTRY"
	shopTitle.Parent = shopPanel

	local shopCoins = Instance.new("TextLabel")
	shopCoins.Size = UDim2.fromScale(0.3, 0.07)
	shopCoins.Position = UDim2.fromScale(0.5, 0.05)
	shopCoins.BackgroundTransparency = 1
	shopCoins.Font = Enum.Font.GothamBold
	shopCoins.TextScaled = true
	shopCoins.TextXAlignment = Enum.TextXAlignment.Right
	shopCoins.TextColor3 = Color3.fromRGB(240, 200, 40)
	shopCoins.Text = ""
	shopCoins.Parent = shopPanel

	local closeShop = Instance.new("TextButton")
	closeShop.Size = UDim2.fromScale(0.1, 0.07)
	closeShop.Position = UDim2.fromScale(0.84, 0.05)
	closeShop.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeShop.Font = Enum.Font.GothamBlack
	closeShop.TextScaled = true
	closeShop.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeShop.Text = "✕"
	corner(closeShop, 10)
	closeShop.Parent = shopPanel
	decoratePanel(shopPanel, shopTitle, closeShop)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.fromScale(0.88, 0.78)
	scroller.Position = UDim2.fromScale(0.06, 0.15)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = shopPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroller

	type ShopRow = { button: TextButton }
	local shopRows: { [string]: ShopRow } = {}

	for index, cosmetic in Catalog.Cosmetics do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.LayoutOrder = index
		row.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
		corner(row)
		row.Parent = scroller

		local emoji = Instance.new("TextLabel")
		emoji.Size = UDim2.fromScale(0.16, 1)
		emoji.BackgroundTransparency = 1
		emoji.Font = Enum.Font.GothamBold
		emoji.TextScaled = true
		emoji.Text = cosmetic.emoji
		emoji.Parent = row

		local name = Instance.new("TextLabel")
		name.Size = UDim2.fromScale(0.45, 1)
		name.Position = UDim2.fromScale(0.18, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Color3.fromRGB(235, 235, 235)
		name.Text = cosmetic.name
		name.Parent = row

		local rowBtn = Instance.new("TextButton")
		rowBtn.Size = UDim2.fromScale(0.3, 0.7)
		rowBtn.Position = UDim2.fromScale(0.67, 0.15)
		rowBtn.Font = Enum.Font.GothamBold
		rowBtn.TextScaled = true
		rowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		corner(rowBtn, 10)
		rowBtn.Parent = row
		pressable(rowBtn)

		rowBtn.Activated:Connect(function()
			Sound.play("Click")
			if not latestProfile then
				return
			end
			local equipped = latestProfile.Equipped == cosmetic.id
			if equipped then
				return
			end
			if Catalog.isOwned(latestProfile, cosmetic.id) then
				if self.onEquip then
					self.onEquip(cosmetic.id)
				end
			elseif self.onBuy then
				self.onBuy(cosmetic.id)
			end
		end)

		shopRows[cosmetic.id] = { button = rowBtn }
	end

	local function refreshShop()
		if latestProfile then
			shopCoins.Text = "💰 " .. latestProfile.Coins
		end
		for _, cosmetic in Catalog.Cosmetics do
			local rowBtn = shopRows[cosmetic.id].button
			local owned = latestProfile ~= nil and Catalog.isOwned(latestProfile, cosmetic.id)
			local equipped = latestProfile ~= nil and latestProfile.Equipped == cosmetic.id
			if equipped then
				rowBtn.Text = "EQUIPPED"
				rowBtn.BackgroundColor3 = Color3.fromRGB(70, 75, 90)
			elseif owned then
				rowBtn.Text = "EQUIP"
				rowBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 210)
			elseif cosmetic.price == 0 then
				rowBtn.Text = "FREE — EQUIP"
				rowBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 210)
			else
				rowBtn.Text = "💰 " .. cosmetic.price
				rowBtn.BackgroundColor3 = ACCENT
			end
		end
	end

	local function openShop()
		lobby.Visible = false
		showPanel(shopPanel)
		refreshShop()
	end
	shopButton.Activated:Connect(openShop)
	nationChip.Activated:Connect(function()
		Sound.play("Click")
		openShop()
	end)
	closeShop.Activated:Connect(function()
		shopPanel.Visible = false
		lobby.Visible = true
	end)

	-- ========================== LEADERBOARD ============================
	local latestBoard: Types.LeaderboardData = { Wins = {}, Coins = {}, Nations = {}, Scorers = {} }

	local boardPanel = Instance.new("Frame")
	boardPanel.Size = UDim2.fromScale(1, 1)
	boardPanel.BackgroundColor3 = Theme.Bg
	gradient(boardPanel, Color3.fromRGB(28, 36, 52), Theme.Bg)
	boardPanel.BackgroundTransparency = 0.05
	boardPanel.Visible = false
	boardPanel.Parent = screen

	local boardTitle = Instance.new("TextLabel")
	boardTitle.Size = UDim2.fromScale(0.6, 0.09)
	boardTitle.Position = UDim2.fromScale(0.06, 0.04)
	boardTitle.BackgroundTransparency = 1
	boardTitle.Font = Enum.Font.GothamBlack
	boardTitle.TextScaled = true
	boardTitle.TextXAlignment = Enum.TextXAlignment.Left
	boardTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	boardTitle.Text = "🏆 WORLD CUP STANDINGS"
	boardTitle.Parent = boardPanel

	local closeBoard = Instance.new("TextButton")
	closeBoard.Size = UDim2.fromScale(0.1, 0.07)
	closeBoard.Position = UDim2.fromScale(0.84, 0.05)
	closeBoard.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeBoard.Font = Enum.Font.GothamBlack
	closeBoard.TextScaled = true
	closeBoard.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBoard.Text = "✕"
	corner(closeBoard, 10)
	closeBoard.Parent = boardPanel
	decoratePanel(boardPanel, boardTitle, closeBoard)

	-- Build one titled column (a header + a scrolling list) and return its list.
	local function buildColumn(heading: string, xScale: number, width: number): ScrollingFrame
		local header = Instance.new("TextLabel")
		header.Size = UDim2.fromScale(width, 0.06)
		header.Position = UDim2.fromScale(xScale, 0.16)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.GothamBold
		header.TextScaled = true
		header.TextColor3 = Color3.fromRGB(240, 200, 40)
		header.Text = heading
		header.Parent = boardPanel

		local column = Instance.new("ScrollingFrame")
		column.Size = UDim2.fromScale(width, 0.72)
		column.Position = UDim2.fromScale(xScale, 0.23)
		column.BackgroundTransparency = 1
		column.BorderSizePixel = 0
		column.ScrollBarThickness = 6
		column.CanvasSize = UDim2.new()
		column.AutomaticCanvasSize = Enum.AutomaticSize.Y
		column.Parent = boardPanel

		local colLayout = Instance.new("UIListLayout")
		colLayout.Padding = UDim.new(0, 6)
		colLayout.SortOrder = Enum.SortOrder.LayoutOrder
		colLayout.Parent = column

		return column
	end

	-- World Cup Standings + Golden Boot lead (the headline boards), then Wins/Coins.
	local nationsColumn = buildColumn("🌍 World Cup", 0.02, 0.23)
	local bootColumn = buildColumn("👟 Golden Boot", 0.26, 0.23)
	local winsColumn = buildColumn("🏆 Most Wins", 0.50, 0.23)
	local coinsColumn = buildColumn("💰 Most Coins", 0.74, 0.23)

	-- Repopulate a column from its entries (rank · name · value).
	local function fillColumn(column: ScrollingFrame, entries: { Types.LeaderEntry })
		for _, child in column:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		if #entries == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, 0, 0, 48)
			empty.BackgroundTransparency = 1
			empty.Font = Enum.Font.Gotham
			empty.TextScaled = true
			empty.TextColor3 = Color3.fromRGB(140, 150, 170)
			empty.Text = "No entries yet — play a match!"
			-- Wrap in a Frame so the "clear Frames" pass can remove it next time.
			local holder = Instance.new("Frame")
			holder.Size = UDim2.new(1, 0, 0, 48)
			holder.BackgroundTransparency = 1
			empty.Parent = holder
			holder.Parent = column
			return
		end

		for rank, entry in entries do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 44)
			row.LayoutOrder = rank
			row.BackgroundColor3 = if rank <= 3
				then Color3.fromRGB(40, 44, 58)
				else Color3.fromRGB(22, 25, 34)
			corner(row)
			row.Parent = column

			local rankLabel = Instance.new("TextLabel")
			rankLabel.Size = UDim2.fromScale(0.18, 1)
			rankLabel.BackgroundTransparency = 1
			rankLabel.Font = Enum.Font.GothamBlack
			rankLabel.TextScaled = true
			rankLabel.TextColor3 = if rank == 1
				then Color3.fromRGB(240, 200, 40)
				else Color3.fromRGB(200, 205, 220)
			rankLabel.Text = "#" .. rank
			rankLabel.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.fromScale(0.52, 1)
			nameLabel.Position = UDim2.fromScale(0.2, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextScaled = true
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
			nameLabel.Text = entry.name
			nameLabel.Parent = row

			local valueLabel = Instance.new("TextLabel")
			valueLabel.Size = UDim2.fromScale(0.26, 1)
			valueLabel.Position = UDim2.fromScale(0.73, 0)
			valueLabel.BackgroundTransparency = 1
			valueLabel.Font = Enum.Font.GothamBold
			valueLabel.TextScaled = true
			valueLabel.TextXAlignment = Enum.TextXAlignment.Right
			valueLabel.TextColor3 = Color3.fromRGB(240, 200, 40)
			valueLabel.Text = tostring(entry.value)
			valueLabel.Parent = row
		end
	end

	local function renderBoard()
		fillColumn(nationsColumn, latestBoard.Nations)
		fillColumn(bootColumn, latestBoard.Scorers)
		fillColumn(winsColumn, latestBoard.Wins)
		fillColumn(coinsColumn, latestBoard.Coins)
	end

	boardButton.Activated:Connect(function()
		lobby.Visible = false
		showPanel(boardPanel)
		renderBoard()
	end)
	closeBoard.Activated:Connect(function()
		boardPanel.Visible = false
		lobby.Visible = true
	end)

	-- ===================== CHALLENGE A FRIEND (1v1) ====================
	local challengePanel = Instance.new("Frame")
	challengePanel.Size = UDim2.fromScale(1, 1)
	challengePanel.BackgroundColor3 = Theme.Bg
	gradient(challengePanel, Color3.fromRGB(28, 36, 52), Theme.Bg)
	challengePanel.BackgroundTransparency = 0.05
	challengePanel.Visible = false
	challengePanel.Parent = screen

	local challengeTitle = Instance.new("TextLabel")
	challengeTitle.Size = UDim2.fromScale(0.7, 0.09)
	challengeTitle.Position = UDim2.fromScale(0.06, 0.04)
	challengeTitle.BackgroundTransparency = 1
	challengeTitle.Font = Enum.Font.GothamBlack
	challengeTitle.TextScaled = true
	challengeTitle.TextXAlignment = Enum.TextXAlignment.Left
	challengeTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	challengeTitle.Text = "⚔️ CHALLENGE A PLAYER"
	challengeTitle.Parent = challengePanel

	local closeChallenge = Instance.new("TextButton")
	closeChallenge.Size = UDim2.fromScale(0.1, 0.07)
	closeChallenge.Position = UDim2.fromScale(0.84, 0.05)
	closeChallenge.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeChallenge.Font = Enum.Font.GothamBlack
	closeChallenge.TextScaled = true
	closeChallenge.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeChallenge.Text = "✕"
	corner(closeChallenge, 10)
	closeChallenge.Parent = challengePanel
	decoratePanel(challengePanel, challengeTitle, closeChallenge)

	local challengeList = Instance.new("ScrollingFrame")
	challengeList.Size = UDim2.fromScale(0.88, 0.78)
	challengeList.Position = UDim2.fromScale(0.06, 0.16)
	challengeList.BackgroundTransparency = 1
	challengeList.BorderSizePixel = 0
	challengeList.ScrollBarThickness = 6
	challengeList.CanvasSize = UDim2.new()
	challengeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	challengeList.Parent = challengePanel
	local challengeLayout = Instance.new("UIListLayout")
	challengeLayout.Padding = UDim.new(0, 8)
	challengeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	challengeLayout.Parent = challengeList

	-- (Re)build the list of other players currently in this server.
	local function refreshChallengeList()
		for _, child in challengeList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local others = 0
		for _, other in Players:GetPlayers() do
			if not rawequal(other, player) then
				others += 1
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 56)
				row.LayoutOrder = others
				row.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
				corner(row)
				row.Parent = challengeList

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Size = UDim2.fromScale(0.6, 1)
				nameLabel.Position = UDim2.fromScale(0.04, 0)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextScaled = true
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
				nameLabel.Text = other.DisplayName
				nameLabel.Parent = row

				local challengeBtn = Instance.new("TextButton")
				challengeBtn.Size = UDim2.fromScale(0.3, 0.7)
				challengeBtn.Position = UDim2.fromScale(0.66, 0.15)
				challengeBtn.BackgroundColor3 = ACCENT
				challengeBtn.Font = Enum.Font.GothamBlack
				challengeBtn.TextScaled = true
				challengeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				challengeBtn.Text = "⚔️ CHALLENGE"
				corner(challengeBtn, 10)
				challengeBtn.Parent = row
				polish(challengeBtn, true)
				local targetId = other.UserId
				challengeBtn.Activated:Connect(function()
					Sound.play("Click")
					if self.onChallenge then
						self.onChallenge(targetId)
					end
					challengePanel.Visible = false
					lobby.Visible = true
				end)
			end
		end
		if others == 0 then
			local empty = Instance.new("Frame")
			empty.Size = UDim2.new(1, 0, 0, 56)
			empty.BackgroundTransparency = 1
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.Gotham
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(140, 150, 170)
			label.Text = "No one else here yet — invite a friend to the game!"
			label.Parent = empty
			empty.Parent = challengeList
		end
	end

	challengeButton.Activated:Connect(function()
		lobby.Visible = false
		showPanel(challengePanel)
		refreshChallengeList()
	end)
	closeChallenge.Activated:Connect(function()
		challengePanel.Visible = false
		lobby.Visible = true
	end)

	-- Incoming-challenge popup (a small modal over whatever screen is up).
	local invitePopup = Instance.new("Frame")
	invitePopup.Size = UDim2.fromScale(0.5, 0.26)
	invitePopup.Position = UDim2.fromScale(0.25, 0.37)
	invitePopup.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	invitePopup.Visible = false
	invitePopup.ZIndex = 60
	corner(invitePopup, 14)
	local inviteStroke = Instance.new("UIStroke")
	inviteStroke.Color = ACCENT
	inviteStroke.Thickness = 3
	inviteStroke.Parent = invitePopup
	invitePopup.Parent = screen

	local inviteText = Instance.new("TextLabel")
	inviteText.Size = UDim2.fromScale(0.9, 0.4)
	inviteText.Position = UDim2.fromScale(0.05, 0.1)
	inviteText.BackgroundTransparency = 1
	inviteText.Font = Enum.Font.GothamBold
	inviteText.TextScaled = true
	inviteText.TextColor3 = Color3.fromRGB(255, 255, 255)
	inviteText.TextWrapped = true
	inviteText.ZIndex = 60
	inviteText.Text = ""
	inviteText.Parent = invitePopup

	local inviteAccept = Instance.new("TextButton")
	inviteAccept.Size = UDim2.fromScale(0.42, 0.32)
	inviteAccept.Position = UDim2.fromScale(0.05, 0.58)
	inviteAccept.BackgroundColor3 = ACCENT
	inviteAccept.Font = Enum.Font.GothamBlack
	inviteAccept.TextScaled = true
	inviteAccept.TextColor3 = Color3.fromRGB(255, 255, 255)
	inviteAccept.Text = "✓ ACCEPT"
	inviteAccept.ZIndex = 60
	corner(inviteAccept, 10)
	inviteAccept.Parent = invitePopup
	polish(inviteAccept, true)

	local inviteDecline = Instance.new("TextButton")
	inviteDecline.Size = UDim2.fromScale(0.42, 0.32)
	inviteDecline.Position = UDim2.fromScale(0.53, 0.58)
	inviteDecline.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
	inviteDecline.Font = Enum.Font.GothamBlack
	inviteDecline.TextScaled = true
	inviteDecline.TextColor3 = Color3.fromRGB(255, 255, 255)
	inviteDecline.Text = "✕ DECLINE"
	inviteDecline.ZIndex = 60
	corner(inviteDecline, 10)
	inviteDecline.Parent = invitePopup
	polish(inviteDecline, false)

	local inviteFromId = 0
	local inviteToken = 0
	local function respondInvite(accept: boolean)
		invitePopup.Visible = false
		if self.onChallengeRespond and inviteFromId ~= 0 then
			self.onChallengeRespond(inviteFromId, accept)
		end
		inviteFromId = 0
	end
	inviteAccept.Activated:Connect(function()
		respondInvite(true)
	end)
	inviteDecline.Activated:Connect(function()
		respondInvite(false)
	end)

	function self.showChallengeInvite(fromUserId: number, fromName: string)
		inviteFromId = fromUserId
		inviteText.Text = string.format("%s challenges you to a 1v1!", fromName)
		invitePopup.Visible = true
		inviteToken += 1
		local tok = inviteToken
		task.delay(18, function()
			if inviteToken == tok and invitePopup.Visible then
				invitePopup.Visible = false
				inviteFromId = 0
			end
		end)
	end

	-- ===================== WORLD CUP FIXTURES (calendar) ===============
	local fixturesPanel = Instance.new("Frame")
	fixturesPanel.Size = UDim2.fromScale(1, 1)
	fixturesPanel.BackgroundColor3 = Theme.Bg
	gradient(fixturesPanel, Color3.fromRGB(28, 36, 52), Theme.Bg)
	fixturesPanel.BackgroundTransparency = 0.05
	fixturesPanel.Visible = false
	fixturesPanel.Parent = screen

	local fixturesTitle = Instance.new("TextLabel")
	fixturesTitle.Size = UDim2.fromScale(0.7, 0.08)
	fixturesTitle.Position = UDim2.fromScale(0.06, 0.04)
	fixturesTitle.BackgroundTransparency = 1
	fixturesTitle.Font = Enum.Font.GothamBlack
	fixturesTitle.TextScaled = true
	fixturesTitle.TextXAlignment = Enum.TextXAlignment.Left
	fixturesTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	fixturesTitle.Text = "📅 WORLD CUP FIXTURES"
	fixturesTitle.Parent = fixturesPanel

	local fixturesSub = Instance.new("TextLabel")
	fixturesSub.Size = UDim2.fromScale(0.7, 0.035)
	fixturesSub.Position = UDim2.fromScale(0.06, 0.12)
	fixturesSub.BackgroundTransparency = 1
	fixturesSub.Font = Enum.Font.GothamMedium
	fixturesSub.TextScaled = true
	fixturesSub.TextXAlignment = Enum.TextXAlignment.Left
	fixturesSub.TextColor3 = Color3.fromRGB(180, 190, 205)
	fixturesSub.Text = string.format("%s → %s", WorldCup.StartDate, WorldCup.EndDate)
	fixturesSub.Parent = fixturesPanel

	local closeFixtures = Instance.new("TextButton")
	closeFixtures.Size = UDim2.fromScale(0.1, 0.07)
	closeFixtures.Position = UDim2.fromScale(0.84, 0.05)
	closeFixtures.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeFixtures.Font = Enum.Font.GothamBlack
	closeFixtures.TextScaled = true
	closeFixtures.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeFixtures.Text = "✕"
	corner(closeFixtures, 10)
	closeFixtures.Parent = fixturesPanel
	decoratePanel(fixturesPanel, fixturesTitle, closeFixtures)

	local fixturesList = Instance.new("ScrollingFrame")
	fixturesList.Size = UDim2.fromScale(0.88, 0.78)
	fixturesList.Position = UDim2.fromScale(0.06, 0.18)
	fixturesList.BackgroundTransparency = 1
	fixturesList.BorderSizePixel = 0
	fixturesList.ScrollBarThickness = 6
	fixturesList.CanvasSize = UDim2.new()
	fixturesList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	fixturesList.Parent = fixturesPanel
	local fixturesLayout = Instance.new("UIListLayout")
	fixturesLayout.Padding = UDim.new(0, 6)
	fixturesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	fixturesLayout.Parent = fixturesList

	local function renderFixtures()
		for _, child in fixturesList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local today = WorldCup.todayISO()
		local order = 0
		local lastDate = ""
		local upcoming = WorldCup.upcoming(90)
		for _, f in upcoming do
			if f.date ~= lastDate then
				lastDate = f.date
				order += 1
				local header = Instance.new("Frame")
				header.Size = UDim2.new(1, 0, 0, 28)
				header.BackgroundTransparency = 1
				header.LayoutOrder = order
				local headerLabel = Instance.new("TextLabel")
				headerLabel.Size = UDim2.fromScale(1, 1)
				headerLabel.BackgroundTransparency = 1
				headerLabel.Font = Enum.Font.GothamBold
				headerLabel.TextScaled = true
				headerLabel.TextXAlignment = Enum.TextXAlignment.Left
				headerLabel.TextColor3 = if f.date == today
					then Color3.fromRGB(60, 220, 110)
					else Color3.fromRGB(240, 200, 40)
				headerLabel.Text = if f.date == today then f.date .. "  ·  TODAY" else f.date
				headerLabel.Parent = header
				header.Parent = fixturesList
			end
			order += 1
			if WorldCup.isMilestone(f) then
				-- Knockout round marker (no teams yet): one centered banner row.
				local marker = Instance.new("TextLabel")
				marker.Size = UDim2.new(1, 0, 0, 40)
				marker.LayoutOrder = order
				marker.BackgroundColor3 = Color3.fromRGB(40, 34, 20)
				marker.Font = Enum.Font.GothamBlack
				marker.TextScaled = true
				marker.TextColor3 = Color3.fromRGB(255, 200, 90)
				marker.Text = f.stage
				corner(marker)
				marker.Parent = fixturesList
			else
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 46)
				row.LayoutOrder = order
				row.BackgroundColor3 = if f.date == today
					then Color3.fromRGB(28, 44, 34)
					else Color3.fromRGB(22, 25, 34)
				corner(row)
				row.Parent = fixturesList

				local matchup = Instance.new("TextLabel")
				matchup.Size = UDim2.fromScale(0.7, 1)
				matchup.Position = UDim2.fromScale(0.03, 0)
				matchup.BackgroundTransparency = 1
				matchup.Font = Enum.Font.GothamBold
				matchup.TextScaled = true
				matchup.TextXAlignment = Enum.TextXAlignment.Left
				matchup.TextColor3 = Color3.fromRGB(235, 235, 235)
				matchup.Text = string.format(
					"%s  vs  %s",
					WorldCup.sideLabel(f.home),
					WorldCup.sideLabel(f.away)
				)
				matchup.Parent = row

				local meta = Instance.new("TextLabel")
				meta.Size = UDim2.fromScale(0.27, 1)
				meta.Position = UDim2.fromScale(0.71, 0)
				meta.BackgroundTransparency = 1
				meta.Font = Enum.Font.Gotham
				meta.TextScaled = true
				meta.TextXAlignment = Enum.TextXAlignment.Right
				meta.TextColor3 = Color3.fromRGB(180, 190, 205)
				meta.Text = f.stage
				meta.Parent = row
			end
		end
		if #upcoming == 0 then
			local empty = Instance.new("Frame")
			empty.Size = UDim2.new(1, 0, 0, 60)
			empty.BackgroundTransparency = 1
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.Gotham
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(140, 150, 170)
			label.Text = "No upcoming fixtures."
			label.Parent = empty
			empty.Parent = fixturesList
		end
	end

	featuredBanner.Activated:Connect(function()
		lobby.Visible = false
		showPanel(fixturesPanel)
		renderFixtures()
	end)
	closeFixtures.Activated:Connect(function()
		fixturesPanel.Visible = false
		lobby.Visible = true
	end)

	-- ============================== STORE ==============================
	local latestMon: Types.MonetizationInfo = { ownsDoubler = false }

	local storePanel = Instance.new("Frame")
	storePanel.Size = UDim2.fromScale(1, 1)
	storePanel.BackgroundColor3 = Theme.Bg
	gradient(storePanel, Color3.fromRGB(28, 36, 52), Theme.Bg)
	storePanel.BackgroundTransparency = 0.05
	storePanel.Visible = false
	storePanel.Parent = screen

	local storeTitle = Instance.new("TextLabel")
	storeTitle.Size = UDim2.fromScale(0.6, 0.09)
	storeTitle.Position = UDim2.fromScale(0.06, 0.04)
	storeTitle.BackgroundTransparency = 1
	storeTitle.Font = Enum.Font.GothamBlack
	storeTitle.TextScaled = true
	storeTitle.TextXAlignment = Enum.TextXAlignment.Left
	storeTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	storeTitle.Text = "💎 STORE"
	storeTitle.Parent = storePanel

	local closeStore = Instance.new("TextButton")
	closeStore.Size = UDim2.fromScale(0.1, 0.07)
	closeStore.Position = UDim2.fromScale(0.84, 0.05)
	closeStore.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeStore.Font = Enum.Font.GothamBlack
	closeStore.TextScaled = true
	closeStore.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeStore.Text = "✕"
	corner(closeStore, 10)
	closeStore.Parent = storePanel
	decoratePanel(storePanel, storeTitle, closeStore)

	local storeScroller = Instance.new("ScrollingFrame")
	storeScroller.Size = UDim2.fromScale(0.88, 0.78)
	storeScroller.Position = UDim2.fromScale(0.06, 0.15)
	storeScroller.BackgroundTransparency = 1
	storeScroller.BorderSizePixel = 0
	storeScroller.ScrollBarThickness = 6
	storeScroller.CanvasSize = UDim2.new()
	storeScroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	storeScroller.Parent = storePanel

	local storeLayout = Instance.new("UIListLayout")
	storeLayout.Padding = UDim.new(0, 8)
	storeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	storeLayout.Parent = storeScroller

	-- A store row: an icon, a label, and a Robux-purchase button.
	local function storeRow(order: number, icon: string, labelText: string): TextButton
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.LayoutOrder = order
		row.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
		corner(row)
		row.Parent = storeScroller

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Size = UDim2.fromScale(0.16, 1)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextScaled = true
		iconLabel.Text = icon
		iconLabel.Parent = row

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.45, 1)
		label.Position = UDim2.fromScale(0.18, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(235, 235, 235)
		label.Text = labelText
		label.Parent = row

		local buy = Instance.new("TextButton")
		buy.Size = UDim2.fromScale(0.3, 0.7)
		buy.Position = UDim2.fromScale(0.67, 0.15)
		buy.BackgroundColor3 = ACCENT
		buy.Font = Enum.Font.GothamBold
		buy.TextScaled = true
		buy.TextColor3 = Color3.fromRGB(255, 255, 255)
		buy.Text = "BUY"
		corner(buy, 10)
		buy.Parent = row
		pressable(buy)
		return buy
	end

	-- Gamepass: 2x coins forever.
	local doublerBtn = storeRow(1, "🔥", "2× Coins Forever")
	doublerBtn.Activated:Connect(function()
		Sound.play("Click")
		if not latestMon.ownsDoubler and self.onBuyDoubler then
			self.onBuyDoubler()
		end
	end)

	-- Coin packs (developer products).
	for index, pack in Config.Monetization.CoinPacks do
		local buy = storeRow(index + 1, "💰", `{pack.label}  (+{pack.coins})`)
		buy.Activated:Connect(function()
			Sound.play("Click")
			if self.onBuyCoins then
				self.onBuyCoins(pack.productId)
			end
		end)
	end

	local function refreshStore()
		if latestMon.ownsDoubler then
			doublerBtn.Text = "OWNED"
			doublerBtn.BackgroundColor3 = Color3.fromRGB(70, 75, 90)
			doublerBtn.AutoButtonColor = false
		else
			doublerBtn.Text = "BUY"
			doublerBtn.BackgroundColor3 = ACCENT
			doublerBtn.AutoButtonColor = true
		end
	end

	storeButton.Activated:Connect(function()
		lobby.Visible = false
		showPanel(storePanel)
		refreshStore()
	end)
	closeStore.Activated:Connect(function()
		storePanel.Visible = false
		lobby.Visible = true
	end)

	-- Public openers so physical hub stalls (ProximityPrompts) can open the panels.
	function self.openShop()
		openShop()
	end
	function self.openRanks()
		lobby.Visible = false
		showPanel(boardPanel)
		renderBoard()
	end
	function self.openStore()
		lobby.Visible = false
		showPanel(storePanel)
		refreshStore()
	end

	-- ============================== TOAST ==============================
	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.fromScale(0.6, 0.07)
	toast.Position = UDim2.fromScale(0.2, 0.1)
	toast.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	toast.BackgroundTransparency = 0.15
	toast.Font = Enum.Font.GothamBold
	toast.TextScaled = true
	toast.TextColor3 = Color3.fromRGB(255, 255, 255)
	toast.Text = ""
	toast.Visible = false
	toast.ZIndex = 50
	corner(toast)
	toast.Parent = screen

	local toastToken = 0

	-- ============================ BEHAVIOUR =============================
	local power = 0.5
	local direction = 1
	local deadline = 0
	local submitted = false
	local role: Types.Role = "Shooter"
	local vsToken = 0

	-- Slide the two names in from the sides, clash a "VS", then clear.
	local function playVsIntro(shooterName: string, keeperName: string)
		vsShooter.Text = "⚽ " .. shooterName
		vsKeeper.Text = "🧤 " .. keeperName
		vsShooter.BackgroundTransparency, vsShooter.TextTransparency = 0.1, 0
		vsKeeper.BackgroundTransparency, vsKeeper.TextTransparency = 0.1, 0
		vsLabel.TextTransparency = 1
		vsLabelScale.Scale = 2
		vsShooter.Position = UDim2.fromScale(-0.5, 0.34)
		vsKeeper.Position = UDim2.fromScale(1.5, 0.34)
		vsCard.Visible = true

		vsToken += 1
		local tok = vsToken
		local slide = TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		TweenService:Create(vsShooter, slide, { Position = UDim2.fromScale(0.05, 0.34) }):Play()
		TweenService:Create(vsKeeper, slide, { Position = UDim2.fromScale(0.95, 0.34) }):Play()
		task.delay(0.26, function()
			if tok ~= vsToken then
				return
			end
			vsLabel.TextTransparency = 0
			TweenService:Create(
				vsLabelScale,
				TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end)
		task.delay(1.15, function()
			if tok ~= vsToken then
				return
			end
			local fade = TweenInfo.new(0.25)
			TweenService
				:Create(vsShooter, fade, { BackgroundTransparency = 1, TextTransparency = 1 })
				:Play()
			TweenService
				:Create(vsKeeper, fade, { BackgroundTransparency = 1, TextTransparency = 1 })
				:Play()
			TweenService:Create(vsLabel, fade, { TextTransparency = 1 }):Play()
			task.delay(0.26, function()
				if tok == vsToken then
					vsCard.Visible = false
				end
			end)
		end)
	end

	local function setControlsEnabled(enabled: boolean)
		action.Visible = enabled
		hint.Visible = enabled
		setAimEnabled(enabled)
		powerBg.Visible = enabled and role == "Shooter"
		curveTrack.Visible = enabled and role == "Shooter" -- only shooters bend it
		waiting.Text = if enabled then "" else "Waiting for opponent…"
	end

	local function doSubmit()
		if submitted then
			return
		end
		submitted = true
		setControlsEnabled(false)
		if self.onSubmit then
			self.onSubmit()
		end
	end

	action.Activated:Connect(function()
		Sound.play("Click")
		doSubmit()
	end)
	backButton.Activated:Connect(function()
		overPanel.Visible = false
		if self.onBackToLobby then
			self.onBackToLobby()
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		-- Power oscillation
		power += direction * POWER_SPEED * dt
		if power >= 1 then
			power, direction = 1, -1
		elseif power <= 0 then
			power, direction = 0, 1
		end
		powerFill.Size = UDim2.fromScale(power, 1)
		powerFill.BackgroundColor3 = if power <= Config.Skill.SweetSpotPower
			then Color3.fromRGB(240, 200, 40)
			else Color3.fromRGB(220, 70, 60)

		-- Countdown + client-side auto-submit at the deadline.
		if match.Visible and not submitted and deadline > 0 then
			local remaining = deadline - workspace:GetServerTimeNow()
			if remaining <= 0 then
				timer.Text = "0.0"
				doSubmit()
			else
				timer.Text = string.format("%.1f", remaining)
			end
		end
	end)

	-- ============================== API ================================
	function self.getInput()
		return { x = aimX, y = aimY, power = power, curve = curve }
	end

	function self.setProfile(data: Types.ProfileData)
		latestProfile = data
		lobbyStats.Text = string.format(
			"💰 %d   ·   W %d / L %d   ·   ⚽ %d",
			data.Coins,
			data.Wins,
			data.Losses,
			data.GoalsScored
		)
		local nation = Catalog.get(data.Equipped)
		nationChip.Text = if nation
			then string.format(
				"🌍 Playing as %s %s  ·  tap to change",
				nation.emoji,
				nation.name
			)
			else "🌍 Pick your country"
		nextMatchLabel.Text = WorldCup.nextMatchText(data.Equipped) or ""
		renderProgression(data)
		refreshShop()
	end

	function self.setLeaderboard(data: Types.LeaderboardData)
		latestBoard = data
		if boardPanel.Visible then
			renderBoard()
		end
	end

	function self.setMonetization(info: Types.MonetizationInfo)
		latestMon = info
		if storePanel.Visible then
			refreshStore()
		end
	end

	function self.notify(message: string)
		Sound.play("Purchase")
		toast.Text = message
		toast.Visible = true
		toastToken += 1
		local myToken = toastToken
		task.delay(2.2, function()
			if toastToken == myToken then
				toast.Visible = false
			end
		end)
	end

	function self.showLobby()
		match.Visible = false
		overPanel.Visible = false
		lobby.Visible = true
		deadline = 0
		setAimEnabled(false) -- no world crosshair while in the plaza
	end

	function self.setQueue(inQueue: boolean, size: number)
		if inQueue then
			findButton.Text = "CANCEL"
			findButton.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
			lobbyStatus.Text = string.format("Waiting for players…  (%d in queue)", size)
		else
			findButton.Text = "FIND MATCH"
			findButton.BackgroundColor3 = ACCENT
			lobbyStatus.Text = ""
		end
	end

	function self.startRound(info: Types.RoundStartInfo)
		role = info.role
		submitted = false
		deadline = info.deadline
		lobby.Visible = false
		overPanel.Visible = false
		match.Visible = true
		result.TextTransparency = 1

		score.Text = string.format("⚽ %s  vs  🧤 %s", info.shooterName, info.keeperName)
		roundLabel.Text = string.format("Turn %d / %d", info.turnIndex, info.totalTurns)
		setStandings(info.standings)
		playVsIntro(info.shooterName, info.keeperName)

		Sound.play("Whistle")
		resetAim()
		resetCurve()
		if role == "Shooter" then
			banner.Text = "⚽ YOUR SHOT"
			banner.TextColor3 = ACCENT
			hint.Text = "Drag to aim · slide CURVE to bend · tap SHOOT to lock power"
			action.Text = "SHOOT"
			setControlsEnabled(true)
			if not coachedShooter then
				coachedShooter = true
				showCoach(
					"Drag the dot in the goal to aim. Slide CURVE to bend the ball around the keeper. The power bar swings — tap SHOOT to lock it. Power + curve beat the keeper, but overdoing either sprays wide!"
				)
			end
		elseif role == "Keeper" then
			banner.Text = "🧤 YOU KEEP — GUESS THE DIVE"
			banner.TextColor3 = Color3.fromRGB(240, 200, 40)
			hint.Text = "Drag to where you'll dive"
			action.Text = "DIVE!"
			setControlsEnabled(true)
			if not coachedKeeper then
				coachedKeeper = true
				showCoach(
					"Read the shooter and drag to where you'll dive. Guess their corner to make the save!"
				)
			end
		else
			banner.Text = "👀 SPECTATING"
			banner.TextColor3 = Color3.fromRGB(190, 200, 215)
			deadline = 0 -- spectators don't act, so no countdown / auto-submit
			submitted = true
			setControlsEnabled(false)
			waiting.Text = string.format("%s is taking a penalty…", info.shooterName)
		end
	end

	function self.showRoundResult(info: Types.RoundResultInfo)
		submitted = true
		deadline = 0
		setControlsEnabled(false)
		waiting.Text = ""
		timer.Text = ""
		setStandings(info.standings)
		Sound.play(info.outcome) -- "Goal" / "Save" / "Miss" map to sound names

		-- The duel reads off the real pitch now: the ball flies to where it was
		-- aimed and the keeper dives to their guess (see ShotAnimator).
		coach.Visible = false

		-- Your goal scores for your country -> the World Cup Standings + Golden
		-- Boot. Flash that tie so the national-pride meta feels tangible.
		if info.outcome == "Goal" and info.youWereShooter and latestProfile then
			local nation = Catalog.get(latestProfile.Equipped)
			if nation then
				toast.Text = string.format("⚽ +1 for %s %s!", nation.emoji, nation.name)
				toast.Visible = true
				toastToken += 1
				local tok = toastToken
				task.delay(2.2, function()
					if toastToken == tok then
						toast.Visible = false
					end
				end)
			end
		end

		-- Phrase the result from this client's point of view.
		local text, color
		if info.outcome == "Goal" then
			text = if info.youWereShooter
				then "GOAL!"
				elseif info.youWereKeeper then "CONCEDED"
				else "GOAL!"
			color = if info.youWereKeeper
				then Color3.fromRGB(230, 80, 70)
				else Color3.fromRGB(60, 220, 110)
		elseif info.outcome == "Save" then
			text = if info.youWereShooter
				then "SAVED!"
				elseif info.youWereKeeper then "GREAT SAVE!"
				else "SAVED!"
			color = if info.youWereKeeper
				then Color3.fromRGB(60, 220, 110)
				else Color3.fromRGB(230, 80, 70)
		else
			text = "MISS!"
			color = Color3.fromRGB(240, 200, 40)
		end
		result.Text = text
		result.TextColor3 = color
		result.TextTransparency = 0
		-- Punch: overshoot the scale, then settle (game feel).
		resultScale.Scale = 1.6
		TweenService:Create(
			resultScale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
		task.spawn(function()
			task.wait(1.4)
			for i = 0, 1, 0.1 do
				result.TextTransparency = i
				task.wait(0.03)
			end
		end)
	end

	function self.showMatchOver(info: Types.MatchOverInfo)
		match.Visible = false
		showPanel(overPanel)
		deadline = 0
		setAimEnabled(false) -- clear the crosshair off the goal
		overTitle.Text = if info.won
			then "🏆 WINNER!"
			else string.format("#%d of %d", info.placement, info.total)
		overTitle.TextColor3 = if info.won
			then Color3.fromRGB(240, 200, 40)
			else Color3.fromRGB(200, 205, 220)

		local lines = {}
		local myGoals = 0
		for rank, entry in info.standings do
			table.insert(lines, string.format("%d. %s — %d", rank, entry.name, entry.goals))
			if entry.isYou then
				myGoals = entry.goals
			end
		end
		local detail = table.concat(lines, "\n")
		if info.reason then
			detail ..= "\n(" .. info.reason .. ")"
		end
		overScore.Text = detail

		-- Victory-card line: your flag + goals this match.
		local nation = if latestProfile then Catalog.get(latestProfile.Equipped) else nil
		local flag = if nation then nation.emoji .. " " .. nation.name else "🌍"
		overNation.Text =
			string.format("%s  ·  %d goal%s", flag, myGoals, if myGoals == 1 then "" else "s")
	end

	return self
end

return UI
