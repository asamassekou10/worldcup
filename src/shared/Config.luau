--!strict
-- Config: single source of truth for every tunable in the game.
-- Designers tune the game HERE, not by hunting through gameplay code.

local Config = {
	-- Admin UserIds (in addition to the place owner / game.CreatorId) allowed to run /result and
	-- other admin chat commands. Add your UserId here if the game is group-owned.
	Admins = {} :: { number },
	-- The goal mouth. Aim is continuous: x in [-1,1], y in [0,1] across this.
	-- Measured from the Football Pitch model: posts 13.22 studs apart (centre-to-centre),
	-- post top at Y=8.131, ground at Y=2.41 → height 5.72. Rounded to 1 d.p.
	Goal = {
		Width = 13.2, -- studs, post to post (measured)
		Height = 5.7, -- studs, ground to crossbar (measured)
		PenaltySpotDistance = 11, -- studs in front of the goal line
	},

	-- Pitch geometry. HalfWidth measured from the Football Pitch turf surface:
	-- turf Part.Size.X = 143.92 studs → half = 71.96 ≈ 72.
	Pitch = {
		HalfWidth = 72, -- studs from pitch centerline to touchline (measured)
	},

	-- Skill shooting. The shooter places an aim point + power; the keeper places
	-- a dive point. The duel: aim far from the keeper, with enough power to beat
	-- their reach -- but too much power sprays the shot wide.
	-- Stud-based params (BaseReach, ReachPerPower, CurveBeat) are scaled to the
	-- real goal half-width (6.6 studs) so game feel is preserved.
	Skill = {
		SweetSpotPower = 0.55, -- power past here starts to spread the shot
		BaseSpread = 0.05, -- always a little inaccuracy (in goal-x/y units)
		SpreadPerOverPower = 0.8, -- extra spread per unit of power over the sweet spot
		BaseReach = 3.8, -- keeper save radius (studs) against a soft shot
		ReachPerPower = 2.0, -- how much a hard shot shrinks the keeper's reach
		-- Curve/bend: drag the ball around the keeper. A full curve bends the
		-- endpoint sideways, makes the swerve harder to read (less keeper reach),
		-- but costs accuracy (extra spread) -- so it's a risk/reward.
		CurveBend = 0.32, -- endpoint shift (goal-x units) at full curve
		CurveSpread = 0.06, -- extra spread per unit of |curve|
		CurveBeat = 0.8, -- studs of keeper reach a full swerve removes
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
		CoinDoublerGamepassId = 1880980469, -- gamepass: 2x coin payouts, forever
		CoinMultiplier = 2, -- payout multiplier the gamepass grants
		SeasonPassId = 1879918823, -- gamepass: "Road to the Final" premium pass (399 R$)
		-- Developer products (buy coins with Robux). productId -> coins.
		CoinPacks = {
			{ productId = 3605107192, coins = 500, label = "Handful of Coins" },
			{ productId = 3605107286, coins = 1500, label = "Bag of Coins" },
			{ productId = 3605107341, coins = 5000, label = "Chest of Coins" },
		},
	},

	-- Choices-runner perks (0 = dormant until you create the gamepass on the dashboard and
	-- paste its id here; the perk board shows "Coming soon" until then). All GAMEPASSES.
	ParkourBoosts = {
		SpeedPassId = 1888846329, -- run faster on the course
		BoostWalkSpeed = 28, -- WalkSpeed while the pass is owned (default ~16/22)
		PointsDoublerPassId = 1887280406, -- 2x run points
		PointsMultiplier = 2,
		SkipProductId = 0, -- (legacy) dev product, unused by the Choices runner
		SkipTokensPerPurchase = 3,
		SneakPeekPassId = 1888132330, -- see the global vote % BEFORE you pick a door
		TrailPassId = 1888600314, -- a glowing trail follows you down the course
	},

	-- Treadmill "Training Grounds": stand on a treadmill in the plaza to earn coins + XP
	-- per tick (server-authoritative). Monetized by a 2x GAMEPASS + an Energy Drink DEV
	-- PRODUCT (repeatable temporary boost). 0 = dormant until ids are set on the dashboard.
	Treadmill = {
		TwoxPassId = 1886854461, -- gamepass: 2x training earnings, forever
		EnergyProductId = 3606145253, -- DEV PRODUCT (consumable): a temporary training boost
		CoinsPerTick = 3, -- base coins granted each tick while training
		XpPerTick = 2, -- base XP each tick
		TickSeconds = 2, -- seconds between training payouts
		EnergyMultiplier = 3, -- training multiplier while an Energy Drink is active
		EnergyDurationSec = 600, -- how long an Energy Drink lasts (10 min)
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
	-- NOTE: the rbxasset:// entries below are Roblox ENGINE BUILT-IN sounds (they ship
	-- with the client, so no marketplace/privacy issues). If any reads silent in-game,
	-- swap it for an uploaded/owned id -- a wrong path just no-ops, it never errors.
	Sounds = {
		Click = "rbxassetid://140207837688369", -- UI button tap
		Whistle = "rbxassetid://9125969478", -- start of a turn
		Kick = "rbxassetid://136922152322648", -- ball struck
		Goal = "rbxassetid://92000304240756", -- crowd cheer on a goal
		Horn = "rbxassetid://114917410847960", -- air horn on a goal
		Save = "rbxassetid://126031531550007", -- keeper save
		-- Two variants -- one is picked at random each miss for variety.
		Miss = "rbxassetid://171370547 rbxassetid://138503230526760", -- shot off target
		MissTooMuch = "rbxassetid://92771529699990", -- played when a player keeps spraying it
		Purchase = "rbxassetid://134952684776633", -- shop/store success
		CrowdRoar = "rbxassetid://1423619896", -- goal-roar one-shot (layers over the loop)
		CrowdGroan = "rbxassetid://122289334695786", -- miss-groan one-shot (kept quiet in Sound.luau)
		StepUp = "rbxassetid://122392468821849", -- tension tick as the kicker steps up
		WinFanfare = "rbxassetid://9042409698", -- victory fanfare on the match-over screen
		Challenge = "rbxassetid://131064426524229", -- taunt when someone challenges you
		-- Choices runner audio.
		DoorWhoosh = "rbxassetid://138890894929151", -- run through a door
		LegendChime = "rbxassetid://81708171932157", -- unlock a new legend
		AnswerCorrect = "rbxassetid://111398542696382", -- right World Cup answer
		AnswerWrong = "rbxassetid://139316231273276", -- wrong World Cup answer
	},

	-- Looping music for the Choices runner (separate from the lobby/stadium audio).
	ChoicesMusic = "rbxassetid://122254026891223",

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
		Kick = "rbxassetid://106036093120322", -- shooter's striking animation (R6, owned)
		Dive = "rbxassetid://8459456709", -- keeper dive (falls back to the scripted dive if it won't load)
	},

	-- Mesh models loaded at runtime (InsertService). 0 = use the built fallback.
	-- Swapped in for the blocky placeholders; each degrades gracefully if it can't
	-- load (Studio without API access, or a private asset).
	Models = {
		Crowd = 0, -- 0 = built blocky crowd (mesh crowds are too heavy to tile a whole stadium)
		Ball = 2599835870, -- soccer ball
		Goal = 0, -- 0 = built posts (mesh 115801784908809 is near-square 17x19x21,
		-- so uniform-scaling to height 5.7 shrinks it to ~5 studs wide -- targets,
		-- laid out for a 13.2-wide goal, then float outside/above it). Built posts
		-- match the goal + target frame exactly, so targets land inside the mouth.
		StandShop = 136506680738607, -- store stand -> SHOP
		StandStore = 12133418608, -- sell stand -> STORE
		StandRanks = 14232203404, -- food stand -> RANKS
		StandDeco = 6863381075, -- ice cream stand (decoration)
		TriviaKiosk = 108305218282536, -- "Quiz Game Show" set for the trivia duel
		PredictKiosk = 91192934622951, -- "Referee" morph manning the predictions booth
		Trophy = 96699151437671, -- real World Cup trophy for the photo booth
		-- RESERVED, not currently placed: this asset ships its own scripts that spawn
		-- projectile fireballs (they fly around and kill players), so it can't be used
		-- as a static prop. Kept for a future "Fireball Escape" mode -- see memory.
		FlamingBall = 15264872392,
		-- Trivia-Gauntlet skyboxes (applied CLIENT-SIDE for players in the course only,
		-- so the stadium sky is unaffected). Loaded server-side into ReplicatedStorage.
		ScarySky = 136055162054954, -- "Scary red sky" real skybox
		FireSky = 6900508449, -- "Fire Sky"
		-- Gauntlet obstacle props (placed as visuals; we re-implement the function so no
		-- untrusted free-model scripts run on the server).
		JumpPad = 8614467015, -- "Futuristic Jump Pad" -> jump-boost zone
		GravityCoil = 88996256597557, -- "Gravity Coil Giver" -> jump-boost zone
		Trusses = 108857271695919, -- "Obby Trusses" -> decor beside a climbable TrussPart wall
		-- "Choices" runner scenery (the Would-You-Rather road). All Models.
		GauntletField = 722192081, -- "GFL Field" -> a stadium backdrop beside the road (no scripts)
		GauntletFence = 1219296760, -- roadside fence, tiled along both edges (no scripts)
		GauntletTrees = 91121812260912, -- "Forest Pack" -> scattered roadside trees (scripts stripped)
		-- Choices-runner dressing (placed as decor; scripts stripped where present).
		ChoicesGrandstand = 135051340897927, -- "Race Grand Stand" -> tiled sections line the course
		ChoicesRaceFence = 14044563045, -- "Race Track Fence" -> tiled down both road edges
		ChoicesBillboard = 11829238764, -- "My billboard" -> stadium ad boards on the perimeter
		ChoicesGrassMaterial = 11568784322, -- a "Grass" MaterialVariant applied to the ground
		ChoicesStartArch = 104095483871265, -- "GALICIA SALIDA RALLY" start gantry over the runway
		ChoicesRoadTexture = 722192081, -- tiled onto the runway floor (Texture on the Top face)
		ChoicesEndArch = 124133513894885, -- archway gate at the trophy finish
		ChoicesConfetti = 89170077453589, -- a confetti ParticleEmitter (used at the finish)
		ChoicesCoin = 2683656699, -- collectible coin model placed between gates
		ChoicesFlagA = 117871245349165, -- waving flags (decor along the course)
		ChoicesFlagB = 16152776816, -- tall flag banners (decor)
		ChoicesFloodlight = 112866180058428, -- stadium floodlight tower (decor)
		-- Teleportation-plaza models (the hub portal area).
		ChoicesPortalPack = 104005814158885, -- "portal pack" -> extract the Portal1 frame mesh
		ChoicesPedestal = 6677469237, -- "Statue Stand" -> a stand per perk (wide/low base)
		ChoicesEntranceGate = 111026346108622, -- "Medieval Arch Gate" -> frames the portal
		ChoicesRope = 90864020162410, -- "VIP Rope Barrier" -> lines the red carpet
		-- "Warm-Up Zone" decor beside the portal plaza.
		ChoicesTreadmillA = 14492354508, -- gym treadmill
		ChoicesTreadmillB = 83162145747402, -- gym machine ("maquina")
		ChoicesWormhole = 410992655, -- sci-fi "Wormhole" accent (⚠️ off-theme, easy to drop)
		-- Training-Zone props (the gym dressing around the treadmills).
		GymVending = 5958066055, -- vending machine -> the Energy Drink stand
		GymDumbbell = 15275879602, -- dumbbell rack
		GymBench = 109734131044193, -- bench press
		GymWaterCooler = 468240417, -- water cooler
		GymMat = 723401960, -- floor mat
		-- Effect-system assets (Would-You-Rather door effects).
		EffectRain = 4999026866, -- "Realistic Rain" -> the rain-weather particles
		EffectLavaSky = 119978113345073, -- "Lava Skybox" -> the per-player HEAT sky
		AuraRed = 12010147091, -- red particle aura -> the "fire" aura
		AuraThunder = 9986036815, -- thunder particle aura -> the "thunder" aura
		MascotCostume = 9203742993, -- "chalk bot" mascot -> a welded costume that hides your body
		-- (deferred: run/jump anim packs 136548520660837 / 113442961065145 are raw
		-- KeyframeSequences -- no published AnimationId -> can't be played at runtime as-is.)
	},

	-- Milestone badges (Phase 5 discovery). Create each badge in the Creator
	-- Dashboard and paste its id here; 0 = not configured (simply not awarded, so
	-- this is safe to ship before the badges exist). Badges show on player
	-- profiles -> social proof + a reason to return.
	Badges = {
		FirstGoal = 1068025231936397, -- "First Goal!" -> score your first goal
		FirstWin = 1329407161724665, -- "Champion" -> win your first match
		HatTrick = 548242867127741, -- "Hat-Trick Hero" -> 3+ goals in a single match
		Level5 = 557114351104718, -- "Rising Star" -> reach level 5
		Level10 = 554183029913837, -- "Pro Striker" -> reach level 10
		Streak3 = 0, -- 3-day login streak (create tomorrow)
		ChoicesFirstRun = 0, -- finish your first Choices run (create tomorrow)
		ChoicesCollector = 0, -- collect 10 legends in the Choices runner (create tomorrow)
		ChoicesAllLegends = 0, -- collect every legend (create tomorrow)
	},

	-- Custom UI icons (uploaded PNGs). "" = fall back to the emoji. Wire new ones here in one place.
	Icons = {
		Coin = "rbxassetid://131687502415517",
		Level = "rbxassetid://105574866507867",
		CardPack = "rbxassetid://121616034306658",
		-- MENU tiles
		PlayModes = "rbxassetid://80101525689020",
		Shop = "rbxassetid://82014163111782",
		Ranks = "rbxassetid://71511453609012",
		Store = "rbxassetid://131061543515245",
		OneVOne = "rbxassetid://116958908789334",
		Club = "rbxassetid://103397255714261",
		Cards = "rbxassetid://76036891510793",
		Deals = "rbxassetid://89021322067133",
		Predict = "rbxassetid://85029747925906",
		Tournament = "rbxassetid://84609144818102",
		Trade = "rbxassetid://94316580933281",
		-- Decorative art (stickers / logos) for world decor + card faces.
		WorldCupLogo = "rbxassetid://73046896092396",
		StickerMessiTrophy = "rbxassetid://110731255568058",
		StickerMessi = "rbxassetid://134542975399832",
		StickerRonaldo = "rbxassetid://139831650782838",
		StickerMbappe = "rbxassetid://103771673024643",
		StickerNeymar = "rbxassetid://115954461509878",
	},
}

return Config
