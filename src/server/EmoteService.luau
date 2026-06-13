--!strict
-- EmoteService: validates + rate-limits in-match emotes, then broadcasts them so
-- every client can pop the emoji above the sender's head. Cosmetic only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

local EmoteService = {}

local COOLDOWN = 1 -- seconds between a player's emotes
local lastEmote: { [Player]: number } = {}

local function isAllowed(emoji: string): boolean
	for _, e in Config.Emotes do
		if e == emoji then
			return true
		end
	end
	return false
end

function EmoteService.handle(player: Player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local emoji = (payload :: { [string]: unknown }).emoji
	if typeof(emoji) ~= "string" or not isAllowed(emoji) then
		return
	end
	local now = os.clock()
	if now - (lastEmote[player] or 0) < COOLDOWN then
		return -- rate-limited
	end
	lastEmote[player] = now
	Net.getEvent(Net.Events.EmoteShown):FireAllClients({ userId = player.UserId, emoji = emoji })
end

function EmoteService.onPlayerRemoving(player: Player)
	lastEmote[player] = nil
end

Players.PlayerRemoving:Connect(EmoteService.onPlayerRemoving)

return EmoteService
