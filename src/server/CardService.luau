--!strict
-- CardService: wires the collectible-card system. Pushes the collection snapshot on join + after
-- changes, and handles pack-opening (DataService owns the economy + rolls server-side, so the
-- client can't fake cards). Packs are granted from playing (see grantPack hooks in the modes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local CardService = {}

local function push(player: Player)
	local info = DataService.cardInfo(player)
	if info then
		Net.getEvent(Net.Events.CardState):FireClient(player, info)
	end
end

function CardService.start()
	DataService.onProfileLoaded(function(player: Player)
		push(player)
	end)

	Net.getEvent(Net.Events.CardOpen).OnServerEvent:Connect(function(player: Player)
		local result = DataService.openPack(player)
		if result then
			Net.getEvent(Net.Events.CardOpened):FireClient(player, result)
		end
		push(player)
	end)
end

return CardService
