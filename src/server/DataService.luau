--!strict
-- DataService: persistent player data via ProfileStore (session-locked, the
-- maintained successor to ProfileService). Loads a profile on join, releases
-- it on leave, mirrors key stats into leaderstats (player-list social proof),
-- and replicates the full snapshot to the owning client for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Progression = require(Shared:WaitForChild("Progression"))
local WorldCup = require(Shared:WaitForChild("WorldCup"))
local SeasonPass = require(Shared:WaitForChild("SeasonPass"))
local CardBank = require(Shared:WaitForChild("CardBank"))
local LiveEvents = require(Shared:WaitForChild("LiveEvents"))
local DailyDeals = require(Shared:WaitForChild("DailyDeals"))
local Tournament = require(Shared:WaitForChild("Tournament"))
local DailyObjective = require(Shared:WaitForChild("DailyObjective"))

local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local BadgeService = require(script.Parent:WaitForChild("BadgeService"))

local DataService = {}

local PROFILE_TEMPLATE: Types.ProfileData = {
	Coins = 0,
	Wins = 0,
	Losses = 0,
	GoalsScored = 0,
	SavesMade = 0,
	MatchesPlayed = 0,
	HasOnboarded = false,
	OwnedCosmetics = {},
	Equipped = Catalog.DefaultEquipped,
	PurchaseIds = {},
	XP = 0,
	LoginStreak = 0,
	LastDailyDay = 0,
	QuestDay = 0,
	QuestGoals = 0,
	QuestWins = 0,
	QuestSaves = 0,
	Predictions = {},
	PredictionRewardDay = 0,
	SeasonXP = 0,
	SeasonTierGranted = 0,
	HasPremiumPass = false,
	OwnedTitles = {},
	EquippedTitle = "",
	XpBoostExpiry = 0,
	LegendsUnlocked = {},
	ChoicesAurasOwned = {}, -- earned equippable auras (set of keys: sparkle/wind/ice/fire/thunder)
	ChoicesQuestDay = 0,
	ChoicesPackDay = 0,
	SquadBonusDay = 0, -- once-per-day "played with a friend" reward
	ChoicesIntroSeen = false,
	ClubLevel = 1, -- idle "Football Club": passive coin earner, upgraded to earn faster
	ClubLastClaim = 0, -- os.time() of the last claim/upgrade (0 = uninitialised)
	CardsOwned = {}, -- collectible cards: id -> count
	CardPacks = 0, -- unopened card packs
	CardSetClaimed = false, -- one-time "completed the set" bonus paid?
	StoreDay = 0, -- day index the StoreBought set belongs to (resets the list each UTC day)
	StoreBought = {}, -- set of daily-deal ids already purchased today
	TournPoints = 0, -- weekly tournament points (= XP earned this week)
	TournWeek = 0, -- week index TournPoints belongs to (resets the total each week)
	TournClaimedWeek = 0, -- last week index whose rank prize was paid (anti double-pay)
	DailyObjDay = 0, -- day index the daily-objective progress belongs to (resets each UTC day)
	DailyObjProgress = 0, -- progress toward today's single big objective
	DailyObjDone = false, -- today's objective reward already paid?
	RookieDone = {}, -- FTUE: set of completed rookie-reward step keys (gift/pack/mode)
}

-- Systems that need a player's profile (e.g. cosmetics applying the equipped
-- flag) register here; we fire them once the profile is loaded and replicated.
local loadedCallbacks: { (Player) -> () } = {}

-- Bump the suffix to start everyone fresh on a breaking schema change.
local PlayerStore = ProfileStore.New("PlayerData_v1", PROFILE_TEMPLATE)

-- ProfileStore's typings aren't exported here; `any` keeps this module clean
-- while DataService.get() still returns the strongly-typed Data snapshot.
local profiles: { [Player]: any } = {}

-- Ice-cream cart "Free Treat" cooldown (in-memory; treats are a light, repeatable
-- freebie, not save-critical, so a session cooldown is enough).
local TREAT_COOLDOWN = 300 -- seconds between scoops
local TREAT_BOOST = 300 -- seconds of 2x XP per scoop
local TREAT_FLAVORS = {
	{ name = "Strawberry", coins = 15 },
	{ name = "Chocolate", coins = 20 },
	{ name = "Vanilla", coins = 12 },
	{ name = "Mint Choc", coins = 18 },
	{ name = "Mango", coins = 25 },
	{ name = "Golden Boot", coins = 40 }, -- rare lucky scoop
}
local nextTreatAt: { [Player]: number } = {}

local function pushToClient(player: Player)
	local profile = profiles[player]
	if profile then
		Net.getEvent(Net.Events.ProfileUpdate):FireClient(player, profile.Data)
	end
end

local function pushSeasonUpdate(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local d = profile.Data
	Net.getEvent(Net.Events.SeasonUpdate):FireClient(player, {
		SeasonXP = d.SeasonXP,
		SeasonTierGranted = d.SeasonTierGranted,
		HasPremiumPass = d.HasPremiumPass,
		EquippedTitle = d.EquippedTitle,
	})
end

-- Apply a single season-pass reward (coins / title / xpboost) in-place.
-- Uses the Net event directly because this runs before the `notify` local is defined.
local function applySeasonReward(player: Player, data: Types.ProfileData, reward: SeasonPass.Reward)
	local function sendNotify(msg: string)
		Net.getEvent(Net.Events.Notify):FireClient(player, { message = msg })
	end
	if reward.kind == "coins" then
		data.Coins += reward.amount or 0
	elseif reward.kind == "title" then
		local id = reward.id
		if id and id ~= "" then
			data.OwnedTitles[id] = true
			if data.EquippedTitle == "" then
				data.EquippedTitle = id
			end
			sendNotify(string.format("Title unlocked: %s", SeasonPass.TitleLabels[id] or id))
		end
	elseif reward.kind == "xpboost" then
		local duration = reward.amount or 86400
		data.XpBoostExpiry = math.max(data.XpBoostExpiry, os.time()) + duration
		local hours = math.floor(duration / 3600)
		sendNotify(string.format("%dh 2x XP Boost activated!", hours))
	end
end

-- Grant free (and optionally premium) season-pass tier rewards, then push state.
local function grantSeasonXp(player: Player, data: Types.ProfileData, amount: number)
	if not SeasonPass.isActive() or amount <= 0 then
		return
	end
	data.SeasonXP += amount
	local newTier = SeasonPass.tierFromXp(data.SeasonXP)
	local oldTier = data.SeasonTierGranted
	if newTier <= oldTier then
		return
	end
	for t = oldTier + 1, newTier do
		local freeReward = SeasonPass.getReward(t, "free")
		if freeReward then
			applySeasonReward(player, data, freeReward)
		end
		if data.HasPremiumPass then
			local premReward = SeasonPass.getReward(t, "premium")
			if premReward then
				applySeasonReward(player, data, premReward)
			end
		end
	end
	data.SeasonTierGranted = newTier
	Net.getEvent(Net.Events.Notify)
		:FireClient(player, { message = string.format("Season Pass - Tier %d reached!", newTier) })
end

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

-- Weekly tournament: roll the point total over to a fresh week if the week changed, then add `n`
-- points (= XP earned). Called from every XP-granting path so all modes feed the competition.
local function bumpTourn(data: any, n: number)
	local week = Tournament.weekId()
	if data.TournWeek ~= week then
		data.TournWeek = week
		data.TournPoints = 0
	end
	if n > 0 then
		data.TournPoints += n
	end
end

-- Daily objective: roll progress over to a fresh day if the day changed, then -- if `kind` matches
-- today's objective -- add progress and pay the reward the first time it's hit. Returns true if the
-- objective was JUST completed (so the caller can celebrate). `n == 0` just performs the roll.
local function bumpDaily(player: Player, data: any, kind: string, n: number): boolean
	local day = Progression.dayIndex()
	if data.DailyObjDay ~= day then
		data.DailyObjDay = day
		data.DailyObjProgress = 0
		data.DailyObjDone = false
	end
	local obj = DailyObjective.today()
	if n <= 0 or data.DailyObjDone or obj.kind ~= kind then
		return false
	end
	data.DailyObjProgress += n
	local justDone = false
	if data.DailyObjProgress >= obj.target then
		data.DailyObjDone = true
		data.Coins += obj.coins
		data.CardPacks += obj.packs
		justDone = true
		Net.getEvent(Net.Events.Notify):FireClient(player, {
			message = string.format(
				"%s Daily Objective complete! +%d coins +%d pack",
				obj.emoji,
				obj.coins,
				obj.packs
			),
		})
	end
	-- Push the live progress to the banner.
	Net.getEvent(Net.Events.DailyObjectiveState):FireClient(player, {
		label = DailyObjective.text(obj),
		emoji = obj.emoji,
		progress = math.min(data.DailyObjProgress, obj.target),
		target = obj.target,
		done = data.DailyObjDone,
		coins = obj.coins,
		packs = obj.packs,
	})
	return justDone
end

local function updateLeaderstats(player: Player)
	local profile = profiles[player]
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	(stats:FindFirstChild("Wins") :: IntValue).Value = profile.Data.Wins;
	(stats:FindFirstChild("Coins") :: IntValue).Value = profile.Data.Coins
end

local function setupLeaderstats(player: Player, data: Types.ProfileData)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = data.Wins
	wins.Parent = stats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = stats

	stats.Parent = player
end

-- Settle past predictions against WorldCup.Results: pay correct picks, then drop
-- resolved/old entries. Dormant until results are filled in (no live feed).
local function settlePredictions(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.Data
	local today = WorldCup.todayISO()
	local correct = 0
	for key, pick in data.Predictions do
		local date = key:match("^(%d+-%d+-%d+)")
		local winner = WorldCup.resultWinner(key)
		if winner then
			if winner == pick then
				correct += 1
			end
			data.Predictions[key] = nil -- resolved
		elseif date and date < today then
			data.Predictions[key] = nil -- match passed with no result on file; drop it
		end
	end
	if correct > 0 then
		data.Coins += correct * 60
		data.XP += correct * 40
		updateLeaderstats(player)
		notify(
			player,
			string.format("🔮 %d correct prediction(s) — +%d coins!", correct, correct * 60)
		)
	end
end

-- Run once per join: roll the daily quest counters over at a new day, and pay the
-- login-streak reward (streak continues if they played yesterday, else resets).
local function evaluateDaily(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.Data
	local today = Progression.dayIndex()

	if data.QuestDay ~= today then
		data.QuestDay = today
		data.QuestGoals = 0
		data.QuestWins = 0
		data.QuestSaves = 0
	end

	settlePredictions(player) -- pay out any predictions that now have results

	if data.LastDailyDay ~= today then
		data.LoginStreak = if data.LastDailyDay == today - 1 then data.LoginStreak + 1 else 1
		data.LastDailyDay = today
		local reward = Progression.dailyReward(data.LoginStreak)
		data.Coins += reward
		updateLeaderstats(player)
		notify(player, string.format("🎁 Day %d streak — +%d coins!", data.LoginStreak, reward))
		if data.LoginStreak >= 3 then
			BadgeService.streak3(player)
		end
		grantSeasonXp(player, data, SeasonPass.XpPerLogin)
	end

	pushToClient(player)
	pushSeasonUpdate(player)
end

local function onPlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Another server holds the lock, or the DataStore is unreachable.
		player:Kick("Data failed to load. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR association
	profile:Reconcile() -- fill in any keys added to the template since last save

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		nextTreatAt[player] = nil
		player:Kick("Your data session ended. Please rejoin.")
	end)

	if player.Parent == Players then
		profiles[player] = profile
		setupLeaderstats(player, profile.Data)
		evaluateDaily(player) -- daily reset + login-streak reward, then push
		for _, callback in loadedCallbacks do
			task.spawn(callback, player)
		end
	else
		-- Player left during the async load; don't hold the lock.
		profile:EndSession()
	end
end

-- Register a callback fired (with the Player) once their profile is loaded.
function DataService.onProfileLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
end

function DataService.start()
	-- Catch players who joined before this script ran (Studio play-solo).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		nextTreatAt[player] = nil
		local profile = profiles[player]
		if profile then
			profile:EndSession()
		end
	end)
end

-- Read-only snapshot for other systems.
function DataService.get(player: Player): Types.ProfileData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Apply the outcome of a finished match: update stats, pay out coins, mirror to
-- leaderstats, and replicate to the client. The single place match -> economy.
function DataService.applyMatchResult(
	player: Player,
	won: boolean,
	goals: number,
	saves: number,
	multiplier: number?
)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end

	local data = profile.Data
	local firstEverGoal = data.GoalsScored == 0 and goals > 0
	data.MatchesPlayed += 1
	data.GoalsScored += goals
	data.SavesMade += saves

	local payout = goals * Config.Rewards.Goal + saves * Config.Rewards.Save
	if won then
		data.Wins += 1
		payout += Config.Rewards.Win
		data.CardPacks += 1 -- a card pack for winning a match
	else
		data.Losses += 1
		payout += Config.Rewards.Loss
	end
	data.Coins += math.floor(payout * (multiplier or 1))

	-- Milestone badges (profile social proof).
	if firstEverGoal then
		BadgeService.firstGoal(player)
	end
	if won and data.Wins == 1 then
		BadgeService.firstWin(player)
	end
	if goals >= 3 then
		BadgeService.hatTrick(player)
	end

	-- XP for the match (doubled on bonus weekends or active XP boost).
	local beforeLevel = Progression.levelFromXp(data.XP)
	local matchXp = goals * Progression.XpPerGoal
		+ saves * Progression.XpPerSave
		+ (if won then Progression.XpPerWin else Progression.XpPerLoss)
	if Progression.isBonusWeekend() then
		matchXp *= Progression.WeekendXpMultiplier
	end
	if data.XpBoostExpiry > os.time() then
		matchXp *= 2
	end
	data.XP += matchXp
	bumpTourn(data, matchXp)
	bumpDaily(player, data, "xp", matchXp)
	bumpDaily(player, data, "goals", goals)

	-- Daily-quest progress: bump each counter, paying out the first time it
	-- crosses its target (counters reset each day in evaluateDaily).
	local function progressQuest(
		current: number,
		add: number,
		quest: Progression.Quest,
		set: (number) -> ()
	)
		if add <= 0 then
			return
		end
		local after = current + add
		set(after)
		if current < quest.target and after >= quest.target then
			data.Coins += quest.coins
			data.XP += quest.xp
			grantSeasonXp(player, data, SeasonPass.XpPerQuest)
			notify(
				player,
				string.format(
					"✅ %s  ·  +%d 💰",
					string.format(quest.label, quest.target),
					quest.coins
				)
			)
		end
	end
	for _, quest in Progression.Quests do
		if quest.stat == "goals" then
			progressQuest(data.QuestGoals, goals, quest, function(v)
				data.QuestGoals = v
			end)
		elseif quest.stat == "wins" then
			progressQuest(data.QuestWins, if won then 1 else 0, quest, function(v)
				data.QuestWins = v
			end)
		elseif quest.stat == "saves" then
			progressQuest(data.QuestSaves, saves, quest, function(v)
				data.QuestSaves = v
			end)
		end
	end

	local afterLevel = Progression.levelFromXp(data.XP)
	if afterLevel > beforeLevel then
		notify(player, string.format("⬆️ Level %d!", afterLevel))
		BadgeService.level(player, afterLevel)
	end

	-- Season pass: grant XP for the match result.
	local seasonMatchXp = goals * SeasonPass.XpPerGoal
		+ saves * SeasonPass.XpPerSave
		+ (if won then SeasonPass.XpPerWin else SeasonPass.XpPerLoss)
	grantSeasonXp(player, data, seasonMatchXp)

	updateLeaderstats(player)
	pushToClient(player)
	pushSeasonUpdate(player)
end

-- Record a match prediction (fixtureKey -> picked nation). Pays a one-time daily
-- participation reward for engaging with the booth.
function DataService.recordPrediction(player: Player, key: string, pick: string)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	if typeof(key) ~= "string" or typeof(pick) ~= "string" or pick == "" then
		return
	end
	local data = profile.Data
	data.Predictions[key] = pick

	local today = Progression.dayIndex()
	if data.PredictionRewardDay ~= today then
		data.PredictionRewardDay = today
		data.Coins += 20 -- daily "analyst" bonus for making a pick
		updateLeaderstats(player)
		notify(player, "🔮 Prediction locked in — +20 coins!")
	end
	pushToClient(player)
end

-- Activate the premium season pass for a player: grant all retroactive premium
-- rewards for tiers they've already unlocked, then push the updated state.
function DataService.activatePremiumPass(player: Player)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	local data = profile.Data
	if data.HasPremiumPass then
		return -- idempotent
	end
	data.HasPremiumPass = true
	-- Retroactively grant premium rewards for any tiers already reached.
	for t = 1, data.SeasonTierGranted do
		local premReward = SeasonPass.getReward(t, "premium")
		if premReward then
			applySeasonReward(player, data, premReward)
		end
	end
	updateLeaderstats(player)
	pushToClient(player)
	pushSeasonUpdate(player)
end

-- Mark the first-time welcome/tutorial as seen so it never shows again.
function DataService.markOnboarded(player: Player)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	if profile.Data.HasOnboarded then
		return -- idempotent
	end
	profile.Data.HasOnboarded = true
	profile.Data.Coins += 100 -- welcome gift so the first session feels rewarding
	updateLeaderstats(player)
	pushToClient(player)
	Net.getEvent(Net.Events.Notify):FireClient(player, {
		message = "👋 Welcome to Penalty Kings! +100 coins to get you started",
	})
end

-- Ice-cream cart: hand out a free scoop -- a few coins + a short 2x XP boost --
-- on a per-player cooldown. A fun, repeatable freebie that pulls players to the
-- plaza between matches (distinct from the automatic daily login-streak reward).
function DataService.claimTreat(player: Player)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	local now = os.time()
	local ready = nextTreatAt[player] or 0
	if now < ready then
		local wait = ready - now
		notify(player, string.format("🍦 Still melting… come back in %ds", wait))
		return
	end
	nextTreatAt[player] = now + TREAT_COOLDOWN

	local flavor = TREAT_FLAVORS[math.random(#TREAT_FLAVORS)]
	local data = profile.Data
	data.Coins += flavor.coins
	data.XpBoostExpiry = math.max(data.XpBoostExpiry, now) + TREAT_BOOST
	updateLeaderstats(player)
	pushToClient(player)
	notify(
		player,
		string.format(
			"🍦 %s scoop! +%d coins · 2x XP for %dm",
			flavor.name,
			flavor.coins,
			TREAT_BOOST // 60
		)
	)
end

-- Grant a flat coin + XP reward (hub activities like the warmup range). Notifies
-- on level-up + awards level badges, mirrors to leaderstats, replicates.
function DataService.grantReward(player: Player, coins: number, xp: number)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	local data = profile.Data
	local beforeLevel = Progression.levelFromXp(data.XP)
	-- live-event multipliers (Double Coins / Double XP / weekend) apply to all earned rewards
	local ev = LiveEvents.current()
	local xpMult = ev.xpMult
	if data.XpBoostExpiry > os.time() then
		xpMult *= 2 -- active 2× XP boost (e.g. from a Daily Deal / treat)
	end
	data.Coins += math.floor(math.max(coins, 0) * ev.coinMult)
	local xpGain = math.floor(math.max(xp, 0) * xpMult)
	data.XP += xpGain
	bumpTourn(data, xpGain)
	bumpDaily(player, data, "xp", xpGain)
	local afterLevel = Progression.levelFromXp(data.XP)
	if afterLevel > beforeLevel then
		notify(player, string.format("⬆️ Level %d!", afterLevel))
		BadgeService.level(player, afterLevel)
	end
	updateLeaderstats(player)
	pushToClient(player)
end

-- Choices runner: unlock a "legend" you became by walking through its door. Returns
-- true only the FIRST time (so the run can celebrate a fresh unlock).
function DataService.unlockLegend(player: Player, legendId: string): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	local data = profile.Data
	if data.LegendsUnlocked[legendId] then
		return false
	end
	data.LegendsUnlocked[legendId] = true
	pushToClient(player)
	return true
end

-- Choices runner: grant an earned cosmetic aura. Returns true only the FIRST time (so the
-- caller can celebrate a fresh unlock).
function DataService.unlockChoicesAura(player: Player, key: string): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	local owned = profile.Data.ChoicesAurasOwned
	if owned[key] then
		return false
	end
	owned[key] = true
	pushToClient(player)
	return true
end

-- ===== Idle "Football Club": a passive coin earner that accrues even while offline (the daily
-- return hook), capped so it's "check in daily" not "afk forever", and upgraded to earn faster. =====
local CLUB_BASE_RATE = 0.07 -- coins/sec at level 1
local CLUB_OFFLINE_CAP = 8 * 3600 -- accrual caps at 8 hours

local function clubPending(data: any): number
	if data.ClubLastClaim <= 0 then
		return 0
	end
	local elapsed = math.clamp(os.time() - data.ClubLastClaim, 0, CLUB_OFFLINE_CAP)
	return math.floor(elapsed * CLUB_BASE_RATE * data.ClubLevel)
end

local function clubUpgradeCost(level: number): number
	return math.floor(1200 * level ^ 1.5)
end

-- A snapshot for the client club panel.
function DataService.clubInfo(player: Player): { [string]: number }?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	local data = profile.Data
	if data.ClubLastClaim <= 0 then
		data.ClubLastClaim = os.time() -- start accruing from first sight (no giant first claim)
	end
	return {
		level = data.ClubLevel,
		ratePerHr = math.floor(CLUB_BASE_RATE * data.ClubLevel * 3600),
		pending = clubPending(data),
		cap = math.floor(CLUB_BASE_RATE * data.ClubLevel * CLUB_OFFLINE_CAP),
		upgradeCost = clubUpgradeCost(data.ClubLevel),
		coins = data.Coins,
	}
end

-- Bank the pending coins; resets the accrual clock. Returns the amount claimed.
function DataService.clubClaim(player: Player): number
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return 0
	end
	local data = profile.Data
	local pending = clubPending(data)
	data.ClubLastClaim = os.time()
	if pending > 0 then
		data.Coins += pending
		updateLeaderstats(player)
		pushToClient(player)
	end
	return pending
end

-- Upgrade the club (banks pending first so the rate change is clean). Returns success + message.
function DataService.clubUpgrade(player: Player): (boolean, string)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false, "No profile."
	end
	local data = profile.Data
	local pending = clubPending(data)
	if pending > 0 then
		data.Coins += pending
	end
	data.ClubLastClaim = os.time()
	local cost = clubUpgradeCost(data.ClubLevel)
	if data.Coins < cost then
		updateLeaderstats(player)
		pushToClient(player)
		return false, string.format("Need %d coins to upgrade your club.", cost)
	end
	data.Coins -= cost
	data.ClubLevel += 1
	updateLeaderstats(player)
	pushToClient(player)
	return true, string.format("🏟️ Club upgraded to Level %d!", data.ClubLevel)
end

-- ===== Collectible cards: earn packs from playing, open them for cards, complete the set. =====
local CARDS_PER_PACK = 3
local CARD_SET_REWARD = 5000 -- one-time payout for completing the whole collection

-- Grant `n` unopened packs (from finishing runs / winning matches).
function DataService.grantPack(player: Player, n: number)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	profile.Data.CardPacks += n + (n > 0 and LiveEvents.current().packBonus or 0) -- Pack Frenzy bonus
	pushToClient(player)
end

-- Daily Deal store: roll the StoreBought set over to today if the day changed (so each day's
-- line-up starts fresh), then return the snapshot the client store panel needs.
local function refreshStore(data: any)
	local today = Progression.dayIndex()
	if data.StoreDay ~= today then
		data.StoreDay = today
		data.StoreBought = {}
	end
end

function DataService.storeInfo(player: Player): { [string]: any }?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	local data = profile.Data
	refreshStore(data)
	return {
		coins = data.Coins,
		bought = data.StoreBought,
		resetsAt = DailyDeals.resetsAt(),
		deals = DailyDeals.dealsFor(),
	}
end

-- Buy one of today's featured deals. Validates the deal is featured today, isn't already bought,
-- and the player can afford it, then applies the effect. Returns (ok, message).
function DataService.buyDeal(player: Player, id: string): (boolean, string)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false, "Not ready"
	end
	local data = profile.Data
	refreshStore(data)
	local deal = DailyDeals.todaysDeal(id)
	if not deal then
		return false, "That deal isn't available today"
	end
	if data.StoreBought[id] then
		return false, "Already claimed today"
	end
	if data.Coins < deal.price then
		return false, "Not enough coins"
	end
	data.Coins -= deal.price
	data.StoreBought[id] = true
	if deal.kind == "pack" then
		DataService.grantPack(player, deal.amount) -- pushes to client
	elseif deal.kind == "boost" then
		data.XpBoostExpiry = math.max(data.XpBoostExpiry, os.time()) + deal.amount
	end
	updateLeaderstats(player)
	pushToClient(player)
	return true, string.format("%s %s purchased!", deal.emoji, deal.label)
end

-- Weekly tournament: the player's current point total (rolled to this week). Used by
-- TournamentService to publish them to the week's OrderedDataStore and show their live rank.
function DataService.tournPoints(player: Player): number?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	bumpTourn(profile.Data, 0) -- roll the week over if needed
	pushToClient(player)
	return profile.Data.TournPoints
end

-- Pay a previous week's rank prize exactly once. Gated by TournClaimedWeek (and ProfileStore's
-- session lock), so even across rejoins/servers a prize is never paid twice. Returns true if paid.
function DataService.payTournament(
	player: Player,
	week: number,
	coins: number,
	packs: number
): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	local data = profile.Data
	if data.TournClaimedWeek >= week then
		return false -- already paid for this (or a later) week
	end
	data.TournClaimedWeek = week
	data.Coins += coins
	if packs > 0 then
		data.CardPacks += packs
	end
	updateLeaderstats(player)
	pushToClient(player)
	return true
end

-- Snapshot for the client daily-objective banner (rolls the day over first so progress is correct).
function DataService.dailyObjectiveInfo(player: Player): { [string]: any }?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	bumpDaily(player, profile.Data, "", 0) -- roll the day over if needed
	local obj = DailyObjective.today()
	return {
		label = DailyObjective.text(obj),
		emoji = obj.emoji,
		progress = math.min(profile.Data.DailyObjProgress, obj.target),
		target = obj.target,
		done = profile.Data.DailyObjDone,
		coins = obj.coins,
		packs = obj.packs,
	}
end

-- ===== FTUE "Rookie Rewards": a sub-60s first-session reward path. The gift step is an instant tap;
-- the pack/mode steps complete the first time the player opens a pack / jumps to a mode. Finishing
-- all three marks HasOnboarded and pays a bonus. Each step pays exactly once. =====
local ROOKIE_STEPS = { "gift", "pack", "mode" }
local ROOKIE_REWARDS: { [string]: { coins: number, packs: number, boost: number, msg: string } } = {
	gift = {
		coins = 300,
		packs = 2,
		boost = 1800,
		msg = "🎁 Welcome gift! +300 coins, 2 packs & 2× XP",
	},
	pack = { coins = 150, packs = 0, boost = 0, msg = "🃏 First pack opened! +150 coins" },
	mode = { coins = 150, packs = 0, boost = 0, msg = "🎮 Nice — you found a mode! +150 coins" },
}
local ROOKIE_COMPLETE_BONUS = 250

function DataService.rookieInfo(player: Player): { [string]: any }?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	return { done = profile.Data.RookieDone, complete = profile.Data.HasOnboarded }
end

-- Complete one rookie step. Returns (granted, complete) -- granted only the first time the step is
-- earned; complete is true once all steps are done (HasOnboarded set + bonus paid).
function DataService.claimRookieStep(player: Player, step: string): (boolean, boolean)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false, false
	end
	local data = profile.Data
	if data.HasOnboarded then
		return false, true -- already a veteran; nothing to claim
	end
	local reward = ROOKIE_REWARDS[step]
	if not reward or data.RookieDone[step] then
		return false, false
	end
	data.RookieDone[step] = true
	data.Coins += reward.coins
	if reward.packs > 0 then
		data.CardPacks += reward.packs
	end
	if reward.boost > 0 then
		data.XpBoostExpiry = math.max(data.XpBoostExpiry, os.time()) + reward.boost
	end
	notify(player, reward.msg)

	local allDone = true
	for _, s in ROOKIE_STEPS do
		if not data.RookieDone[s] then
			allDone = false
			break
		end
	end
	if allDone then
		data.HasOnboarded = true
		data.Coins += ROOKIE_COMPLETE_BONUS
		notify(player, string.format("⭐ Rookie complete! +%d bonus coins", ROOKIE_COMPLETE_BONUS))
	end
	updateLeaderstats(player)
	pushToClient(player)
	return true, data.HasOnboarded
end

-- Snapshot for the client card collection panel.
function DataService.cardInfo(player: Player): { [string]: any }?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	local data = profile.Data
	local distinct = 0
	for _ in data.CardsOwned do
		distinct += 1
	end
	return {
		owned = data.CardsOwned,
		packs = data.CardPacks,
		distinct = distinct,
		total = CardBank.count(),
	}
end

-- Re-push the card collection to a client (used after a trade changes ownership). Fires the same
-- CardState event CardService uses, so the client's collection panel stays correct.
function DataService.pushCardState(player: Player)
	local info = DataService.cardInfo(player)
	if info then
		Net.getEvent(Net.Events.CardState):FireClient(player, info)
	end
end

-- How many of card `id` a player currently owns (0 if none / not loaded).
function DataService.cardCount(player: Player, id: string): number
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return 0
	end
	return profile.Data.CardsOwned[id] or 0
end

-- Execute a two-sided card trade ATOMICALLY. Both profiles are session-locked to THIS server, so
-- validating both offers in full and only then mutating (with no yields in between) makes the swap
-- race-free and dupe-proof. `aOffer`/`bOffer` map cardId -> count the respective player gives up.
-- Returns (ok, message). On success both clients get a refreshed CardState.
function DataService.executeTrade(
	a: Player,
	aOffer: { [string]: number },
	b: Player,
	bOffer: { [string]: number }
): (boolean, string)
	local pa, pb = profiles[a], profiles[b]
	if not pa or not pa:IsActive() or not pb or not pb:IsActive() then
		return false, "A player isn't ready"
	end
	local da, db = pa.Data, pb.Data

	-- Validate ownership of EVERY offered card before touching anything.
	local function validate(data: any, offer: { [string]: number }): boolean
		for id, count in offer do
			if type(count) ~= "number" or count < 1 then
				return false
			end
			if not CardBank.byId[id] then
				return false -- unknown card id (tampered client)
			end
			if (data.CardsOwned[id] or 0) < count then
				return false -- doesn't own enough
			end
		end
		return true
	end
	if not validate(da, aOffer) or not validate(db, bOffer) then
		return false, "Offer is no longer valid"
	end

	-- Apply: remove from giver, add to receiver. (Synchronous -> atomic.)
	local function move(from: any, to: any, offer: { [string]: number })
		for id, count in offer do
			local left = (from.CardsOwned[id] or 0) - count
			if left > 0 then
				from.CardsOwned[id] = left
			else
				from.CardsOwned[id] = nil
			end
			to.CardsOwned[id] = (to.CardsOwned[id] or 0) + count
		end
	end
	move(da, db, aOffer)
	move(db, da, bOffer)

	DataService.pushCardState(a)
	DataService.pushCardState(b)
	return true, "Trade complete!"
end

-- Open ONE pack: rolls CARDS_PER_PACK cards, banks them, pays the set-completion bonus once.
-- Returns the rolled card ids + which were NEW (for the reveal), or nil if no packs.
function DataService.openPack(
	player: Player
): { rolled: { string }, newIds: { [string]: boolean } }?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	local data = profile.Data
	if data.CardPacks <= 0 then
		return nil
	end
	data.CardPacks -= 1
	local rolled: { string } = {}
	local newIds: { [string]: boolean } = {}
	for _ = 1, CARDS_PER_PACK do
		local id = CardBank.rollOne()
		if (data.CardsOwned[id] or 0) == 0 then
			newIds[id] = true
		end
		data.CardsOwned[id] = (data.CardsOwned[id] or 0) + 1
		table.insert(rolled, id)
	end
	bumpDaily(player, data, "packs", 1)
	-- one-time "completed the collection" jackpot
	if not data.CardSetClaimed then
		local distinct = 0
		for _ in data.CardsOwned do
			distinct += 1
		end
		if distinct >= CardBank.count() then
			data.CardSetClaimed = true
			data.Coins += CARD_SET_REWARD
			Net.getEvent(Net.Events.Notify):FireClient(player, {
				message = string.format("🃏 COLLECTION COMPLETE! +%d coins!", CARD_SET_REWARD),
			})
		end
	end
	updateLeaderstats(player)
	pushToClient(player)
	return { rolled = rolled, newIds = newIds }
end

-- Social growth: a once-per-day reward for playing in a server with a friend (the "invite a
-- friend" incentive). Returns the coin reward (0 if already claimed today).
function DataService.claimSquadBonus(player: Player): number
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return 0
	end
	local data = profile.Data
	local today = Progression.dayIndex()
	if data.SquadBonusDay == today then
		return 0
	end
	data.SquadBonusDay = today
	local reward = 60
	data.Coins += reward
	updateLeaderstats(player)
	pushToClient(player)
	return reward
end

-- Choices runner: mark the first-time intro nudge as shown. Returns true only the FIRST
-- time (so the nudge fires exactly once, ever).
function DataService.markChoicesIntro(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	if profile.Data.ChoicesIntroSeen then
		return false
	end
	profile.Data.ChoicesIntroSeen = true
	return true
end

-- Choices runner: pay a once-per-day bonus the first time you finish a run that day.
-- Returns the coin reward (0 if already claimed today).
function DataService.claimChoicesDaily(player: Player): number
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return 0
	end
	local data = profile.Data
	local today = Progression.dayIndex()
	if data.ChoicesQuestDay == today then
		return 0
	end
	data.ChoicesQuestDay = today
	local reward = 75
	data.Coins += reward
	data.XP += 25
	updateLeaderstats(player)
	pushToClient(player)
	return reward
end

-- Choices runner: pay a once-per-day bonus the first time you clear ALL of today's featured
-- "Daily 5" dilemmas in a single run. Returns the coin reward (0 if already claimed today).
function DataService.claimChoicesPack(player: Player): number
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return 0
	end
	local data = profile.Data
	local today = Progression.dayIndex()
	if data.ChoicesPackDay == today then
		return 0
	end
	data.ChoicesPackDay = today
	local reward = 150
	data.Coins += reward
	data.XP += 50
	updateLeaderstats(player)
	pushToClient(player)
	return reward
end

-- Atomically spend coins. Returns false (and changes nothing) if the player
-- can't afford it. The only path that removes coins -- keeps the economy honest.
function DataService.trySpend(player: Player, cost: number): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	if profile.Data.Coins < cost then
		return false
	end
	profile.Data.Coins -= cost
	updateLeaderstats(player)
	pushToClient(player)
	return true
end

-- Grant ownership of a cosmetic id.
function DataService.grantCosmetic(player: Player, id: string)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	profile.Data.OwnedCosmetics[id] = true
	pushToClient(player)
end

-- Set the equipped cosmetic id (ownership is validated by the caller).
function DataService.setEquipped(player: Player, id: string)
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	profile.Data.Equipped = id
	pushToClient(player)
end

-- Grant a dev-product purchase exactly once. Records the receipt's PurchaseId in
-- session-locked data, so a retried receipt is recognised and not double-granted.
-- Returns true if the purchase is now (or was already) accounted for.
function DataService.grantPurchase(player: Player, purchaseId: string, coins: number): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false -- not loaded here; let Roblox retry the receipt later
	end

	local data = profile.Data
	if table.find(data.PurchaseIds, purchaseId) then
		return true -- already granted on a previous receipt delivery
	end

	table.insert(data.PurchaseIds, purchaseId)
	if #data.PurchaseIds > 50 then
		table.remove(data.PurchaseIds, 1) -- keep the history bounded
	end
	data.Coins += coins

	updateLeaderstats(player)
	pushToClient(player)
	return true
end

return DataService
