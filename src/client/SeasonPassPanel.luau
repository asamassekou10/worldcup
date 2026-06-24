--!strict
-- SeasonPassPanel: the "Road to the Final" season pass -- the lobby mini-badge AND
-- the full 40-tier panel -- extracted from UI.luau to free UI.create's local budget
-- (the 40 tier rows + badge + panel were ~17 locals). The host injects styling
-- helpers + a lobby toggle, and supplies callbacks for the buy prompt and for
-- marking the Store's season-pass row as owned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SeasonPass = require(Shared:WaitForChild("SeasonPass"))
local Theme = require(Shared:WaitForChild("Theme"))
local Sound = require(script.Parent:WaitForChild("Sound"))

-- The HUD ScreenGui uses CoreUISafeInsets, which already clears the topbar/notch, so the
-- lobby badge needs no manual top shift -- kept as a 0 no-op to match UI.luau.
local TOP_INSET = 0

local SeasonPassPanel = {}

export type Info = {
	SeasonXP: number,
	SeasonTierGranted: number,
	HasPremiumPass: boolean,
	EquippedTitle: string,
}

export type Deps = {
	corner: (g: GuiObject, r: number) -> (),
	gradient: (g: GuiObject, top: Color3, bottom: Color3, rotation: number?) -> (),
	polish: (b: GuiButton, primary: boolean?) -> (),
	decoratePanel: (panel: GuiObject, title: TextLabel, close: GuiButton?) -> (),
	showPanel: (panel: GuiObject) -> (),
	setLobbyVisible: (visible: boolean) -> (),
	onBuy: () -> (),
	onPremiumOwned: () -> (),
}

export type Controller = {
	setSeasonPass: (info: Info) -> (),
}

local function rewardText(r: SeasonPass.Reward): string
	if r.kind == "coins" then
		return string.format("💰 %d", r.amount or 0)
	elseif r.kind == "title" then
		local id = r.id or ""
		return string.format("🏅 %s", SeasonPass.TitleLabels[id] or id)
	elseif r.kind == "xpboost" then
		local hrs = math.floor((r.amount or 0) / 3600)
		return string.format("⚡ 2× XP (%dh)", hrs)
	end
	return ""
end

function SeasonPassPanel.build(screen: ScreenGui, lobby: Frame, deps: Deps): Controller
	local corner = deps.corner

	-- ===== Lobby mini-badge: a thin clickable strip below the XP bar =====
	local spBadge = Instance.new("TextButton")
	spBadge.Size = UDim2.fromScale(0.22, 0.026)
	spBadge.Position = UDim2.new(0.02, 0, 0.212, TOP_INSET)
	spBadge.BackgroundColor3 = Color3.fromRGB(22, 28, 44)
	spBadge.BackgroundTransparency = 0.15
	spBadge.Text = ""
	corner(spBadge, 6)
	local spBadgeStroke = Instance.new("UIStroke")
	spBadgeStroke.Color = Color3.fromRGB(240, 200, 40)
	spBadgeStroke.Thickness = 1.5
	spBadgeStroke.Transparency = 0.4
	spBadgeStroke.Parent = spBadge
	spBadge.Parent = lobby

	local spBadgeTierLabel = Instance.new("TextLabel")
	spBadgeTierLabel.Size = UDim2.fromScale(0.68, 0.9)
	spBadgeTierLabel.Position = UDim2.fromScale(0.02, 0.05)
	spBadgeTierLabel.BackgroundTransparency = 1
	spBadgeTierLabel.Font = Enum.Font.GothamBold
	spBadgeTierLabel.TextScaled = true
	spBadgeTierLabel.TextXAlignment = Enum.TextXAlignment.Left
	spBadgeTierLabel.TextColor3 = Color3.fromRGB(240, 200, 40)
	spBadgeTierLabel.Text = "SEASON PASS  Tier 0/40"
	spBadgeTierLabel.Parent = spBadge

	local spBadgeBarBg = Instance.new("Frame")
	spBadgeBarBg.Size = UDim2.fromScale(0.28, 0.3)
	spBadgeBarBg.Position = UDim2.fromScale(0.7, 0.35)
	spBadgeBarBg.BackgroundColor3 = Color3.fromRGB(30, 34, 50)
	corner(spBadgeBarBg, 4)
	spBadgeBarBg.Parent = spBadge

	local spBadgeFill = Instance.new("Frame")
	spBadgeFill.Size = UDim2.fromScale(0, 1)
	spBadgeFill.BackgroundColor3 = Color3.fromRGB(240, 200, 40)
	corner(spBadgeFill, 4)
	spBadgeFill.Parent = spBadgeBarBg

	-- ===== Full panel =====
	local panel = Instance.new("Frame")
	panel.Name = "SeasonPassPanel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Bg
	deps.gradient(panel, Color3.fromRGB(28, 36, 52), Theme.Bg)
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = screen

	local spTitle = Instance.new("TextLabel")
	spTitle.Size = UDim2.fromScale(0.6, 0.08)
	spTitle.Position = UDim2.fromScale(0.06, 0.03)
	spTitle.BackgroundTransparency = 1
	spTitle.Font = Enum.Font.GothamBlack
	spTitle.TextScaled = true
	spTitle.TextXAlignment = Enum.TextXAlignment.Left
	spTitle.TextColor3 = Color3.fromRGB(240, 200, 40)
	spTitle.Text = "ROAD TO THE FINAL"
	spTitle.Parent = panel

	local spEndDate = Instance.new("TextLabel")
	spEndDate.Size = UDim2.fromScale(0.45, 0.04)
	spEndDate.Position = UDim2.fromScale(0.06, 0.10)
	spEndDate.BackgroundTransparency = 1
	spEndDate.Font = Enum.Font.GothamMedium
	spEndDate.TextScaled = true
	spEndDate.TextXAlignment = Enum.TextXAlignment.Left
	spEndDate.TextColor3 = Color3.fromRGB(160, 175, 200)
	spEndDate.Text = string.format("Season ends  %s", SeasonPass.EndDate)
	spEndDate.Parent = panel

	local closeSP = Instance.new("TextButton")
	closeSP.Size = UDim2.fromScale(0.1, 0.07)
	closeSP.Position = UDim2.fromScale(0.84, 0.04)
	closeSP.BackgroundColor3 = Color3.fromRGB(180, 70, 60)
	closeSP.Font = Enum.Font.GothamBlack
	closeSP.TextScaled = true
	closeSP.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeSP.Text = "X"
	corner(closeSP, 10)
	closeSP.Parent = panel
	deps.decoratePanel(panel, spTitle, closeSP)

	local spProgressBg = Instance.new("Frame")
	spProgressBg.Size = UDim2.fromScale(0.88, 0.025)
	spProgressBg.Position = UDim2.fromScale(0.06, 0.155)
	spProgressBg.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
	corner(spProgressBg, 8)
	spProgressBg.Parent = panel

	local spProgressFill = Instance.new("Frame")
	spProgressFill.Size = UDim2.fromScale(0, 1)
	spProgressFill.BackgroundColor3 = Color3.fromRGB(240, 200, 40)
	corner(spProgressFill, 8)
	spProgressFill.Parent = spProgressBg

	local spProgressLabel = Instance.new("TextLabel")
	spProgressLabel.Size = UDim2.fromScale(0.88, 0.04)
	spProgressLabel.Position = UDim2.fromScale(0.06, 0.185)
	spProgressLabel.BackgroundTransparency = 1
	spProgressLabel.Font = Enum.Font.GothamBold
	spProgressLabel.TextScaled = true
	spProgressLabel.TextXAlignment = Enum.TextXAlignment.Left
	spProgressLabel.TextColor3 = Color3.fromRGB(210, 220, 235)
	spProgressLabel.Text = "Tier 0 / 40  ·  0 XP"
	spProgressLabel.Parent = panel

	local spBuyBtn = Instance.new("TextButton")
	spBuyBtn.Size = UDim2.fromScale(0.22, 0.06)
	spBuyBtn.Position = UDim2.fromScale(0.69, 0.145)
	spBuyBtn.BackgroundColor3 = Theme.Accent
	spBuyBtn.Font = Enum.Font.GothamBlack
	spBuyBtn.TextScaled = true
	spBuyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	spBuyBtn.Text = "UPGRADE TO PREMIUM"
	corner(spBuyBtn, 10)
	spBuyBtn.Parent = panel
	deps.polish(spBuyBtn, true)
	spBuyBtn.Activated:Connect(function()
		Sound.play("Click")
		deps.onBuy()
	end)

	-- Column headers.
	local spColumnHeaders = Instance.new("Frame")
	spColumnHeaders.Size = UDim2.fromScale(0.88, 0.04)
	spColumnHeaders.Position = UDim2.fromScale(0.06, 0.232)
	spColumnHeaders.BackgroundTransparency = 1
	spColumnHeaders.Parent = panel

	local spTierHeader = Instance.new("TextLabel")
	spTierHeader.Size = UDim2.fromScale(0.15, 1)
	spTierHeader.BackgroundTransparency = 1
	spTierHeader.Font = Enum.Font.GothamBold
	spTierHeader.TextScaled = true
	spTierHeader.TextColor3 = Color3.fromRGB(160, 175, 200)
	spTierHeader.Text = "TIER"
	spTierHeader.Parent = spColumnHeaders

	local spFreeHeader = Instance.new("TextLabel")
	spFreeHeader.Size = UDim2.fromScale(0.38, 1)
	spFreeHeader.Position = UDim2.fromScale(0.17, 0)
	spFreeHeader.BackgroundTransparency = 1
	spFreeHeader.Font = Enum.Font.GothamBold
	spFreeHeader.TextScaled = true
	spFreeHeader.TextXAlignment = Enum.TextXAlignment.Left
	spFreeHeader.TextColor3 = Color3.fromRGB(210, 220, 235)
	spFreeHeader.Text = "FREE"
	spFreeHeader.Parent = spColumnHeaders

	local spPremHeader = Instance.new("TextLabel")
	spPremHeader.Size = UDim2.fromScale(0.4, 1)
	spPremHeader.Position = UDim2.fromScale(0.58, 0)
	spPremHeader.BackgroundTransparency = 1
	spPremHeader.Font = Enum.Font.GothamBold
	spPremHeader.TextScaled = true
	spPremHeader.TextXAlignment = Enum.TextXAlignment.Left
	spPremHeader.TextColor3 = Color3.fromRGB(240, 200, 40)
	spPremHeader.Text = "PREMIUM"
	spPremHeader.Parent = spColumnHeaders

	local spScroller = Instance.new("ScrollingFrame")
	spScroller.Size = UDim2.fromScale(0.88, 0.71)
	spScroller.Position = UDim2.fromScale(0.06, 0.275)
	spScroller.BackgroundTransparency = 1
	spScroller.BorderSizePixel = 0
	spScroller.ScrollBarThickness = 6
	spScroller.CanvasSize = UDim2.new()
	spScroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	spScroller.Parent = panel

	local spListLayout = Instance.new("UIListLayout")
	spListLayout.Padding = UDim.new(0, 4)
	spListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	spListLayout.Parent = spScroller

	-- All 40 tier rows (static -- rewards don't change).
	local spTierRows: { Frame } = {}
	for _, tierData in SeasonPass.Tiers do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 40)
		row.LayoutOrder = tierData.tier
		row.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
		corner(row, 6)
		row.Parent = spScroller
		table.insert(spTierRows, row)

		local tierNum = Instance.new("TextLabel")
		tierNum.Size = UDim2.fromScale(0.15, 1)
		tierNum.BackgroundTransparency = 1
		tierNum.Font = Enum.Font.GothamBold
		tierNum.TextScaled = true
		tierNum.TextColor3 = Color3.fromRGB(150, 160, 180)
		tierNum.Text = tostring(tierData.tier)
		tierNum.Parent = row

		local freeLabel = Instance.new("TextLabel")
		freeLabel.Size = UDim2.fromScale(0.38, 1)
		freeLabel.Position = UDim2.fromScale(0.17, 0)
		freeLabel.BackgroundTransparency = 1
		freeLabel.Font = Enum.Font.GothamMedium
		freeLabel.TextScaled = true
		freeLabel.TextXAlignment = Enum.TextXAlignment.Left
		freeLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
		freeLabel.Text = rewardText(tierData.free)
		freeLabel.Parent = row

		local premLabel = Instance.new("TextLabel")
		premLabel.Size = UDim2.fromScale(0.4, 1)
		premLabel.Position = UDim2.fromScale(0.58, 0)
		premLabel.BackgroundTransparency = 1
		premLabel.Font = Enum.Font.GothamMedium
		premLabel.TextScaled = true
		premLabel.TextXAlignment = Enum.TextXAlignment.Left
		premLabel.TextColor3 = Color3.fromRGB(240, 200, 40)
		premLabel.Text = rewardText(tierData.premium)
		premLabel.Parent = row
	end

	spBadge.Activated:Connect(function()
		Sound.play("Click")
		deps.setLobbyVisible(false)
		deps.showPanel(panel)
	end)

	closeSP.Activated:Connect(function()
		panel.Visible = false
		deps.setLobbyVisible(true)
	end)

	local controller = {}
	function controller.setSeasonPass(info: Info)
		local tier = SeasonPass.tierFromXp(info.SeasonXP)
		local xpInTier = info.SeasonXP - tier * SeasonPass.XpPerTier
		local fillRatio = if tier >= SeasonPass.TierCount
			then 1
			else xpInTier / SeasonPass.XpPerTier

		spBadgeTierLabel.Text = string.format("SEASON PASS  Tier %d/40", tier)
		spBadgeFill.Size = UDim2.fromScale(math.clamp(fillRatio, 0, 1), 1)

		spProgressFill.Size = UDim2.fromScale(math.clamp(fillRatio, 0, 1), 1)
		spProgressLabel.Text =
			string.format("Tier %d / %d  ·  %d XP", tier, SeasonPass.TierCount, info.SeasonXP)

		for i, row in spTierRows do
			row.BackgroundColor3 = if i <= tier
				then Color3.fromRGB(30, 42, 26)
				else Color3.fromRGB(20, 24, 34)
		end

		if info.HasPremiumPass then
			spBuyBtn.Text = "PREMIUM OWNED"
			spBuyBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 60)
			spBuyBtn.AutoButtonColor = false
			deps.onPremiumOwned() -- mark the Store's season-pass row owned too
		end
	end

	return controller
end

return SeasonPassPanel
