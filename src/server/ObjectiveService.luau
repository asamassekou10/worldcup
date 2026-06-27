--!strict
-- ObjectiveService: pushes the daily-objective banner state to clients on join. Live progress
-- updates are fired straight from DataService.bumpDaily as the player earns toward it, so this only
-- needs to seed the banner when they arrive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local ObjectiveService = {}

function ObjectiveService.start()
	DataService.onProfileLoaded(function(player: Player)
		local info = DataService.dailyObjectiveInfo(player)
		if info then
			Net.getEvent(Net.Events.DailyObjectiveState):FireClient(player, info)
		end
	end)
end

return ObjectiveService
