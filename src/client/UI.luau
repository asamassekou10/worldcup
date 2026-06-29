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
local TriviaPanel = require(script.Parent:WaitForChild("TriviaPanel"))
local SeasonPassPanel = require(script.Parent:WaitForChild("SeasonPassPanel"))

-- Mobile layout: the bottom corners are taken by the jump button + movement thumbstick,
-- so on touch the bottom button row insets/compresses away from them (see menuButton).
-- The top no longer needs a manual shift: the HUD ScreenGui uses CoreUISafeInsets, which
-- already keeps everything clear of the topbar/notch -- so TOP_INSET stays 0 (kept as a
-- no-op term in the top elements' positions). (Module-level so the 200-local builder pays
-- nothing for them.)
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local TOP_INSET = 0

local UI = {}

local ACCENT = Theme.Accent
local PANEL = Theme.Panel
local POWER_SPEED = 1.4 -- full sweeps of the power bar per second

-- Turn a resolved shot into a punchy, CONTEXT-AWARE verdict (a big word + a small
-- teaching line) from the geometry alone. This makes the hidden skill model legible
-- -- players learn WHY they scored/missed -- and gives every shot personality.
-- Pure + module-level (no UI deps), so it stays out of the 200-local HUD builder.
local function deriveVerdict(info: Types.RoundResultInfo): (string, string)
	local sx, sy = info.shotX, info.shotY
	local kx = info.keeperX
	local topShot = sy >= 0.72
	local corner = math.abs(sx) >= 0.6
	local central = math.abs(sx) <= 0.28
	local keeperCommitted = math.abs(kx) >= 0.35
	local wrongFooted = keeperCommitted and (kx * sx) < -0.04 -- keeper went the other way
	local readYou = keeperCommitted and (kx * sx) > 0.04 -- keeper guessed your side
	local bigCurve = math.abs(info.curve) >= 0.45

	if info.outcome == "Goal" then
		if bigCurve and corner then
			return "GOLAZO!", "Bent into the top corner"
		elseif wrongFooted then
			return "WRONG-FOOTED!", "Sent the keeper the wrong way"
		elseif topShot and corner then
			return "TOP BINS!", "Upper 90 — unsavable"
		elseif corner then
			return "TUCKED AWAY!", "Buried in the corner"
		elseif central and keeperCommitted then
			return "CHEEKY!", "Straight down the middle"
		elseif topShot then
			return "ROOFED IT!", "Lifted over the keeper"
		end
		return "GOAL!", "Clinical finish"
	elseif info.outcome == "Save" then
		if readYou then
			return "READ IT!", "Keeper guessed your side"
		elseif corner then
			return "FINGERTIPS!", "Somehow clawed out of the corner"
		elseif central then
			return "RIGHT AT 'EM", "Too close to the keeper"
		end
		return "DENIED!", "Huge save"
	else
		if sy > 1 then
			return "OVER THE BAR!", "Too much power on it"
		elseif math.abs(sx) > 1 then
			return "WIDE!", "Dragged past the post"
		elseif bigCurve then
			return "CURLED WIDE", "Over-bent it"
		end
		return "OFF TARGET!", "Inches away"
	end
end

-- The trivia panel now lives in TriviaPanel.luau; re-export its question shape so
-- existing references (UI.TriviaQuestionInfo) keep working.
export type TriviaQuestionInfo = TriviaPanel.QuestionInfo

-- The season pass now lives in SeasonPassPanel.luau; re-export its info shape.
export type SeasonPassInfo = SeasonPassPanel.Info

export type Hud = {
	onQueueButton: (() -> ())?,
	onSubmit: (() -> ())?,
	onBackToLobby: (() -> ())?,
	onBuy: ((id: string) -> ())?,
	onEquip: ((id: string) -> ())?,
	onBuyCoins: ((productId: number) -> ())?,
	onBuyDoubler: (() -> ())?,
	onBuySeasonPass: (() -> ())?,
	onJoinWalkOff: (() -> ())?,
	onChallenge: ((targetUserId: number) -> ())?,
	onChallengeRespond: ((fromUserId: number, accept: boolean) -> ())?,
	onEmote: ((emoji: string) -> ())?,
	openShop: () -> (),
	openRanks: () -> (),
	openStore: () -> (),
	openChallenge1v1: () -> (),
	onPanelToggle: ((open: boolean) -> ())?,
	showChallengeInvite: (fromUserId: number, fromName: string) -> (),
	getInput: () -> { x: number, y: number, power: number, curve: number },
	setProfile: (data: Types.ProfileData) -> (),
	setLeaderboard: (data: Types.LeaderboardData) -> (),
	setMonetization: (info: Types.MonetizationInfo) -> (),
	setSeasonPass: (info: SeasonPassInfo) -> (),
	setWalkOffQueue: (inQueue: boolean, size: number) -> (),
	notify: (message: string) -> (),
	showLobby: () -> (),
	setLobbyVisible: (visible: boolean) -> (),
	setQueue: (inQueue: boolean, size: number) -> (),
	startRound: (info: Types.RoundStartInfo) -> (),
	showRoundResult: (info: Types.RoundResultInfo) -> (),
	showMatchOver: (info: Types.MatchOverInfo) -> (),
	onTriviaAnswer: ((answer: string) -> ())?,
	showTriviaQuestion: (info: TriviaQuestionInfo) -> (),
	showTriviaResult: (
		correct: boolean,
		correctAnswer: string,
		timedOut: boolean,
		yourScore: number?,
		oppScore: number?
	) -> (),
	hideTriviaPanel: () -> (),
	setChoicesMode: (active: boolean) -> (),
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
-- Cap how large TextScaled text may grow. These full-screen panels let TextScaled balloon labels
-- and buttons to ~50px on desktop (the "giant BUY/EQUIP" look); a max size keeps them tasteful.
-- Pure clamp -- it can only shrink over-scaled text, never enlarge or reflow anything.
local function capScaled(obj: Instance, max: number)
	if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.TextScaled then
		if not obj:FindFirstChildOfClass("UITextSizeConstraint") then
			local c = Instance.new("UITextSizeConstraint")
			c.MaxTextSize = max
			c.Parent = obj
		end
	end
end

local function decoratePanel(panel: GuiObject, title: TextLabel, close: GuiButton?)
	-- Tame oversized text across the whole panel (titles a touch larger), now and as rows stream in.
	capScaled(title, 44)
	for _, d in panel:GetDescendants() do
		capScaled(d, 30)
	end
	panel.DescendantAdded:Connect(function(d)
		capScaled(d, 30)
	end)
	-- These panels ignore the GUI inset (to fill the screen), so their titles would
	-- otherwise render BEHIND the Roblox topbar (menu/chat/mic/account buttons). A
	-- top inset pushes all panel content clear of it. One source of truth for every
	-- panel that calls decoratePanel.
	if not panel:FindFirstChildOfClass("UIPadding") then
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 48)
		pad.Parent = panel
	end

	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0.14, 0.007)
	bar.Position =
		UDim2.fromScale(title.Position.X.Scale, title.Position.Y.Scale + title.Size.Y.Scale + 0.004)
	bar.BackgroundColor3 = Theme.Accent
	bar.BorderSizePixel = 0
	corner(bar, 4)
	gradient(bar, Theme.Accent, Theme.Gold, 0)
	bar.Parent = panel
	-- Standardise the close control into a neutral "‹ Back" pill (was a jarring red X), matching the
	-- feature panels. One place styles every panel that calls decoratePanel.
	if close then
		close.Text = "‹  Back"
		close.Size = UDim2.fromScale(0.15, 0.07)
		close.Position = UDim2.fromScale(0.8, 0.045)
		close.BackgroundColor3 = Color3.fromRGB(42, 47, 66)
		close.TextColor3 = Color3.fromRGB(214, 220, 234)
		close.Font = Enum.Font.GothamBold
		if not close:FindFirstChildOfClass("UIPadding") then
			local cp = Instance.new("UIPadding")
			cp.PaddingTop = UDim.new(0, 8)
			cp.PaddingBottom = UDim.new(0, 8)
			cp.PaddingLeft = UDim.new(0, 14)
			cp.PaddingRight = UDim.new(0, 14)
			cp.Parent = close
		end
		polish(close, false)
	end
end

-- A custom icon image at the left of a full-screen panel's title (replaces the emoji prefix). No-op
-- if `iconId` is blank. The matching title should start at x ~0.115 to leave room.
local function titleIcon(panel: GuiObject, iconId: string?)
	if not iconId or iconId == "" then
		return
	end
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Position = UDim2.fromScale(0.05, 0.03)
	img.Size = UDim2.fromScale(0.06, 0.1)
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = iconId
	img.Parent = panel
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
		onBuySeasonPass = nil :: (() -> ())?,
		onJoinWalkOff = nil :: (() -> ())?,
		onTriviaAnswer = nil :: ((answer: string) -> ())?,
		onChallenge = nil :: ((targetUserId: number) -> ())?,
		onChallengeRespond = nil :: ((fromUserId: number, accept: boolean) -> ())?,
		onEmote = nil :: ((emoji: string) -> ())?,
		onPanelToggle = nil :: ((open: boolean) -> ())?,
	}

	local screen = Instance.new("ScreenGui")
	screen.Name = "PenaltyKingsHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Global ZIndex behaviour (the default this UI is built around: button shadows
	-- sit at widget.ZIndex-1 to render BEHIND, overlays use explicit ZIndex). Panels
	-- that raise their own ZIndex must give their content an even higher ZIndex so
	-- the panel background doesn't paint over it (see triviaPanel below).
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screen.Parent = player:WaitForChild("PlayerGui")

	-- ===================== CELEBRATION OVERLAY =======================
	-- A dedicated full-screen layer for the big "moment": a colour band sweeps
	-- across and a huge word slams in (GOAL! / GREAT SAVE!), then sweeps out.
	-- Lives above the ShotAnimator flash (DisplayOrder 5) but below loading.
	--
	-- Wrapped in a `do` block: UI.create is a huge function near Luau's 200-local
	-- limit, so we scope the ~dozen build-time locals here and let them release at
	-- `end`. Only the two closures below survive (captured GUI refs as upvalues).
	local playCelebration: (kind: string) -> ()
	local dropConfetti: () -> ()
	do
		local celebGui = Instance.new("ScreenGui")
		celebGui.Name = "PenaltyKingsCelebrate"
		celebGui.ResetOnSpawn = false
		celebGui.IgnoreGuiInset = true
		celebGui.DisplayOrder = 8
		celebGui.Parent = player:WaitForChild("PlayerGui")

		-- The diagonal colour band the word rides on.
		local celebBand = Instance.new("Frame")
		celebBand.Name = "Band"
		celebBand.Size = UDim2.fromScale(1.4, 0.30)
		celebBand.Position = UDim2.fromScale(-1.6, 0.34)
		celebBand.AnchorPoint = Vector2.new(0, 0)
		celebBand.Rotation = -4
		celebBand.BackgroundColor3 = Theme.Accent
		celebBand.BorderSizePixel = 0
		celebBand.Visible = false
		celebBand.Parent = celebGui
		local celebGrad = Instance.new("UIGradient")
		celebGrad.Color = ColorSequence.new(Theme.AccentDark, Theme.Accent)
		celebGrad.Rotation = 8
		celebGrad.Parent = celebBand

		-- The big word.
		local celebWord = Instance.new("TextLabel")
		celebWord.Name = "Word"
		celebWord.Size = UDim2.fromScale(1, 0.62)
		celebWord.Position = UDim2.fromScale(0, 0.19)
		celebWord.BackgroundTransparency = 1
		celebWord.Font = Enum.Font.GothamBlack
		celebWord.TextScaled = true
		celebWord.TextColor3 = Color3.fromRGB(255, 255, 255)
		celebWord.Text = "GOAL!"
		celebWord.Parent = celebBand
		local celebWordStroke = Instance.new("UIStroke")
		celebWordStroke.Color = Color3.fromRGB(15, 20, 28)
		celebWordStroke.Thickness = 4
		celebWordStroke.Parent = celebWord

		-- The smaller flavour line under the word.
		local celebSub = Instance.new("TextLabel")
		celebSub.Name = "Sub"
		celebSub.Size = UDim2.fromScale(1, 0.18)
		celebSub.Position = UDim2.fromScale(0, 0.80)
		celebSub.BackgroundTransparency = 1
		celebSub.Font = Enum.Font.GothamBold
		celebSub.TextScaled = true
		celebSub.TextColor3 = Color3.fromRGB(20, 28, 36)
		celebSub.Text = ""
		celebSub.Parent = celebBand

		-- Random flavour lines keep the moment fresh on repeat goals/saves.
		local GOAL_LINES = {
			"GOLAZO!",
			"TOP BINS!",
			"WHAT A STRIKE!",
			"CLINICAL!",
			"UNSTOPPABLE!",
			"BACK OF THE NET!",
		}
		local SAVE_LINES =
			{ "DENIED!", "NO CHANCE!", "BRICK WALL!", "HUGE HANDS!", "PARRIED AWAY!" }
		local celebToken = 0

		-- kind: "goal" (green) or "save" (blue). Sweeps the band in, slams the word,
		-- holds, then sweeps out. Self-cancelling via a token so rapid turns are safe.
		function playCelebration(kind: string, word: string?, sub: string?)
			celebToken += 1
			local myToken = celebToken

			local lines = if kind == "save" then SAVE_LINES else GOAL_LINES
			celebWord.Text = word or (if kind == "save" then "GREAT SAVE!" else "GOAL!")
			celebSub.Text = sub or lines[math.random(1, #lines)]
			celebBand.BackgroundColor3 = if kind == "save"
				then Color3.fromRGB(58, 150, 230)
				else Theme.Accent
			celebGrad.Color = if kind == "save"
				then ColorSequence.new(Color3.fromRGB(36, 96, 170), Color3.fromRGB(72, 170, 245))
				else ColorSequence.new(Theme.AccentDark, Theme.Accent)

			-- Reset to the off-screen-left start state.
			celebBand.Visible = true
			celebBand.Position = UDim2.fromScale(-1.6, 0.34)
			celebWord.TextTransparency = 0
			celebWordStroke.Transparency = 0
			celebSub.TextTransparency = 0
			local wordScale = celebWord:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			wordScale.Parent = celebWord
			wordScale.Scale = 2.2

			-- 1) Band sweeps in to centre.
			TweenService:Create(
				celebBand,
				TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Position = UDim2.fromScale(-0.2, 0.34) }
			):Play()
			-- 2) Word slams down to full size.
			task.delay(0.05, function()
				if celebToken ~= myToken then
					return
				end
				TweenService:Create(
					wordScale,
					TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }
				):Play()
			end)
			-- 3) Hold, then sweep out to the right and fade.
			task.delay(1.25, function()
				if celebToken ~= myToken then
					return
				end
				local OUT = TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				TweenService:Create(celebBand, OUT, { Position = UDim2.fromScale(1.4, 0.34) })
					:Play()
				TweenService:Create(celebWord, OUT, { TextTransparency = 1 }):Play()
				TweenService:Create(celebWordStroke, OUT, { Transparency = 1 }):Play()
				TweenService:Create(celebSub, OUT, { TextTransparency = 1 }):Play()
				task.delay(0.32, function()
					if celebToken == myToken then
						celebBand.Visible = false
					end
				end)
			end)
		end

		-- A burst of falling, spinning confetti pieces (used on a match win). Pure
		-- UI Frames -> no assets. They self-destruct after falling off-screen.
		local CONFETTI_COLORS: { Color3 } = {
			Color3.fromRGB(46, 200, 112),
			Color3.fromRGB(255, 206, 72),
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(58, 150, 230),
			Color3.fromRGB(230, 80, 70),
		}
		function dropConfetti()
			for _ = 1, 60 do
				local piece = Instance.new("Frame")
				piece.Size = UDim2.fromOffset(math.random(8, 16), math.random(10, 20))
				piece.Position = UDim2.fromScale(math.random(), -0.1)
				piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
				piece.BorderSizePixel = 0
				piece.Rotation = math.random(0, 360)
				piece.ZIndex = 2
				piece.Parent = celebGui
				local fall = math.random(18, 28) / 10 -- 1.8 .. 2.8s
				local drift = (math.random() - 0.5) * 0.3
				TweenService:Create(
					piece,
					TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{
						Position = UDim2.fromScale(math.random() + drift, 1.15),
						Rotation = piece.Rotation + math.random(-360, 360),
						BackgroundTransparency = 0.4,
					}
				):Play()
				task.delay(fall + 0.1, function()
					piece:Destroy()
				end)
				task.wait(0.01) -- stagger the spawn for a natural shower
			end
		end
	end -- close the celebration `do` scope (releases build-time locals)

	-- ============================ LOBBY HUD ============================
	-- A transparent full-screen container so the festival plaza shows through.
	-- (Plain Frames don't capture input, so walking / the PLAY prompt still work.)
	local lobby = Instance.new("Frame")
	lobby.Name = "Lobby"
	lobby.Size = UDim2.fromScale(1, 1)
	lobby.BackgroundTransparency = 1
	lobby.Parent = screen

	-- One hook covers every UI.luau panel: the lobby is hidden exactly while a panel is up, so mirror
	-- that to onPanelToggle (init.client hides the floating lobby banners while a panel is open).
	lobby:GetPropertyChangedSignal("Visible"):Connect(function()
		if self.onPanelToggle then
			self.onPanelToggle(not lobby.Visible)
		end
	end)

	-- Whenever we return to the lobby, drop the full-screen panel backdrop (showPanel
	-- raises it). Centralised here so every panel-close path is covered automatically.

	-- (Persistent "PENALTY KINGS" title removed from the lobby HUD: it's branding that's
	-- already on the loading screen, and it dominated the top-centre. The stadium + nation
	-- chip carry the identity; this frees the whole top-centre of text.)

	-- Nation identity: front-and-center so repping your country is the first thing
	-- a new player does. Tapping it opens the nation picker (the shop).
	local nationChip = Instance.new("TextButton")
	nationChip.Size = UDim2.fromScale(0.34, 0.06)
	nationChip.Position = UDim2.new(0.33, 0, 0.055, TOP_INSET)
	nationChip.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
	nationChip.BackgroundTransparency = 0.1
	nationChip.Font = Enum.Font.GothamBold
	nationChip.TextScaled = true
	nationChip.TextColor3 = Color3.fromRGB(255, 255, 255)
	nationChip.Text = "Pick your country"
	corner(nationChip, 12)
	local nationChipStroke = Instance.new("UIStroke")
	nationChipStroke.Color = ACCENT
	nationChipStroke.Thickness = 2
	nationChipStroke.Parent = nationChip
	nationChip.Parent = lobby
	shadow(nationChip, 0.6)
	pressable(nationChip)

	-- ONE matchday line (the verbose "MATCHDAY — nations score 2× · tap for fixtures" promo
	-- was merged in here to cut a row). Shows your nation's next match + a 📅 tap-for-fixtures
	-- hint; the full matchday details live in the fixtures panel it opens.
	local nextMatchLabel = Instance.new("TextButton")
	nextMatchLabel.Size = UDim2.fromScale(0.46, 0.04)
	nextMatchLabel.Position = UDim2.new(0.27, 0, 0.118, TOP_INSET) -- centred just under the nation chip
	nextMatchLabel.BackgroundTransparency = 1
	nextMatchLabel.Font = Enum.Font.GothamBold
	nextMatchLabel.TextScaled = true
	nextMatchLabel.TextXAlignment = Enum.TextXAlignment.Center
	nextMatchLabel.TextColor3 = Color3.fromRGB(120, 230, 150)
	nextMatchLabel.TextStrokeTransparency = 0.5
	nextMatchLabel.Text = ""
	nextMatchLabel.Parent = lobby

	-- A subtle backing card groups the top-left stat cluster (coins / record / level
	-- / XP / season pass) so it reads cleanly over the busy stadium instead of as
	-- loose floating text. ZIndex 0 keeps it behind the stats (Global behaviour).
	local statPanel = Instance.new("Frame")
	statPanel.Size = UDim2.fromScale(0.28, 0.17)
	statPanel.Position = UDim2.new(0.012, 0, 0.075, TOP_INSET)
	statPanel.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
	statPanel.BackgroundTransparency = 0.42
	statPanel.BorderSizePixel = 0
	statPanel.ZIndex = 0
	corner(statPanel, 10)
	statPanel.Parent = lobby

	-- Coins + win/loss record (filled by ProfileUpdate), top-left HUD.
	local coinStatIcon = Instance.new("ImageLabel")
	coinStatIcon.Size = UDim2.fromScale(0.036, 0.05)
	coinStatIcon.Position = UDim2.new(0.02, 0, 0.085, TOP_INSET)
	coinStatIcon.BackgroundTransparency = 1
	coinStatIcon.ScaleType = Enum.ScaleType.Fit
	coinStatIcon.Image = Config.Icons.Coin
	coinStatIcon.Parent = lobby
	local lobbyStats = Instance.new("TextLabel")
	lobbyStats.Size = UDim2.fromScale(0.24, 0.045)
	lobbyStats.Position = UDim2.new(0.062, 0, 0.088, TOP_INSET) -- after the coin icon; clears mobile topbar
	lobbyStats.BackgroundTransparency = 1
	lobbyStats.Font = Enum.Font.GothamBold
	lobbyStats.TextScaled = true
	lobbyStats.TextXAlignment = Enum.TextXAlignment.Left
	lobbyStats.TextColor3 = Color3.fromRGB(240, 200, 40)
	lobbyStats.TextStrokeTransparency = 0.5
	lobbyStats.Text = "…"
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
		-- On touch, compress the 4-button row into the middle 0.06..0.81 so the rightmost
		-- (1V1) clears the jump button and the leftmost clears the movement thumbstick.
		local x = if IS_TOUCH then 0.06 + (xScale - 0.03) * (0.193 / 0.235) else xScale
		local w = if IS_TOUCH then 0.175 else 0.22
		btn.Size = UDim2.fromScale(w, 0.08)
		btn.Position = UDim2.fromScale(x, 0.86)
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
	-- These four now live inside the unified MENU (init.client) instead of a permanent bottom bar;
	-- they stay created+wired (the MENU calls their exposed open methods) but are hidden here.
	shopButton.Visible = false
	boardButton.Visible = false
	storeButton.Visible = false
	challengeButton.Visible = false

	findButton.Activated:Connect(function()
		Sound.play("Click")
		if self.onQueueButton then
			self.onQueueButton()
		end
	end)

	-- Level + XP bar (progression), top-left under the coins/record line.
	local levelStatIcon = Instance.new("ImageLabel")
	levelStatIcon.Size = UDim2.fromScale(0.036, 0.045)
	levelStatIcon.Position = UDim2.new(0.02, 0, 0.143, TOP_INSET)
	levelStatIcon.BackgroundTransparency = 1
	levelStatIcon.ScaleType = Enum.ScaleType.Fit
	levelStatIcon.Image = Config.Icons.Level
	levelStatIcon.Parent = lobby
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.fromScale(0.2, 0.04)
	levelLabel.Position = UDim2.new(0.062, 0, 0.145, TOP_INSET)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = Enum.Font.GothamBlack
	levelLabel.TextScaled = true
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.TextColor3 = Color3.fromRGB(120, 210, 255)
	levelLabel.TextStrokeTransparency = 0.5
	levelLabel.Text = "LV 1"
	levelLabel.Parent = lobby

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Size = UDim2.fromScale(0.22, 0.016)
	xpBarBg.Position = UDim2.new(0.02, 0, 0.19, TOP_INSET)
	xpBarBg.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
	corner(xpBarBg, 6)
	xpBarBg.Parent = lobby
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(120, 210, 255)
	corner(xpFill, 6)
	xpFill.Parent = xpBarBg

	-- (Season Pass mini-badge + full panel are built by SeasonPassPanel.luau, wired
	-- in just after the Store row below.)

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
		barBg.BackgroundColor3 = Color3.fromRGB(46, 52, 70) -- visible track (was near-black)
		corner(barBg, 8)
		barBg.Parent = questsCard
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = ACCENT
		corner(fill, 8)
		gradient(fill, Theme.Gold, ACCENT, 0)
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
			then "LV " .. Progression.levelFromXp(data.XP) .. "   🔥 2× XP"
			else "LV " .. Progression.levelFromXp(data.XP)
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
	local powerMisses, readStreak = 0, 0 -- adaptive-coach streak counters (shooter)
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
	shopTitle.Size = UDim2.fromScale(0.46, 0.09)
	shopTitle.Position = UDim2.fromScale(0.115, 0.04)
	shopTitle.BackgroundTransparency = 1
	shopTitle.Font = Enum.Font.GothamBlack
	shopTitle.TextScaled = true
	shopTitle.TextXAlignment = Enum.TextXAlignment.Left
	shopTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopTitle.Text = "CHOOSE YOUR COUNTRY"
	shopTitle.Parent = shopPanel
	titleIcon(shopPanel, Config.Icons.Shop)

	local shopCoinIcon = Instance.new("ImageLabel")
	shopCoinIcon.Size = UDim2.fromScale(0.035, 0.07)
	shopCoinIcon.Position = UDim2.fromScale(0.62, 0.05)
	shopCoinIcon.BackgroundTransparency = 1
	shopCoinIcon.ScaleType = Enum.ScaleType.Fit
	shopCoinIcon.Image = Config.Icons.Coin
	shopCoinIcon.Parent = shopPanel
	local shopCoins = Instance.new("TextLabel")
	shopCoins.Size = UDim2.fromScale(0.11, 0.07)
	shopCoins.Position = UDim2.fromScale(0.662, 0.05)
	shopCoins.BackgroundTransparency = 1
	shopCoins.Font = Enum.Font.GothamBold
	shopCoins.TextScaled = true
	shopCoins.TextXAlignment = Enum.TextXAlignment.Left
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
	closeShop.Text = "X"
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
			shopCoins.Text = tostring(latestProfile.Coins)
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
	self.openShop = openShop -- exposed so the unified MENU (init.client) can open it
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
	boardTitle.Size = UDim2.fromScale(0.62, 0.09)
	boardTitle.Position = UDim2.fromScale(0.115, 0.04)
	boardTitle.BackgroundTransparency = 1
	boardTitle.Font = Enum.Font.GothamBlack
	boardTitle.TextScaled = true
	boardTitle.TextXAlignment = Enum.TextXAlignment.Left
	boardTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	boardTitle.Text = "WORLD CUP STANDINGS"
	boardTitle.Parent = boardPanel
	titleIcon(boardPanel, Config.Icons.Ranks)

	local closeBoard = Instance.new("TextButton")
	closeBoard.Size = UDim2.fromScale(0.1, 0.07)
	closeBoard.Position = UDim2.fromScale(0.84, 0.05)
	closeBoard.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeBoard.Font = Enum.Font.GothamBlack
	closeBoard.TextScaled = true
	closeBoard.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBoard.Text = "X"
	corner(closeBoard, 10)
	closeBoard.Parent = boardPanel
	decoratePanel(boardPanel, boardTitle, closeBoard)

	-- Tabbed standings: 4 tabs + ONE full-width list (was 4 cramped side-by-side columns). Each entry
	-- now gets the whole panel width. Wrapped in a do-block (UI.create is near the 200-local cap).
	local renderBoard: () -> ()
	do
		local TABS = {
			{
				label = "🌍 World Cup",
				get = function()
					return latestBoard.Nations
				end,
			},
			{
				label = "👟 Golden Boot",
				get = function()
					return latestBoard.Scorers
				end,
			},
			{
				label = "🏆 Most Wins",
				get = function()
					return latestBoard.Wins
				end,
			},
			{
				label = "💰 Most Coins",
				get = function()
					return latestBoard.Coins
				end,
			},
		}
		local activeTab = 1
		local BOARD_ACCENT = Color3.fromRGB(240, 200, 40)

		-- the single wide list
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.fromScale(0.9, 0.6)
		list.Position = UDim2.fromScale(0.05, 0.3)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = Color3.fromRGB(90, 98, 124)
		list.CanvasSize = UDim2.new()
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.Parent = boardPanel
		local boardListLayout = Instance.new("UIListLayout")
		boardListLayout.Padding = UDim.new(0, 8)
		boardListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		boardListLayout.Parent = list

		local function fillList(entries: { Types.LeaderEntry })
			for _, child in list:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			if #entries == 0 then
				local holder = Instance.new("Frame")
				holder.Size = UDim2.new(1, 0, 0, 60)
				holder.BackgroundTransparency = 1
				holder.Parent = list
				local empty = Instance.new("TextLabel")
				empty.Size = UDim2.fromScale(1, 1)
				empty.BackgroundTransparency = 1
				empty.Font = Enum.Font.GothamMedium
				empty.TextScaled = true
				empty.TextColor3 = Color3.fromRGB(140, 150, 170)
				empty.Text = "No entries yet — be the first, play a match!"
				empty.Parent = holder
				return
			end
			for rank, entry in entries do
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 52)
				row.LayoutOrder = rank
				row.BackgroundColor3 = if rank <= 3
					then Color3.fromRGB(38, 43, 60)
					else Color3.fromRGB(26, 30, 42)
				corner(row, 12)
				row.Parent = list
				local medals = { "🥇", "🥈", "🥉" }
				local rankLabel = Instance.new("TextLabel")
				rankLabel.Size = UDim2.fromOffset(64, 52)
				rankLabel.Position = UDim2.fromOffset(8, 0)
				rankLabel.BackgroundTransparency = 1
				rankLabel.Font = Enum.Font.GothamBlack
				rankLabel.TextScaled = true
				rankLabel.TextColor3 = if rank == 1
					then BOARD_ACCENT
					else Color3.fromRGB(200, 205, 220)
				rankLabel.Text = medals[rank] or ("#" .. rank)
				rankLabel.Parent = row
				local nameLabel = Instance.new("TextLabel")
				nameLabel.Position = UDim2.fromOffset(80, 0)
				nameLabel.Size = UDim2.new(1, -260, 1, 0)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextScaled = true
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextColor3 = Color3.fromRGB(238, 240, 248)
				nameLabel.Text = entry.name
				nameLabel.Parent = row
				local valueLabel = Instance.new("TextLabel")
				valueLabel.AnchorPoint = Vector2.new(1, 0)
				valueLabel.Position = UDim2.new(1, -18, 0, 0)
				valueLabel.Size = UDim2.fromOffset(150, 52)
				valueLabel.BackgroundTransparency = 1
				valueLabel.Font = Enum.Font.GothamBlack
				valueLabel.TextScaled = true
				valueLabel.TextXAlignment = Enum.TextXAlignment.Right
				valueLabel.TextColor3 = BOARD_ACCENT
				valueLabel.Text = tostring(entry.value)
				valueLabel.Parent = row
			end
		end

		renderBoard = function()
			fillList(TABS[activeTab].get())
		end

		-- the tab row
		local tabBtns: { TextButton } = {}
		local function styleTabs()
			for i, b in tabBtns do
				local on = i == activeTab
				b.BackgroundColor3 = if on then BOARD_ACCENT else Color3.fromRGB(34, 40, 56)
				b.TextColor3 = if on
					then Color3.fromRGB(22, 24, 32)
					else Color3.fromRGB(196, 204, 222)
			end
		end
		for i, tab in TABS do
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromScale(0.235, 0.075)
			b.Position = UDim2.fromScale(0.05 + (i - 1) * 0.227, 0.18)
			b.Font = Enum.Font.GothamBold
			b.TextScaled = true
			b.AutoButtonColor = false
			b.Text = tab.label
			corner(b, 10)
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 6)
			pad.PaddingRight = UDim.new(0, 6)
			pad.PaddingTop = UDim.new(0, 6)
			pad.PaddingBottom = UDim.new(0, 6)
			pad.Parent = b
			b.Parent = boardPanel
			tabBtns[i] = b
			b.Activated:Connect(function()
				Sound.play("Click")
				activeTab = i
				styleTabs()
				renderBoard()
			end)
		end
		styleTabs()
	end

	self.openRanks = function() -- exposed for the unified MENU
		lobby.Visible = false
		showPanel(boardPanel)
		renderBoard()
	end
	boardButton.Activated:Connect(self.openRanks)
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
	challengeTitle.Position = UDim2.fromScale(0.115, 0.04)
	challengeTitle.BackgroundTransparency = 1
	challengeTitle.Font = Enum.Font.GothamBlack
	challengeTitle.TextScaled = true
	challengeTitle.TextXAlignment = Enum.TextXAlignment.Left
	challengeTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	challengeTitle.Text = "CHALLENGE A PLAYER"
	challengeTitle.Parent = challengePanel
	titleIcon(challengePanel, Config.Icons.OneVOne)

	local closeChallenge = Instance.new("TextButton")
	closeChallenge.Size = UDim2.fromScale(0.1, 0.07)
	closeChallenge.Position = UDim2.fromScale(0.84, 0.05)
	closeChallenge.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeChallenge.Font = Enum.Font.GothamBlack
	closeChallenge.TextScaled = true
	closeChallenge.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeChallenge.Text = "X"
	corner(closeChallenge, 10)
	closeChallenge.Parent = challengePanel
	decoratePanel(challengePanel, challengeTitle, closeChallenge)

	-- Walk-Off quick-queue card (at the top of the 1V1 panel).
	local walkoffCard = Instance.new("Frame")
	walkoffCard.Size = UDim2.fromScale(0.88, 0.16)
	walkoffCard.Position = UDim2.fromScale(0.06, 0.16)
	walkoffCard.BackgroundColor3 = Color3.fromRGB(28, 36, 52)
	walkoffCard.BackgroundTransparency = 0.2
	corner(walkoffCard, 12)
	local walkoffStroke = Instance.new("UIStroke")
	walkoffStroke.Color = Color3.fromRGB(80, 140, 255)
	walkoffStroke.Thickness = 2
	walkoffStroke.Transparency = 0.4
	walkoffStroke.Parent = walkoffCard
	walkoffCard.Parent = challengePanel

	local walkoffLabel = Instance.new("TextLabel")
	walkoffLabel.Size = UDim2.fromScale(0.55, 0.55)
	walkoffLabel.Position = UDim2.fromScale(0.03, 0.1)
	walkoffLabel.BackgroundTransparency = 1
	walkoffLabel.Font = Enum.Font.GothamBlack
	walkoffLabel.TextScaled = true
	walkoffLabel.TextXAlignment = Enum.TextXAlignment.Left
	walkoffLabel.TextColor3 = Color3.fromRGB(120, 180, 255)
	walkoffLabel.Text = "WALK-OFF 1v1"
	walkoffLabel.Parent = walkoffCard

	local walkoffDesc = Instance.new("TextLabel")
	walkoffDesc.Size = UDim2.fromScale(0.55, 0.35)
	walkoffDesc.Position = UDim2.fromScale(0.03, 0.62)
	walkoffDesc.BackgroundTransparency = 1
	walkoffDesc.Font = Enum.Font.Gotham
	walkoffDesc.TextScaled = true
	walkoffDesc.TextXAlignment = Enum.TextXAlignment.Left
	walkoffDesc.TextColor3 = Color3.fromRGB(160, 175, 200)
	walkoffDesc.Text = "Instant 1v1 — pairs on join"
	walkoffDesc.Parent = walkoffCard

	local walkoffBtn = Instance.new("TextButton")
	walkoffBtn.Size = UDim2.fromScale(0.32, 0.6)
	walkoffBtn.Position = UDim2.fromScale(0.65, 0.2)
	walkoffBtn.BackgroundColor3 = Color3.fromRGB(45, 110, 220)
	walkoffBtn.Font = Enum.Font.GothamBlack
	walkoffBtn.TextScaled = true
	walkoffBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	walkoffBtn.Text = "JOIN"
	corner(walkoffBtn, 10)
	walkoffBtn.Parent = walkoffCard
	polish(walkoffBtn, true)

	walkoffBtn.Activated:Connect(function()
		Sound.play("Click")
		if self.onJoinWalkOff then
			self.onJoinWalkOff()
		end
	end)

	local walkoffStatus = Instance.new("TextLabel")
	walkoffStatus.Size = UDim2.fromScale(1, 0.22)
	walkoffStatus.Position = UDim2.fromScale(0, 0.78)
	walkoffStatus.BackgroundTransparency = 1
	walkoffStatus.Font = Enum.Font.GothamMedium
	walkoffStatus.TextScaled = true
	walkoffStatus.TextColor3 = Color3.fromRGB(140, 155, 185)
	walkoffStatus.Text = ""
	walkoffStatus.Parent = walkoffCard

	-- Divider between walk-off card and player list.
	local divLabel = Instance.new("TextLabel")
	divLabel.Size = UDim2.fromScale(0.88, 0.04)
	divLabel.Position = UDim2.fromScale(0.06, 0.34)
	divLabel.BackgroundTransparency = 1
	divLabel.Font = Enum.Font.GothamBold
	divLabel.TextScaled = true
	divLabel.TextColor3 = Color3.fromRGB(240, 200, 40)
	divLabel.Text = "— OR CHALLENGE A PLAYER —"
	divLabel.Parent = challengePanel

	local challengeList = Instance.new("ScrollingFrame")
	challengeList.Size = UDim2.fromScale(0.88, 0.56)
	challengeList.Position = UDim2.fromScale(0.06, 0.39)
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

	self.openChallenge1v1 = function() -- exposed for the unified MENU
		lobby.Visible = false
		showPanel(challengePanel)
		refreshChallengeList()
	end
	challengeButton.Activated:Connect(self.openChallenge1v1)
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
	inviteDecline.Text = "X DECLINE"
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
	closeFixtures.Text = "X"
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

	nextMatchLabel.Activated:Connect(function()
		lobby.Visible = false
		showPanel(fixturesPanel)
		renderFixtures()
	end)
	closeFixtures.Activated:Connect(function()
		fixturesPanel.Visible = false
		lobby.Visible = true
	end)

	-- (Season Pass panel built by SeasonPassPanel.luau; wired in after the Store row.)

	-- ========================== TRIVIA KIOSK ==========================
	-- Extracted to TriviaPanel.luau to keep UI.create under Luau's 200-local limit.
	local triviaCtl = TriviaPanel.build(screen, {
		corner = corner,
		pressable = pressable,
		setLobbyVisible = function(v: boolean)
			lobby.Visible = v
		end,
	})
	-- Route answer taps through the host's network callback (set by init.client).
	triviaCtl.onAnswer = function(answer: string)
		if self.onTriviaAnswer then
			self.onTriviaAnswer(answer)
		end
	end
	self.showTriviaQuestion = triviaCtl.showQuestion
	self.showTriviaResult = triviaCtl.showResult
	self.hideTriviaPanel = triviaCtl.hide

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
	storeTitle.Position = UDim2.fromScale(0.115, 0.04)
	storeTitle.BackgroundTransparency = 1
	storeTitle.Font = Enum.Font.GothamBlack
	storeTitle.TextScaled = true
	storeTitle.TextXAlignment = Enum.TextXAlignment.Left
	storeTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	storeTitle.Text = "STORE"
	storeTitle.Parent = storePanel
	titleIcon(storePanel, Config.Icons.Store)

	local closeStore = Instance.new("TextButton")
	closeStore.Size = UDim2.fromScale(0.1, 0.07)
	closeStore.Position = UDim2.fromScale(0.84, 0.05)
	closeStore.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeStore.Font = Enum.Font.GothamBlack
	closeStore.TextScaled = true
	closeStore.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeStore.Text = "X"
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

		-- Icon: an image asset when an id is passed (rbxassetid://…), else emoji text.
		-- We render via rbxthumb:// (the asset's thumbnail) so it shows whether the id
		-- is an Image OR a Decal -- a raw Decal id often won't render via .Image directly.
		if string.sub(icon, 1, 4) == "rbxa" then
			local assetId = string.match(icon, "%d+") or "0"
			local iconImg = Instance.new("ImageLabel")
			iconImg.Size = UDim2.fromScale(0.13, 0.7)
			iconImg.Position = UDim2.fromScale(0.015, 0.15)
			iconImg.BackgroundTransparency = 1
			iconImg.ScaleType = Enum.ScaleType.Fit
			iconImg.Image = "rbxthumb://type=Asset&id=" .. assetId .. "&w=150&h=150"
			iconImg.Parent = row
		else
			local iconLabel = Instance.new("TextLabel")
			iconLabel.Size = UDim2.fromScale(0.16, 1)
			iconLabel.BackgroundTransparency = 1
			iconLabel.Font = Enum.Font.GothamBold
			iconLabel.TextScaled = true
			iconLabel.Text = icon
			iconLabel.Parent = row
		end

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

	-- Gamepass: Season Pass "Road to the Final".
	local seasonPassBtn =
		storeRow(1, "rbxassetid://123868339254737", "Season Pass — Road to the Final")
	seasonPassBtn.Activated:Connect(function()
		Sound.play("Click")
		if self.onBuySeasonPass then
			self.onBuySeasonPass()
		end
	end)

	-- Build the Season Pass (badge + 40-tier panel) now that the Store row exists, so
	-- its setSeasonPass can also mark that row owned. Lives in SeasonPassPanel.luau.
	local seasonPassCtl = SeasonPassPanel.build(screen, lobby, {
		corner = corner,
		gradient = gradient,
		polish = polish,
		decoratePanel = decoratePanel,
		showPanel = showPanel,
		setLobbyVisible = function(v: boolean)
			lobby.Visible = v
		end,
		onBuy = function()
			if self.onBuySeasonPass then
				self.onBuySeasonPass()
			end
		end,
		onPremiumOwned = function()
			seasonPassBtn.Text = "OWNED"
			seasonPassBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 60)
			seasonPassBtn.AutoButtonColor = false
		end,
	})
	self.setSeasonPass = seasonPassCtl.setSeasonPass

	-- Gamepass: 2x coins forever.
	local doublerBtn = storeRow(2, "rbxassetid://76742672116397", "2× Coins Forever")
	doublerBtn.Activated:Connect(function()
		Sound.play("Click")
		if not latestMon.ownsDoubler and self.onBuyDoubler then
			self.onBuyDoubler()
		end
	end)

	-- Coin packs (developer products).
	for index, pack in Config.Monetization.CoinPacks do
		local buy = storeRow(index + 2, Config.Icons.Coin, `{pack.label}  (+{pack.coins})`)
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

	self.openStore = function() -- exposed for the unified MENU
		lobby.Visible = false
		showPanel(storePanel)
		refreshStore()
	end
	storeButton.Activated:Connect(self.openStore)
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
			"%d   ·   W %d / L %d   ·   ⚽ %d",
			data.Coins,
			data.Wins,
			data.Losses,
			data.GoalsScored
		)
		local nation = Catalog.get(data.Equipped)
		nationChip.Text = if nation
			then string.format("%s  %s", nation.emoji, nation.name)
			else "Pick your country"
		local nextMatch = WorldCup.nextMatchText(data.Equipped)
		nextMatchLabel.Text = if nextMatch
			then nextMatch .. "   ·   📅 fixtures"
			else "📅 World Cup fixtures"
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

	-- Temporarily hide/show the whole lobby HUD (used by the Free Kicks warmup so its
	-- own header + SHOOT button don't stack on top of the lobby title + FIND MATCH).
	function self.setLobbyVisible(visible: boolean)
		lobby.Visible = visible
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

		-- A context-aware verdict (big word + teaching line) derived from the geometry,
		-- so the hidden skill model is legible and every shot gets personality.
		local vword, vsub = deriveVerdict(info)
		waiting.Text = vsub -- the descriptive line shows on every POV (incl. conceded/saved/miss)

		-- Big cinematic overlay on the dramatic positive beats: a goal (you scored
		-- or you're watching one land) or a keeper's save you made. The negative POV
		-- (you conceded / your shot was saved / a miss) keeps just the HUD label.
		if info.outcome == "Goal" and not info.youWereKeeper then
			playCelebration("goal", vword, vsub)
		elseif info.outcome == "Save" and info.youWereKeeper then
			playCelebration("save", vword, vsub)
		end

		-- Adaptive coaching: spot a REPEATED mistake from the geometry and give the
		-- shooter a targeted fix (same skill model the verdicts read). Fires only on the
		-- shooter's negative beats, so it never collides with a celebration.
		if info.youWereShooter then
			local sprayed = info.outcome == "Miss" and (info.shotY > 1 or math.abs(info.shotX) > 1)
			powerMisses = if sprayed then powerMisses + 1 else 0
			local read = info.outcome == "Save"
				and math.abs(info.keeperX) >= 0.35
				and (info.keeperX * info.shotX) > 0.04
			readStreak = if read then readStreak + 1 else 0
			if powerMisses >= 2 then
				powerMisses = 0
				Sound.play("MissTooMuch") -- cheeky callout for repeated over-power sprays
				showCoach(
					"Tip: ease off the power — too much sprays it wide. Find the sweet spot."
				)
			elseif readStreak >= 2 then
				readStreak = 0
				showCoach("Tip: mix up your corners — the keeper is reading your side.")
			end
		end

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

		-- Dramatic, result-dependent headline (podium medals make 2nd/3rd feel earned
		-- instead of "you lost").
		local headline, headColor
		if info.won then
			headline, headColor = "🏆 WINNER!", Color3.fromRGB(255, 210, 60)
		elseif info.placement == 2 then
			headline, headColor = "🥈 2ND PLACE", Color3.fromRGB(214, 222, 236)
		elseif info.placement == 3 then
			headline, headColor = "🥉 3RD PLACE", Color3.fromRGB(206, 150, 96)
		else
			headline = string.format("#%d of %d", info.placement, info.total)
			headColor = Color3.fromRGB(200, 205, 220)
		end
		overTitle.Text = headline
		overTitle.TextColor3 = headColor
		-- Punch the headline in (reuse one UIScale; no new build-time locals).
		local tScale = overTitle:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		tScale.Parent = overTitle
		tScale.Scale = 1.8
		TweenService:Create(
			tScale,
			TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()

		-- Champagne moment: a confetti shower rains down behind the victory card.
		if info.won then
			task.spawn(dropConfetti)
		end

		-- Final standings, with YOUR row highlighted gold (RichText) so the screenshot
		-- reads at a glance.
		overScore.RichText = true
		local lines = {}
		local myGoals = 0
		for rank, entry in info.standings do
			local line = string.format("%d. %s — %d", rank, entry.name, entry.goals)
			if entry.isYou then
				myGoals = entry.goals
				line = string.format('<b><font color="rgb(255,210,60)">%s</font></b>', line)
			end
			table.insert(lines, line)
		end
		local detail = table.concat(lines, "\n")
		if info.reason then
			detail ..= "\n(" .. info.reason .. ")"
		end
		overScore.Text = detail

		-- Victory-card line: your flag + a quick count-up of your goals.
		local nation = if latestProfile then Catalog.get(latestProfile.Equipped) else nil
		local flag = if nation then nation.emoji .. " " .. nation.name else "🌍"
		task.spawn(function()
			for g = 0, myGoals do
				if not overPanel.Visible then
					return -- left the screen; stop counting
				end
				overNation.Text =
					string.format("%s  ·  %d goal%s", flag, g, if g == 1 then "" else "s")
				task.wait(0.1)
			end
		end)
	end

	-- (Trivia panel + its showTriviaQuestion/showTriviaResult/hideTriviaPanel are now
	-- provided by TriviaPanel.luau and wired onto `self` up where the panel is built.)

	-- Updates the Walk-Off queue button and status label in the challenge panel.
	function self.setWalkOffQueue(inQueue: boolean, size: number)
		if inQueue then
			walkoffBtn.Text = "CANCEL"
			walkoffBtn.BackgroundColor3 = Color3.fromRGB(140, 60, 60)
			walkoffStatus.Text = string.format("In queue · %d waiting", size)
		else
			walkoffBtn.Text = "JOIN"
			walkoffBtn.BackgroundColor3 = Color3.fromRGB(45, 110, 220)
			walkoffStatus.Text = if size > 0 then string.format("%d in queue", size) else ""
		end
	end

	-- (self.setSeasonPass is wired from SeasonPassPanel.build above.)

	-- Choices runner: hide the whole penalty-game HUD (coins/level/queue banners) while a
	-- player is in the Choices course, so their screen is clean. Restored on exit.
	self.setChoicesMode = function(active: boolean)
		screen.Enabled = not active
	end

	return self
end

return UI
