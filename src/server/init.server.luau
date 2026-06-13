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
local EmoteService = require(script:WaitForChild("EmoteService"))
local WarmupService = require(script:WaitForChild("WarmupService"))
local HubService = require(script:WaitForChild("HubService"))
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
		-- The Match sanitizes the payload; matchmaking just routes it.
		Matchmaking.submit(player, payload)
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

Players.PlayerRemoving:Connect(function(player: Player)
	Matchmaking.onPlayerRemoving(player)
end)

print("[PenaltyKings] Server ready (PvP).")
