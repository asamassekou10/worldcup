--!strict
-- MonetizationService: the Robux side of the economy.
--   * Coin Doubler gamepass -> 2x match payouts (live ownership check).
--   * Coin-pack developer products -> coins, via an idempotent ProcessReceipt.
-- Asset IDs live in Config.Monetization; while they're 0 the checks are skipped
-- so the game runs fine before the assets exist on the Creator Dashboard.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local MonetizationService = {}

local DOUBLER_ID = Config.Monetization.CoinDoublerGamepassId
local ownsDoubler: { [Player]: boolean } = {}

-- Build a productId -> coins lookup from the configured coin packs.
local productCoins: { [number]: number } = {}
for _, pack in Config.Monetization.CoinPacks do
	if pack.productId > 0 then
		productCoins[pack.productId] = pack.coins
	end
end

local function sendInfo(player: Player)
	local info: Types.MonetizationInfo = { ownsDoubler = ownsDoubler[player] == true }
	Net.getEvent(Net.Events.MonetizationInfo):FireClient(player, info)
end

local function refreshGamepass(player: Player)
	local owns = false
	if DOUBLER_ID > 0 then
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, DOUBLER_ID)
		end)
		owns = ok and result == true
	end
	ownsDoubler[player] = owns
	sendInfo(player)
end

-- Payout multiplier for a player's matches (used by DataService.applyMatchResult).
function MonetizationService.coinMultiplier(player: Player): number
	return if ownsDoubler[player] then Config.Monetization.CoinMultiplier else 1
end

local function processReceipt(receipt: {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
}): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local coins = productCoins[receipt.ProductId]
	if not coins then
		-- Unknown product for this place; let Roblox retry rather than swallow it.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if DataService.grantPurchase(player, tostring(receipt.PurchaseId), coins) then
		Net.getEvent(Net.Events.Notify):FireClient(player, { message = `+{coins} coins!` })
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(refreshGamepass, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(refreshGamepass, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		ownsDoubler[player] = nil
	end)

	-- Gamepass purchases finish on the server; flip the perk on immediately.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if wasPurchased and gamePassId == DOUBLER_ID then
				ownsDoubler[player] = true
				sendInfo(player)
				Net.getEvent(Net.Events.Notify)
					:FireClient(player, { message = "2× Coins unlocked!" })
			end
		end
	)

	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService
