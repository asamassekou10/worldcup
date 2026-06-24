--!strict
-- Juggle: client-side juggling minigame UI + ball animation.
-- Shown while a JuggleSession is active on the server. The ball oscillates
-- vertically in a track at `freq` Hz; the sweet spot (middle band) glows green.
-- The TAP button pulses green when the ball is in range and red otherwise.
-- `show()` / `update()` / `hide()` are called from init.client event handlers.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Juggle = {}

local player = Players.LocalPlayer

-- Module state
local gui: ScreenGui?
local ballFrame: Frame?
local tapButton: TextButton?
local countLbl: TextLabel?
local timerLbl: TextLabel?
local beatConn: RBXScriptConnection?

local sessionStart   = 0.0
local sessionLen     = 30.0
local currentFreq    = 0.8
Juggle.active = false

-- Fraction of the track height travelled by the ball (keeps ball away from edges).
local TRAVEL_TOP    = 0.06
local TRAVEL_BOTTOM = 0.94

-- Sweet zone: ball sin value 0.35–0.65 triggers green tint on the TAP button.
local ZONE_LO = 0.35
local ZONE_HI = 0.65

local COL_GREEN  = Color3.fromRGB(38, 180, 60)
local COL_RED    = Color3.fromRGB(190, 40, 40)
local COL_BG     = Color3.fromRGB(10, 16, 30)
local COL_PANEL  = Color3.fromRGB(16, 24, 46)

local function fmt(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

local function buildGui(onTap: () -> ())
	local g = Instance.new("ScreenGui")
	g.Name            = "JuggleGui"
	g.IgnoreGuiInset  = true
	g.DisplayOrder    = 50
	g.ResetOnSpawn    = false
	g.Parent          = player:WaitForChild("PlayerGui")

	-- Dim overlay
	local dim = Instance.new("Frame")
	dim.Size                = UDim2.fromScale(1, 1)
	dim.BackgroundColor3    = COL_BG
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel     = 0
	dim.Parent              = g

	-- Centre panel
	local panel = Instance.new("Frame")
	panel.Size              = UDim2.fromOffset(640, 520)
	panel.Position          = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint       = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3  = COL_PANEL
	panel.BorderSizePixel   = 0
	panel.Parent            = g
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent      = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Size                  = UDim2.new(1, 0, 0, 48)
	title.Position              = UDim2.fromOffset(0, 16)
	title.BackgroundTransparency = 1
	title.Font                  = Enum.Font.GothamBold
	title.TextScaled            = true
	title.TextColor3            = Color3.fromRGB(255, 255, 255)
	title.Text                  = "⚽  JUGGLING CHALLENGE"
	title.Parent                = panel

	local sub = Instance.new("TextLabel")
	sub.Size                    = UDim2.new(1, 0, 0, 26)
	sub.Position                = UDim2.fromOffset(0, 68)
	sub.BackgroundTransparency  = 1
	sub.Font                    = Enum.Font.Gotham
	sub.TextScaled              = true
	sub.TextColor3              = Color3.fromRGB(160, 180, 200)
	sub.Text                    = "Tap when the ball hits the green zone!"
	sub.Parent                  = panel

	-- ── Ball track (left column) ──────────────────────────────────────────
	local track = Instance.new("Frame")
	track.Size              = UDim2.fromOffset(160, 280)
	track.Position          = UDim2.fromOffset(80, 110)
	track.BackgroundColor3  = Color3.fromRGB(8, 12, 24)
	track.BorderSizePixel   = 0
	track.ClipsDescendants  = true
	track.Parent            = panel
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 10)
	trackCorner.Parent      = track

	-- Sweet-spot band (centre third of the track)
	local sweetSpot = Instance.new("Frame")
	sweetSpot.Size              = UDim2.fromScale(1, 0.20)
	sweetSpot.Position          = UDim2.fromScale(0, 0.40)
	sweetSpot.BackgroundColor3  = COL_GREEN
	sweetSpot.BackgroundTransparency = 0.55
	sweetSpot.BorderSizePixel   = 0
	sweetSpot.ZIndex            = 2
	sweetSpot.Parent            = track

	local ssLine = Instance.new("Frame")
	ssLine.Size                 = UDim2.fromScale(1, 0)
	ssLine.Position             = UDim2.fromScale(0, 0.5)
	ssLine.BackgroundColor3     = COL_GREEN
	ssLine.BackgroundTransparency = 0.2
	ssLine.BorderSizePixel      = 0
	ssLine.ZIndex               = 3
	ssLine.Size                 = UDim2.new(1, 0, 0, 2)
	ssLine.Parent               = sweetSpot

	local ssLabel = Instance.new("TextLabel")
	ssLabel.Size                = UDim2.fromScale(1, 1)
	ssLabel.BackgroundTransparency = 1
	ssLabel.Font                = Enum.Font.GothamBold
	ssLabel.TextScaled          = true
	ssLabel.TextColor3          = COL_GREEN
	ssLabel.Text                = "TAP HERE"
	ssLabel.ZIndex              = 3
	ssLabel.Parent              = sweetSpot

	-- The ball (circle)
	local ball = Instance.new("Frame")
	ball.Size               = UDim2.fromOffset(44, 44)
	ball.AnchorPoint        = Vector2.new(0.5, 0.5)
	ball.Position           = UDim2.fromScale(0.5, 0.5)
	ball.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
	ball.BorderSizePixel    = 0
	ball.ZIndex             = 4
	ball.Parent             = track
	local ballCorner = Instance.new("UICorner")
	ballCorner.CornerRadius = UDim.new(0.5, 0)
	ballCorner.Parent       = ball

	local ballLbl = Instance.new("TextLabel")
	ballLbl.Size                = UDim2.fromScale(1, 1)
	ballLbl.BackgroundTransparency = 1
	ballLbl.Font                = Enum.Font.GothamBold
	ballLbl.TextScaled          = true
	ballLbl.Text                = "⚽"
	ballLbl.ZIndex              = 5
	ballLbl.Parent              = ball
	ballFrame = ball

	-- ── Stats (right column) ─────────────────────────────────────────────
	local statsFrame = Instance.new("Frame")
	statsFrame.Size             = UDim2.fromOffset(300, 280)
	statsFrame.Position         = UDim2.fromOffset(280, 110)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent           = panel

	local juggleLbl = Instance.new("TextLabel")
	juggleLbl.Name               = "JuggleCount"
	juggleLbl.Size               = UDim2.fromOffset(300, 120)
	juggleLbl.Position           = UDim2.fromOffset(0, 30)
	juggleLbl.BackgroundTransparency = 1
	juggleLbl.Font               = Enum.Font.GothamBold
	juggleLbl.TextScaled         = true
	juggleLbl.TextColor3         = Color3.fromRGB(255, 255, 100)
	juggleLbl.Text               = "0"
	juggleLbl.Parent             = statsFrame
	countLbl = juggleLbl

	local juggleCaption = Instance.new("TextLabel")
	juggleCaption.Size               = UDim2.fromOffset(300, 30)
	juggleCaption.Position           = UDim2.fromOffset(0, 150)
	juggleCaption.BackgroundTransparency = 1
	juggleCaption.Font               = Enum.Font.Gotham
	juggleCaption.TextScaled         = true
	juggleCaption.TextColor3         = Color3.fromRGB(180, 180, 200)
	juggleCaption.Text               = "JUGGLES"
	juggleCaption.Parent             = statsFrame

	local timeLbl = Instance.new("TextLabel")
	timeLbl.Name                = "Timer"
	timeLbl.Size                = UDim2.fromOffset(300, 70)
	timeLbl.Position            = UDim2.fromOffset(0, 195)
	timeLbl.BackgroundTransparency = 1
	timeLbl.Font                = Enum.Font.GothamBold
	timeLbl.TextScaled          = true
	timeLbl.TextColor3          = Color3.fromRGB(220, 220, 220)
	timeLbl.Text                = "00:30"
	timeLbl.Parent              = statsFrame
	timerLbl = timeLbl

	-- ── TAP button ───────────────────────────────────────────────────────
	local tap = Instance.new("TextButton")
	tap.Name                = "TapButton"
	tap.Size                = UDim2.new(1, -60, 0, 74)
	tap.Position            = UDim2.fromOffset(30, 422)
	tap.BackgroundColor3    = COL_RED
	tap.BorderSizePixel     = 0
	tap.Font                = Enum.Font.GothamBold
	tap.TextScaled          = true
	tap.TextColor3          = Color3.fromRGB(255, 255, 255)
	tap.Text                = "TAP!"
	tap.Parent              = panel
	local tapCorner = Instance.new("UICorner")
	tapCorner.CornerRadius = UDim.new(0, 12)
	tapCorner.Parent       = tap
	tapButton = tap

	tap.Activated:Connect(function()
		onTap()
		-- Quick press visual feedback
		TweenService:Create(tap, TweenInfo.new(0.08), { Size = UDim2.new(1, -80, 0, 66) }):Play()
		task.delay(0.10, function()
			TweenService:Create(tap, TweenInfo.new(0.08), { Size = UDim2.new(1, -60, 0, 74) }):Play()
		end)
	end)

	return g
end

function Juggle.show(info: { duration: number, startTime: number, freq: number }, onTap: () -> ())
	Juggle.hide()

	sessionStart  = os.clock()
	sessionLen    = info.duration
	currentFreq   = info.freq
	Juggle.active = true

	gui = buildGui(onTap)

	beatConn = RunService.Heartbeat:Connect(function()
		if not Juggle.active then return end

		local t = os.clock() - sessionStart
		-- Sine wave: 0 at bottom, 1 at top, 0.5 at centre (sweet spot)
		local ballY = 0.5 + 0.5 * math.sin(t * currentFreq * math.pi * 2)
		local yPos  = TRAVEL_BOTTOM - (TRAVEL_BOTTOM - TRAVEL_TOP) * ballY

		local bf = ballFrame
		if bf and bf.Parent then
			bf.Position = UDim2.fromScale(0.5, yPos)
		end

		local inZone = ballY >= ZONE_LO and ballY <= ZONE_HI
		local btn = tapButton
		if btn and btn.Parent then
			btn.BackgroundColor3 = if inZone then COL_GREEN else COL_RED
		end

		local tl = timerLbl
		if tl and tl.Parent then
			tl.Text = fmt(sessionLen - t)
		end
	end)
end

function Juggle.update(info: { count: number, streak: number, freq: number })
	currentFreq  = info.freq
	local lbl = countLbl
	if lbl and lbl.Parent then
		lbl.Text = tostring(info.count)
	end
	-- Small scale pop on the count label for feel
	local tw = TweenService:Create(
		lbl :: TextLabel,
		TweenInfo.new(0.08),
		{ TextTransparency = 0 }
	)
	tw:Play()
end

function Juggle.hide()
	Juggle.active = false
	if beatConn then
		beatConn:Disconnect()
		beatConn = nil
	end
	local g = gui
	if g and g.Parent then
		g:Destroy()
	end
	gui        = nil
	ballFrame  = nil
	tapButton  = nil
	countLbl   = nil
	timerLbl   = nil
end

return Juggle
