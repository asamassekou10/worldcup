--!strict
-- Config: single source of truth for every tunable in the game.
-- Designers tune the game HERE, not by hunting through gameplay code.

local Config = {
	-- The goal mouth. Aim is continuous: x in [-1,1], y in [0,1] across this.
	Goal = {
		Width = 21, -- studs, post to post
		Height = 8, -- studs, ground to crossbar
		PenaltySpotDistance = 11, -- studs in front of the goal line
	},

	-- Skill shooting. The shooter places an aim point + power; the keeper places
	-- a dive point. The duel: aim far from the keeper, with enough power to beat
	-- their reach -- but too much power sprays the shot wide.
	Skill = {
		SweetSpotPower = 0.55, -- power past here starts to spread the shot
		BaseSpread = 0.05, -- always a little inaccuracy (in goal-x/y units)
		SpreadPerOverPower = 0.8, -- extra spread per unit of power over the sweet spot
		BaseReach = 6, -- keeper save radius (studs) against a soft shot
		ReachPerPower = 3.2, -- how much a hard shot shrinks the keeper's reach
		-- Curve/bend: drag the ball around the keeper. A full curve bends the
		-- endpoint sideways, makes the swerve harder to read (less keeper reach),
		-- but costs accuracy (extra spread) -- so it's a risk/reward.
		CurveBend = 0.32, -- endpoint shift (goal-x units) at full curve
		CurveSpread = 0.06, -- extra spread per unit of |curve|
		CurveBeat = 1.3, -- studs of keeper reach a full swerve removes
	},

	-- Coin rewards (Slice 3 economy). Match payout = base for the result +
	-- per-goal + per-save, so even a loss earns something for effort.
	Rewards = {
		Goal = 10, -- per goal scored
		Save = 5, -- per save made
		Win = 100, -- bonus for winning the match
		Loss = 25, -- consolation for losing
	},

	-- Monetization (Slice 5). Replace the 0 placeholders with real asset IDs from
	-- the Creator Dashboard. While an id is 0, the store shows a "not configured"
	-- toast and grants nothing -- so the code is safe to ship before assets exist.
	Monetization = {
		CoinDoublerGamepassId = 0, -- gamepass: 2x coin payouts, forever
		CoinMultiplier = 2, -- payout multiplier the gamepass grants
		-- Developer products (buy coins with Robux). productId -> coins.
		CoinPacks = {
			{ productId = 0, coins = 500, label = "Handful of Coins" },
			{ productId = 0, coins = 1500, label = "Bag of Coins" },
			{ productId = 0, coins = 5000, label = "Chest of Coins" },
		},
	},

	-- Catalog asset IDs to load into the showcase (0 = skip). These are loaded
	-- with InsertService:LoadAsset and auto-fitted; positions are tuned in
	-- AssetService. Loading is best-effort -- failures fall back gracefully.
	Assets = {
		StadiumId = 117499034066262,
		BallId = 128643658488494,
		TrophyId = 96699151437671,
		PlayerId = 106766623441137,
	},

	-- Sound effect asset IDs (Slice 5 polish). Replace "rbxassetid://0" with real
	-- uploaded sound IDs; any left as the placeholder are simply not played, so
	-- the hooks are safe to ship before the audio exists.
	Sounds = {
		Click = "rbxassetid://0", -- UI button tap
		Whistle = "rbxassetid://9125969478", -- start of a turn
		Kick = "rbxassetid://136922152322648", -- ball struck
		Goal = "rbxassetid://92000304240756", -- crowd cheer on a goal
		Horn = "rbxassetid://114917410847960", -- air horn on a goal
		Save = "rbxassetid://0", -- keeper save
		Miss = "rbxassetid://0", -- shot off target
		Purchase = "rbxassetid://0", -- shop/store success
	},

	-- Looping audio: stadium ambience (always) + lobby/entrance music.
	Audio = {
		Crowd = "rbxassetid://1847279315", -- stadium ambience (loops, quiet)
		LobbyMusic = "rbxassetid://9043193236", -- entrance song (lobby only)
	},

	-- In-match emotes/taunts (Phase 3 social). The client renders a bar of these;
	-- the server validates against this exact list before broadcasting.
	Emotes = { "👏", "🔥", "😎", "🧤", "😂", "⚽" },

	-- Character animations (uploaded Roblox animation asset ids; "" = none).
	Animations = {
		-- Custom anims only play if uploaded by the GAME's owner/group; toolbox ids
		-- fail to load (spamming errors), so we ship with none and rely on the
		-- scripted lunge/dive. Re-add your OWN uploaded ids here to enable them.
		Kick = "", -- shooter's striking animation
		Dive = "", -- keeper dive
	},

	-- Mesh models loaded at runtime (InsertService). 0 = use the built fallback.
	-- Swapped in for the blocky placeholders; each degrades gracefully if it can't
	-- load (Studio without API access, or a private asset).
	Models = {
		Crowd = 0, -- 0 = built blocky crowd (mesh crowds are too heavy to tile a whole stadium)
		Ball = 2599835870, -- soccer ball
		Goal = 115801784908809, -- goal frame + net
		StandShop = 136506680738607, -- store stand -> SHOP
		StandStore = 12133418608, -- sell stand -> STORE
		StandRanks = 14232203404, -- food stand -> RANKS
		StandDeco = 6863381075, -- ice cream stand (decoration)
	},

	-- Milestone badges (Phase 5 discovery). Create each badge in the Creator
	-- Dashboard and paste its id here; 0 = not configured (simply not awarded, so
	-- this is safe to ship before the badges exist). Badges show on player
	-- profiles -> social proof + a reason to return.
	Badges = {
		FirstGoal = 0, -- score your first goal
		FirstWin = 0, -- win your first match
		HatTrick = 0, -- 3+ goals in a single match
		Level5 = 0, -- reach level 5
		Level10 = 0, -- reach level 10
		Streak3 = 0, -- 3-day login streak
	},
}

return Config
