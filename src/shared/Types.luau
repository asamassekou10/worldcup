--!strict
-- Shared type contract. Both client and server import these so the data
-- crossing the network has one agreed-upon shape.

-- Skill aiming: continuous coordinates over the goal mouth.
--   x = -1 (left post) .. +1 (right post)
--   y =  0 (ground)    ..  1 (crossbar)
export type ShotRequest = {
	x: number,
	y: number,
	power: number, -- 0..1
	curve: number, -- -1..1, how much the ball bends in flight
}

export type ShotOutcome = "Goal" | "Save" | "Miss"

-- The resolved outcome + where the ball actually went and where the keeper dived
-- (post spread), so the client can animate to the exact points.
export type ShotResult = {
	outcome: ShotOutcome,
	shotX: number,
	shotY: number,
	keeperX: number,
	keeperY: number,
	curve: number, -- the bend applied, so the client can swerve the ball
}

-- ===== Free-for-all PvP =====

-- A player's role this turn. Only the current shooter/keeper act; the rest spectate.
export type Role = "Shooter" | "Keeper" | "Spectator"

-- Client -> server. The keeper aims where to dive (same x/y goal space).
export type KeeperInput = {
	x: number,
	y: number,
}

-- One row of the live standings (every player ranked by goals).
export type StandingEntry = {
	name: string,
	goals: number,
	isYou: boolean,
}

-- server -> client, start of every turn. `role` tells the receiving client what
-- to do; `standings` is the live table from their point of view.
export type RoundStartInfo = {
	role: Role,
	shooterName: string,
	keeperName: string,
	turnIndex: number,
	totalTurns: number,
	deadline: number, -- workspace:GetServerTimeNow() value to act by
	standings: { StandingEntry },
}

-- server -> client, after a turn resolves. Superset of the animator's needs.
export type RoundResultInfo = {
	outcome: ShotOutcome,
	shotX: number,
	shotY: number,
	keeperX: number,
	keeperY: number,
	curve: number,
	youWereShooter: boolean,
	youWereKeeper: boolean,
	shooterName: string,
	keeperName: string,
	standings: { StandingEntry },
}

export type MatchOverInfo = {
	won: boolean,
	placement: number, -- 1 = winner
	total: number, -- players ranked
	standings: { StandingEntry },
	reason: string?,
}

export type QueueInfo = {
	inQueue: boolean,
	size: number,
}

-- ===== Global leaderboards (Slice 4) =====

export type LeaderEntry = {
	name: string,
	value: number,
}

-- Top-N for each tracked board, sent to every client. `Nations` ranks national
-- teams by total goals scored by everyone repping them (the World Cup standings).
export type LeaderboardData = {
	Wins: { LeaderEntry },
	Coins: { LeaderEntry },
	Nations: { LeaderEntry }, -- national teams by total goals (World Cup standings)
	Scorers: { LeaderEntry }, -- individual top scorers THIS WEEK (Golden Boot)
}

-- ===== Persistence (Slice 3) =====

-- The persisted player profile. This IS the ProfileStore template shape, and
-- the same shape is replicated to the client for display.
export type ProfileData = {
	Coins: number,
	Wins: number,
	Losses: number,
	GoalsScored: number,
	SavesMade: number,
	MatchesPlayed: number,
	HasOnboarded: boolean, -- shown the first-time welcome/tutorial yet?
	OwnedCosmetics: { [string]: boolean }, -- cosmetic id -> owned
	Equipped: string, -- currently equipped cosmetic id
	PurchaseIds: { string }, -- processed dev-product receipts (idempotency)
	-- Retention (Phase 2): XP/levels, daily login streak, daily quest progress.
	XP: number,
	LoginStreak: number,
	LastDailyDay: number, -- day index of the last daily reward claimed
	QuestDay: number, -- day index the quest counters belong to
	QuestGoals: number, -- goals scored today (quest progress)
	QuestWins: number, -- matches won today
	QuestSaves: number, -- saves made today
	-- Prediction booth (hub): fixtureKey -> picked nation id, + the day a daily
	-- participation reward was last paid.
	Predictions: { [string]: string },
	PredictionRewardDay: number,
	-- Season Pass ("Road to the Final", June 13 – July 19, 2026).
	SeasonXP: number, -- XP accrued toward the pass (separate from level XP)
	SeasonTierGranted: number, -- highest tier whose free (+ premium) rewards have been granted
	HasPremiumPass: boolean, -- owns the premium upgrade gamepass
	OwnedTitles: { [string]: boolean }, -- title IDs unlocked via the pass
	EquippedTitle: string, -- currently displayed title; "" = none
	XpBoostExpiry: number, -- os.time() when the active 2× XP boost expires; 0 = inactive
	-- Choices runner: legends you've "become" (legend id -> unlocked), and the day index
	-- the once-per-day Choices-run bonus was last paid.
	LegendsUnlocked: { [string]: boolean },
	ChoicesQuestDay: number,
	ChoicesIntroSeen: boolean, -- shown the first-time nudge toward the Choices mode yet?
}

-- server -> client: gamepass-derived perks (not persisted; ownership is live).
export type MonetizationInfo = {
	ownsDoubler: boolean,
}

return {}
