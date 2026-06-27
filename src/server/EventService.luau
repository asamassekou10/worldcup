--!strict
-- EventService: pushes the current LiveEvent to clients (on join + on a heartbeat) so the HUD
-- countdown banner stays current and updates the moment an event rotates. The actual reward
-- multipliers are applied server-side in DataService; this is just the broadcast for the UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local LiveEvents = require(Shared:WaitForChild("LiveEvents"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local EventService = {}

local function pushTo(player: Player)
	Net.getEvent(Net.Events.LiveEvent):FireClient(player, LiveEvents.current())
end

function EventService.start()
	DataService.onProfileLoaded(pushTo)
	task.spawn(function()
		while true do
			task.wait(30)
			local now = LiveEvents.current()
			for _, p in Players:GetPlayers() do
				Net.getEvent(Net.Events.LiveEvent):FireClient(p, now)
			end
		end
	end)
end

return EventService
