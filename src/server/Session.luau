--!strict
-- Session: in-memory per-player score for Slice 1.
-- In Slice 3 this gets backed by ProfileStore so stats persist across sessions.

local Session = {}

export type Score = { goals: number, shots: number }

local scores: { [Player]: Score } = {}

function Session.get(player: Player): Score
	local existing = scores[player]
	if existing then
		return existing
	end
	local fresh: Score = { goals = 0, shots = 0 }
	scores[player] = fresh
	return fresh
end

function Session.clear(player: Player)
	scores[player] = nil
end

return Session
