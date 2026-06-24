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

-- DataService is loaded before MonetizationService in init.server.luau, so this
-- require is safe (no circular init; both are ModuleScripts cached by the VM).
local DataService = require(script.Parent:WaitForChild("DataService"))

local MonetizationService = {}

local DOUBLER_ID = Config.Monetization.CoinDoublerGamepassId
local SEASON_PASS_ID = Config.Monetization.SeasonPassId
-- EVERY gamepass that ownsPass() must answer for -- queried + cached on join, and flipped
-- on purchase. Add new boost passes HERE, or ownsPass() will always return false for them.
local BOOST_PASS_IDS: { number } = {
	Config.ParkourBoosts.SpeedPassId,
	Config.ParkourBoosts.PointsDoublerPassId,
	Config.ParkourBoosts.SneakPeekPassId,
	Config.ParkourBoosts.TrailPassId,
	Config.Treadmill.TwoxPassId,
}
local ownsDoubler: { [Player]: boolean } = {}
-- Generic gamepass ownership (parkour boosts etc.), queried via MonetizationService.ownsPass.
local passOwnership: { [Player]: { [number]: boolean } } = {}
-- Other services register handlers for their own developer products here, so the single
-- ProcessReceipt callback can route to them without this module depending on them.
local productHandlers: { [number]: (player: Player, purchaseId: string) -> boolean } = {}

-- Build a productId -> coins lookup from the configured coin packs.
local productCoins: { [number]: number } = {}
for _, pack in Config.Monetization.CoinPacks do
	if pack.productId > 0 then
		productCoins[pack.productId] = pack.coins
	end
end

-- Does the player own a given gamepass (live cache; false for unset/0 ids)?
function MonetizationService.ownsPass(player: Player, passId: number): boolean
	if passId <= 0 then
		return false
	end
	local owned = passOwnership[player]
	return owned ~= nil and owned[passId] == true
end

-- Register a developer-product handler. handler(player, purchaseId) -> granted?.
function MonetizationService.registerProduct(
	productId: number,
	handler: (player: Player, purchaseId: string) -> boolean
)
	if productId > 0 then
		productHandlers[productId] = handler
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

	if SEASON_PASS_ID > 0 then
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, SEASON_PASS_ID)
		end)
		if ok and result == true then
			DataService.activatePremiumPass(player)
		end
	end

	-- Boost gamepasses (parkour perks + treadmill 2x): generic ownership cache.
	local owned: { [number]: boolean } = {}
	for _, id in BOOST_PASS_IDS do
		if id > 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			owned[id] = ok and result == true
		end
	end
	passOwnership[player] = owned

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
	if coins then
		if DataService.grantPurchase(player, tostring(receipt.PurchaseId), coins) then
			Net.getEvent(Net.Events.Notify):FireClient(player, { message = `+{coins} coins!` })
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- A product another service registered (e.g. the parkour skip token).
	local handler = productHandlers[receipt.ProductId]
	if handler then
		if handler(player, tostring(receipt.PurchaseId)) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Unknown product for this place; let Roblox retry rather than swallow it.
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
		passOwnership[player] = nil
	end)

	-- Gamepass purchases finish on the server; flip perks on immediately.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			local isBoost = false
			for _, id in BOOST_PASS_IDS do
				if id > 0 and gamePassId == id then
					isBoost = true
					break
				end
			end
			if isBoost then
				local owned = passOwnership[player] or {}
				owned[gamePassId] = true
				passOwnership[player] = owned
				Net.getEvent(Net.Events.Notify)
					:FireClient(player, { message = "✅ Pass unlocked!" })
			elseif gamePassId == DOUBLER_ID then
				ownsDoubler[player] = true
				sendInfo(player)
				Net.getEvent(Net.Events.Notify)
					:FireClient(player, { message = "2× Coins unlocked!" })
			elseif gamePassId == SEASON_PASS_ID then
				DataService.activatePremiumPass(player)
				Net.getEvent(Net.Events.Notify):FireClient(
					player,
					{ message = "🏆 Road to the Final — Premium Pass activated!" }
				)
			end
		end
	)

	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService
