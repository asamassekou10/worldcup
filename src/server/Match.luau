--!strict
-- Match: a free-for-all penalty shootout for 2-8 players. Each turn one player
-- SHOOTS and the next KEEPS (round-robin), everyone else spectates. Shooter and
-- keeper choose simultaneously; the server resolves. Goals = points; after every
-- player has shot a fixed number of times, the most goals wins. Runs as a
-- coroutine: broadcast turn -> await both inputs (or deadline) -> resolve ->
-- broadcast result -> repeat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))

local Penalty = require(script.Parent:WaitForChild("Penalty"))
local Pitch = require(script.Parent:WaitForChild("Pitch"))
local Decor = require(script.Parent:WaitForChild("Decor"))

local TURNS_PER_PLAYER = 3
local TURN_SECONDS = 7 -- time to pick a shot / dive
local RESULT_SECONDS = 2 -- how long the result is shown
local POLL_SECONDS = 0.15

local Match = {}
Match.__index = Match

export type Input = { x: number, y: number, power: number, curve: number }

export type Match = typeof(setmetatable(
	{} :: {
		players: { Player },
		present: { [Player]: boolean },
		scores: { [Player]: number }, -- goals
		saves: { [Player]: number },
		inputs: { [Player]: Input },
		active: boolean,
		finished: boolean,
		onFinished: (() -> ())?,
		onPlayerResult: ((player: Player, won: boolean, goals: number, saves: number) -> ())?,
	},
	Match
))

local rng = Random.new()

local function randomInput(): Input
	return {
		x = rng:NextNumber(-0.7, 0.7),
		y = rng:NextNumber(0.15, 0.9),
		power = rng:NextNumber(0.4, 0.8),
		curve = rng:NextNumber(-0.6, 0.6),
	}
end

function Match.new(players: { Player }): Match
	local self = setmetatable({}, Match) :: Match
	self.players = table.clone(players)
	self.present = {}
	self.scores = {}
	self.saves = {}
	for _, player in players do
		self.present[player] = true
		self.scores[player] = 0
		self.saves[player] = 0
	end
	self.inputs = {}
	self.active = true
	self.finished = false
	self.onFinished = nil
	self.onPlayerResult = nil
	return self
end

local function activeCount(self: Match): number
	local n = 0
	for _, player in self.players do
		if self.present[player] and player.Parent == Players then
			n += 1
		end
	end
	return n
end

-- The live table from `viewer`'s point of view, ranked by goals.
local function standingsFor(self: Match, viewer: Player): { Types.StandingEntry }
	local entries: { Types.StandingEntry } = {}
	for _, player in self.players do
		table.insert(entries, {
			name = player.DisplayName,
			goals = self.scores[player],
			isYou = player == viewer,
		})
	end
	table.sort(entries, function(a, b)
		return a.goals > b.goals
	end)
	return entries
end

-- Accept a player's choice for the current turn. First submission wins.
function Match.submit(self: Match, player: Player, payload: unknown)
	if not self.active or self.inputs[player] then
		return
	end
	if table.find(self.players, player) == nil then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local raw = payload :: { [string]: unknown }
	self.inputs[player] = {
		x = math.clamp(tonumber(raw.x) or 0, -1.3, 1.3),
		y = math.clamp(tonumber(raw.y) or 0.5, 0, 1.2),
		power = math.clamp(tonumber(raw.power) or 0.5, 0, 1),
		curve = math.clamp(tonumber(raw.curve) or 0, -1, 1),
	}
end

function Match.broadcastTurnStart(
	self: Match,
	shooter: Player,
	keeper: Player,
	turnIndex: number,
	totalTurns: number,
	deadline: number
)
	local event = Net.getEvent(Net.Events.RoundStart)
	for _, player in self.players do
		if player.Parent == Players then
			local role: Types.Role = if player == shooter
				then "Shooter"
				elseif player == keeper then "Keeper"
				else "Spectator"
			local info: Types.RoundStartInfo = {
				role = role,
				shooterName = shooter.DisplayName,
				keeperName = keeper.DisplayName,
				turnIndex = turnIndex,
				totalTurns = totalTurns,
				deadline = deadline,
				standings = standingsFor(self, player),
			}
			event:FireClient(player, info)
		end
	end
end

function Match.broadcastTurnResult(
	self: Match,
	shooter: Player,
	keeper: Player,
	result: Types.ShotResult
)
	local event = Net.getEvent(Net.Events.RoundResult)
	for _, player in self.players do
		if player.Parent == Players then
			local info: Types.RoundResultInfo = {
				outcome = result.outcome,
				shotX = result.shotX,
				shotY = result.shotY,
				keeperX = result.keeperX,
				keeperY = result.keeperY,
				curve = result.curve,
				youWereShooter = player == shooter,
				youWereKeeper = player == keeper,
				shooterName = shooter.DisplayName,
				keeperName = keeper.DisplayName,
				standings = standingsFor(self, player),
			}
			event:FireClient(player, info)
		end
	end
end

function Match.run(self: Match)
	local n = #self.players
	local totalTurns = n * TURNS_PER_PLAYER

	for turn = 0, totalTurns - 1 do
		if not self.active or activeCount(self) < 2 then
			break
		end
		-- Round-robin: player `turn` shoots, the next keeps.
		local shooter = self.players[(turn % n) + 1]
		local keeper = self.players[((turn + 1) % n) + 1]

		self.inputs = {}
		Pitch.positionPlayers(self.players, shooter, keeper) -- stage shooter + keeper
		local deadline = workspace:GetServerTimeNow() + TURN_SECONDS
		Match.broadcastTurnStart(self, shooter, keeper, turn + 1, totalTurns, deadline)

		while
			self.active
			and not (self.inputs[shooter] and self.inputs[keeper])
			and workspace:GetServerTimeNow() < deadline
		do
			task.wait(POLL_SECONDS)
		end
		if not self.active then
			break
		end

		local shot = self.inputs[shooter] or randomInput()
		local guess = self.inputs[keeper] or randomInput()
		local result = Penalty.resolveSkill(shot, { x = guess.x, y = guess.y })
		if result.outcome == "Goal" then
			self.scores[shooter] += 1
			Decor.goalBurst() -- firework over the goal
		elseif result.outcome == "Save" then
			self.saves[keeper] += 1
		end

		Pitch.kickShooter(shooter) -- lunge as the ball launches
		Pitch.keeperDive(keeper, guess.x) -- keeper commits to their guess
		Match.broadcastTurnResult(self, shooter, keeper, result)
		task.wait(RESULT_SECONDS)
	end

	Match.finish(self)
end

function Match.finish(self: Match, reason: string?)
	if self.finished then
		return
	end
	self.finished = true
	self.active = false

	-- Rank the players who are still here, by goals.
	local ranking: { Player } = {}
	for _, player in self.players do
		if self.present[player] and player.Parent == Players then
			table.insert(ranking, player)
		end
	end
	table.sort(ranking, function(a, b)
		return self.scores[a] > self.scores[b]
	end)
	local topGoals = if #ranking > 0 then self.scores[ranking[1]] else 0

	local matchOver = Net.getEvent(Net.Events.MatchOver)
	for placement, player in ranking do
		local won = self.scores[player] == topGoals
		local info: Types.MatchOverInfo = {
			won = won,
			placement = placement,
			total = #ranking,
			standings = standingsFor(self, player),
			reason = reason,
		}
		matchOver:FireClient(player, info)
		if self.onPlayerResult then
			self.onPlayerResult(player, won, self.scores[player], self.saves[player])
		end
	end

	-- Winner ceremony: fireworks + a trophy lift, then send everyone home.
	if #ranking > 0 then
		Decor.celebrate(ranking[1])
		task.wait(4)
	end
	Pitch.releasePlayers(self.players) -- unanchor + back to the lobby

	if self.onFinished then
		self.onFinished()
	end
end

-- A player disconnected: drop them from the rotation. If fewer than two remain,
-- the run loop ends and the match wraps up.
function Match.onPlayerLeft(self: Match, player: Player)
	self.present[player] = false
	if activeCount(self) < 2 then
		self.active = false
	end
end

return Match
