--!strict
-- TreadmillService: "Training Grounds". Stand on a treadmill in the plaza to earn coins +
-- XP per tick (server-authoritative). Monetized by a 2x GAMEPASS (Config.Treadmill.TwoxPassId)
-- and an Energy Drink DEV PRODUCT (Config.Treadmill.EnergyProductId) -> a temporary boost
-- that stacks on top. Other services (TriviaParkourService) register the belt zones.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))

local TreadmillService = {}

type Zone = { x: number, y: number, z: number, r: number }
local zones: { Zone } = {}
local energyUntil: { [Player]: number } = {} -- os.time() the Energy Drink boost expires
local processedEnergy: { [string]: boolean } = {} -- receipt idempotency (session)

-- Register a treadmill belt as a circular standing zone (world position + radius).
function TreadmillService.registerZone(pos: Vector3, radius: number)
	table.insert(zones, { x = pos.X, y = pos.Y, z = pos.Z, r = radius })
end

local function onTreadmill(root: BasePart): boolean
	local p = root.Position
	for _, z in zones do
		local dx, dz = p.X - z.x, p.Z - z.z
		if dx * dx + dz * dz <= z.r * z.r and math.abs(p.Y - z.y) <= 6 then
			return true
		end
	end
	return false
end

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

function TreadmillService.start()
	local T = Config.Treadmill

	-- Energy Drink dev product -> a timed training boost (idempotent per receipt).
	MonetizationService.registerProduct(
		T.EnergyProductId,
		function(player: Player, purchaseId: string): boolean
			if processedEnergy[purchaseId] then
				return true
			end
			processedEnergy[purchaseId] = true
			local base = math.max(energyUntil[player] or 0, os.time())
			energyUntil[player] = base + T.EnergyDurationSec
			notify(
				player,
				string.format(
					"⚡ Energy Drink! %d× training for %d min",
					T.EnergyMultiplier,
					T.EnergyDurationSec // 60
				)
			)
			return true
		end
	)

	-- Training payout loop: anyone standing on a belt earns coins + XP each tick.
	task.spawn(function()
		while true do
			task.wait(T.TickSeconds)
			if #zones == 0 then
				continue
			end
			for _, player in Players:GetPlayers() do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and onTreadmill(root) then
					local mult = 1
					if MonetizationService.ownsPass(player, T.TwoxPassId) then
						mult *= 2 -- 2x Training gamepass
					end
					local energy = (energyUntil[player] or 0) > os.time()
					if energy then
						mult *= T.EnergyMultiplier -- Energy Drink boost
					end
					local coins = math.floor(T.CoinsPerTick * mult)
					local xp = math.floor(T.XpPerTick * mult)
					DataService.grantReward(player, coins, xp)
					Net.getEvent(Net.Events.TreadmillTick)
						:FireClient(player, { coins = coins, xp = xp, energy = energy })
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		energyUntil[player] = nil
	end)
end

return TreadmillService
