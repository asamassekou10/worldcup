--!strict
-- Theme: the single source of truth for the UI's visual language -- palette,
-- fonts, radii. Centralised so every screen reads as one cohesive product.

local Theme = {}

-- Palette
Theme.Accent = Color3.fromRGB(46, 200, 112) -- vibrant pitch green
Theme.AccentDark = Color3.fromRGB(26, 150, 84)
Theme.Gold = Color3.fromRGB(255, 206, 72)
Theme.Bg = Color3.fromRGB(13, 16, 23) -- panel backdrops
Theme.Panel = Color3.fromRGB(24, 28, 38)
Theme.PanelLight = Color3.fromRGB(36, 41, 54)
Theme.Stroke = Color3.fromRGB(60, 68, 86)
Theme.Text = Color3.fromRGB(240, 244, 252)
Theme.Subtext = Color3.fromRGB(165, 176, 196)
Theme.Danger = Color3.fromRGB(224, 86, 74)

-- Fonts
Theme.FontTitle = Enum.Font.GothamBlack
Theme.FontBold = Enum.Font.GothamBold
Theme.FontBody = Enum.Font.GothamMedium

-- Shape
Theme.Corner = 12
Theme.Shadow = "rbxassetid://1316045217" -- common soft 9-slice drop shadow

return Theme
