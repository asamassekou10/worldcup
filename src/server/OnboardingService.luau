--!strict
-- OnboardingService: drives the sub-60s FTUE "Rookie Rewards" path. New players see a 3-step
-- checklist; finishing it (all instant or near-instant) makes the first session feel rewarding fast
-- and teaches the core loops. The reward logic + one-time guards live in DataService; this wires the
-- triggers:
--   * gift  -> an instant tap (WelcomeClaim)
--   * pack  -> the first time they open a card pack (CardOpen)
--   * mode  -> the first time they jump to a mode via the PLAY menu (GotoActivity)
-- Listening on CardOpen/GotoActivity here is an ADDITIONAL connection (CardService/ActivityService
-- still handle the actual action); we only watch to tick the rookie step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local OnboardingService = {}

-- Always send the latest state (including the final complete=true) so the client can celebrate +
-- dismiss the checklist. The join hook gates separately so veterans are never bothered.
local function pushWelcome(player: Player)
	local info = DataService.rookieInfo(player)
	if info then
		Net.getEvent(Net.Events.WelcomeState):FireClient(player, info)
	end
end

-- Tick a step that completes by DOING something (pack/mode), but only while the player is still a
-- rookie and hasn't earned that step yet.
local function tickStep(player: Player, step: string)
	local info = DataService.rookieInfo(player)
	if info and not info.complete and not info.done[step] then
		DataService.claimRookieStep(player, step)
		pushWelcome(player)
	end
end

function OnboardingService.start()
	DataService.onProfileLoaded(function(player: Player)
		local info = DataService.rookieInfo(player)
		if info and not info.complete then
			pushWelcome(player) -- only greet genuine new players on join
		end
	end)

	Net.getEvent(Net.Events.WelcomeClaim).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			if typeof(payload) ~= "table" then
				return
			end
			local step = (payload :: { step: unknown }).step
			if step == "gift" then
				DataService.claimRookieStep(player, "gift")
				pushWelcome(player)
			end
		end)

	Net.getEvent(Net.Events.CardOpen).OnServerEvent:Connect(function(player: Player)
		tickStep(player, "pack")
	end)

	Net.getEvent(Net.Events.GotoActivity).OnServerEvent:Connect(function(player: Player)
		tickStep(player, "mode")
	end)
end

return OnboardingService
