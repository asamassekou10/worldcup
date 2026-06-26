--!strict
-- ClubService: wires the idle "Football Club" (DataService owns the economy). Pushes the club
-- snapshot to the client on join + after each action, and routes claim/upgrade requests. The
-- club is the daily return hook -- it earns coins passively (even offline) that you bank + reinvest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local ClubService = {}

local function push(player: Player)
	local info = DataService.clubInfo(player)
	if info then
		Net.getEvent(Net.Events.ClubState):FireClient(player, info)
	end
end

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

function ClubService.start()
	DataService.onProfileLoaded(function(player: Player)
		push(player)
	end)

	Net.getEvent(Net.Events.ClubAction).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			local action = if type(payload) == "table" then (payload :: any).action else nil
			if action == "claim" then
				local got = DataService.clubClaim(player)
				if got > 0 then
					notify(player, string.format("🏟️ Club payout banked — +%d coins!", got))
				end
			elseif action == "upgrade" then
				local ok, message = DataService.clubUpgrade(player)
				notify(player, message)
				local _ = ok
			end
			push(player)
		end)
end

return ClubService
