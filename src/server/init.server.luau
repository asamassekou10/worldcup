--!strict
-- Server bootstrap (Slice 2: PvP). The client only ever REQUESTS things --
-- join the queue, leave it, submit a shot/dive. The server owns the queue,
-- the match state machine, and every outcome. Never trust the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local DataService = require(script:WaitForChild("DataService"))
local CosmeticsService = require(script:WaitForChild("CosmeticsService"))
local LeaderboardService = require(script:WaitForChild("LeaderboardService"))
local MonetizationService = require(script:WaitForChild("MonetizationService"))
local Matchmaking = require(script:WaitForChild("Matchmaking"))
local GauntletService = require(script:WaitForChild("GauntletService"))
local FreekickService = require(script:WaitForChild("FreekickService"))
local TriviaService = require(script:WaitForChild("TriviaService"))
local WatchPartyService = require(script:WaitForChild("WatchPartyService"))
local JuggleService = require(script:WaitForChild("JuggleService"))
local EmoteService = require(script:WaitForChild("EmoteService"))
local WarmupService = require(script:WaitForChild("WarmupService"))
local HubService = require(script:WaitForChild("HubService"))
local FieldCoinsService = require(script:WaitForChild("FieldCoinsService"))
local PredictService = require(script:WaitForChild("PredictService"))
local ResultsService = require(script:WaitForChild("ResultsService"))
local TriviaParkourService = require(script:WaitForChild("TriviaParkourService"))
local TreadmillService = require(script:WaitForChild("TreadmillService"))
local ActivityService = require(script:WaitForChild("ActivityService"))
local ClubService = require(script:WaitForChild("ClubService"))
local CardService = require(script:WaitForChild("CardService"))
local EventService = require(script:WaitForChild("EventService"))
local StoreService = require(script:WaitForChild("StoreService"))
local TournamentService = require(script:WaitForChild("TournamentService"))
local TradeService = require(script:WaitForChild("TradeService"))
local ObjectiveService = require(script:WaitForChild("ObjectiveService"))
local OnboardingService = require(script:WaitForChild("OnboardingService"))
local Pitch = require(script:WaitForChild("Pitch"))
local Decor = require(script:WaitForChild("Decor"))
local World = require(script:WaitForChild("World"))

-- Players have visible avatars and gather in a pre-game lobby on the pitch; the
-- camera follows their own character. The Match steps the shooter up to the spot
-- and benches the rest during a game. Every spawn is forced to the lobby so a
-- player can never land outside the stadium.
Players.CharacterAutoLoads = true
local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.1) -- let the root part settle after spawn
		Pitch.placeAtLobby(player)
	end)
	if player.Character then
		Pitch.placeAtLobby(player)
	end
end
for _, p in Players:GetPlayers() do
	task.spawn(watchPlayer, p)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Squad bonus: if you're in a server with a friend, you BOTH get a once-per-day coin reward --
-- the legit, ToS-clean "invite a friend" incentive (rewards playing together, not raw invites).
local function checkSquad(player: Player)
	task.spawn(function()
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local ok, isFriend = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				if ok and isFriend then
					for _, p in { player, other } do
						local reward = DataService.claimSquadBonus(p)
						if reward > 0 then
							Net.getEvent(Net.Events.Notify):FireClient(p, {
								message = string.format(
									"👥 Squad bonus — playing with a friend! +%d coins",
									reward
								),
							})
						end
					end
					break
				end
			end
		end
	end)
end
Players.PlayerAdded:Connect(checkSquad)
for _, p in Players:GetPlayers() do
	task.spawn(checkSquad, p)
end

-- Make sure every remote exists before any client asks for it.
for _, eventName in Net.Events do
	Net.getEvent(eventName :: string)
end

DataService.start()
CosmeticsService.start()
LeaderboardService.start()
MonetizationService.start()
WarmupService.start()
HubService.start()
FieldCoinsService.start()
PredictService.start()
ResultsService.start()
TriviaParkourService.start()
TreadmillService.start()
ActivityService.start()
ClubService.start()
CardService.start()
EventService.start()
StoreService.start()
TournamentService.start()
TradeService.start()
ObjectiveService.start()
OnboardingService.start()
GauntletService.start()
FreekickService.start()
TriviaService.start()
WatchPartyService.start()
JuggleService.start()
-- Guard world setup so a single error surfaces clearly (and doesn't abort the
-- rest of the bootstrap, leaving an empty sky).
local function guard(label: string, fn: () -> ...any)
	local results = { pcall(fn) }
	if not results[1] then
		warn("[PenaltyKings] " .. label .. " failed: " .. tostring(results[2]))
	end
end

-- Light the hand-built stadium and spawn the pre-game lobby. (No procedural
-- world is built -- the Workspace stadium is the scene.)
guard("setupLighting", World.setupLighting)
guard("setupLobby", Pitch.setupLobby)
guard("decor", Decor.setup)

Net.getEvent(Net.Events.JoinQueue).OnServerEvent:Connect(function(player: Player)
	Matchmaking.join(player)
end)

Net.getEvent(Net.Events.LeaveQueue).OnServerEvent:Connect(function(player: Player)
	Matchmaking.leave(player)
end)

Net.getEvent(Net.Events.SubmitInput).OnServerEvent
	:Connect(function(player: Player, payload: unknown)
		-- Route: match → gauntlet → freekick.
		if not Matchmaking.submit(player, payload) then
			if not GauntletService.submit(player, payload) then
				FreekickService.submit(player, payload)
			end
		end
	end)

Net.getEvent(Net.Events.JoinWalkOffQueue).OnServerEvent:Connect(function(player: Player)
	Matchmaking.joinWalkOff(player)
end)

Net.getEvent(Net.Events.LeaveWalkOffQueue).OnServerEvent:Connect(function(player: Player)
	Matchmaking.leaveWalkOff(player)
end)

Net.getEvent(Net.Events.ChallengePlayer).OnServerEvent
	:Connect(function(player: Player, payload: unknown)
		Matchmaking.challenge(player, payload)
	end)

Net.getEvent(Net.Events.ChallengeRespond).OnServerEvent
	:Connect(function(player: Player, payload: unknown)
		Matchmaking.respondChallenge(player, payload)
	end)

Net.getEvent(Net.Events.Emote).OnServerEvent:Connect(function(player: Player, payload: unknown)
	EmoteService.handle(player, payload)
end)

Net.getEvent(Net.Events.MarkOnboarded).OnServerEvent:Connect(function(player: Player)
	DataService.markOnboarded(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	Matchmaking.onPlayerRemoving(player)
end)

print("[PenaltyKings] Server ready (PvP).")
