--!strict
-- StoreService: the Daily Deals coin store. Pushes the current line-up to clients (on join, after a
-- purchase, and on a slow heartbeat so the list flips when the UTC day rolls over), and handles
-- StoreBuy. DataService owns the actual coin spend + effect and the once-per-day claim guard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local StoreService = {}

local function pushTo(player: Player)
	local info = DataService.storeInfo(player)
	if info then
		Net.getEvent(Net.Events.StoreState):FireClient(player, info)
	end
end

function StoreService.start()
	DataService.onProfileLoaded(pushTo)

	Net.getEvent(Net.Events.StoreBuy).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			if typeof(payload) ~= "table" then
				return
			end
			local id = (payload :: { [string]: unknown }).id
			if type(id) ~= "string" then
				return
			end
			local ok, message = DataService.buyDeal(player, id)
			Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
			if ok then
				pushTo(player) -- reflect the spent coins + claimed deal
			end
		end)

	-- Heartbeat so an open store flips to the new line-up the moment the UTC day rolls over.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in Players:GetPlayers() do
				pushTo(p)
			end
		end
	end)
end

return StoreService
