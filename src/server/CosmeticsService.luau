--!strict
-- CosmeticsService: the shop's server brain. Validates purchases and equips
-- against the player's authoritative profile, then shows the equipped country
-- flag as a billboard above their head. The Catalog is the menu; coins and
-- ownership only ever change here, through DataService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local CosmeticsService = {}

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

-- (Re)draw the equipped flag above the player's head.
local function applyToCharacter(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	local existing = head:FindFirstChild("FanFlag")
	if existing then
		existing:Destroy()
	end

	local cosmetic = Catalog.get(data.Equipped)
	if not cosmetic then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FanFlag"
	billboard.Size = UDim2.fromOffset(38, 38)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	billboard.MaxDistance = 70

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = cosmetic.emoji
	label.Parent = billboard

	billboard.Parent = head
end

function CosmeticsService.buy(player: Player, id: string)
	local cosmetic = Catalog.get(id)
	local data = DataService.get(player)
	if not cosmetic or not data then
		return
	end
	if Catalog.isOwned(data, id) then
		notify(player, "You already own " .. cosmetic.name)
		return
	end
	if not DataService.trySpend(player, cosmetic.price) then
		notify(player, "Not enough coins for " .. cosmetic.name)
		return
	end
	DataService.grantCosmetic(player, id)
	notify(player, cosmetic.name .. " purchased!")
end

function CosmeticsService.equip(player: Player, id: string)
	local cosmetic = Catalog.get(id)
	local data = DataService.get(player)
	if not cosmetic or not data then
		return
	end
	if not Catalog.isOwned(data, id) then
		notify(player, "You don't own " .. cosmetic.name)
		return
	end
	DataService.setEquipped(player, id)
	applyToCharacter(player)
	notify(player, cosmetic.name .. " equipped")
end

local function idFromPayload(payload: unknown): string?
	if typeof(payload) ~= "table" then
		return nil
	end
	local id = (payload :: { [string]: unknown }).id
	return if type(id) == "string" then id else nil
end

local function hookCharacter(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2) -- let the Head replicate
		applyToCharacter(player)
	end)
	if player.Character then
		applyToCharacter(player)
	end
end

function CosmeticsService.start()
	Net.getEvent(Net.Events.BuyCosmetic).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			local id = idFromPayload(payload)
			if id then
				CosmeticsService.buy(player, id)
			end
		end)

	Net.getEvent(Net.Events.EquipCosmetic).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			local id = idFromPayload(payload)
			if id then
				CosmeticsService.equip(player, id)
			end
		end)

	-- Re-apply the equipped flag whenever data loads or the character respawns.
	DataService.onProfileLoaded(applyToCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
	Players.PlayerAdded:Connect(hookCharacter)
end

return CosmeticsService
