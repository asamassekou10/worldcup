--!strict
-- Onboarding: the first-time welcome / how-to-play flow. Shows ONCE for a new
-- player (HasOnboarded == false), orients them on the core loop in three beats,
-- and pushes them straight to their first match. Owns its own ScreenGui so it
-- never competes with UI.create's local budget.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

local Onboarding = {}

local player = Players.LocalPlayer
local shown = false

local function corner(g: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = g
end

local function stepCard(parent: Instance, x: number, emoji: string, title: string, body: string)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(0.3, 0.62)
	card.Position = UDim2.fromScale(x, 0.2)
	card.BackgroundColor3 = Theme.PanelLight
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = parent
	corner(card, 14)

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.fromScale(1, 0.42)
	icon.Position = UDim2.fromScale(0, 0.06)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.TextScaled = true
	icon.Text = emoji
	icon.Parent = card

	local head = Instance.new("TextLabel")
	head.Size = UDim2.fromScale(0.9, 0.16)
	head.Position = UDim2.fromScale(0.05, 0.5)
	head.BackgroundTransparency = 1
	head.Font = Theme.FontTitle
	head.TextScaled = true
	head.TextColor3 = Theme.Gold
	head.Text = title
	head.Parent = card

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(0.86, 0.26)
	text.Position = UDim2.fromScale(0.07, 0.68)
	text.BackgroundTransparency = 1
	text.Font = Theme.FontBody
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = Theme.Subtext
	text.Text = body
	text.Parent = card
end

-- Show the welcome flow unless the player has already onboarded.
function Onboarding.start(profile: Types.ProfileData)
	if shown or profile.HasOnboarded then
		return
	end
	shown = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "PenaltyKingsOnboarding"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Dim backdrop (fades in).
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(6, 9, 16)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = gui
	TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 0.25 }):Play()

	-- Centre panel.
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.74, 0.62)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Theme.Panel
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 18)
	local pscale = Instance.new("UIScale")
	pscale.Scale = 0.9
	pscale.Parent = panel
	TweenService:Create(pscale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.9, 0.13)
	title.Position = UDim2.fromScale(0.05, 0.04)
	title.BackgroundTransparency = 1
	title.Font = Theme.FontTitle
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "⚽ WELCOME TO PENALTY KINGS 👑"
	title.Parent = panel
	local tgrad = Instance.new("UIGradient")
	tgrad.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), Theme.Gold)
	tgrad.Rotation = 90
	tgrad.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(0.9, 0.06)
	sub.Position = UDim2.fromScale(0.05, 0.17)
	sub.BackgroundTransparency = 1
	sub.Font = Theme.FontBody
	sub.TextScaled = true
	sub.TextColor3 = Theme.Subtext
	sub.Text = "Outscore your rivals in penalty shootouts. Here's the play:"
	sub.Parent = panel

	-- Three steps.
	local steps = Instance.new("Frame")
	steps.Size = UDim2.fromScale(0.92, 0.5)
	steps.Position = UDim2.fromScale(0.04, 0.26)
	steps.BackgroundTransparency = 1
	steps.Parent = panel
	stepCard(steps, 0.02, "🎯", "AIM", "Drag the dot anywhere in the goal")
	stepCard(steps, 0.35, "⚡", "SHOOT", "Tap SHOOT to lock your power")
	stepCard(steps, 0.68, "🧤", "BEAT THE KEEPER", "Pick a corner and bury it!")

	-- CTA.
	local cta = Instance.new("TextButton")
	cta.Size = UDim2.fromScale(0.5, 0.13)
	cta.Position = UDim2.fromScale(0.25, 0.82)
	cta.BackgroundColor3 = Theme.Accent
	cta.Font = Theme.FontTitle
	cta.TextScaled = true
	cta.TextColor3 = Color3.fromRGB(255, 255, 255)
	cta.Text = "LET'S PLAY!  ▶"
	cta.AutoButtonColor = false
	cta.Parent = panel
	corner(cta, 14)
	local ctaStroke = Instance.new("UIStroke")
	ctaStroke.Color = Color3.fromRGB(255, 255, 255)
	ctaStroke.Thickness = 2
	ctaStroke.Transparency = 0.4
	ctaStroke.Parent = cta
	-- Gentle pulse to draw the eye.
	TweenService:Create(
		cta,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundColor3 = Theme.AccentDark }
	):Play()

	local function finish()
		Net.getEvent(Net.Events.MarkOnboarded):FireServer()
		TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		local out = TweenService:Create(
			pscale,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.85 }
		)
		TweenService:Create(panel, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		out:Play()
		out.Completed:Connect(function()
			gui:Destroy()
		end)
	end
	cta.Activated:Connect(finish)
end

return Onboarding
