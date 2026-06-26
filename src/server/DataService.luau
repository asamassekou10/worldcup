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
	data.Coins += math.max(coins, 0)
	data.XP += math.max(xp, 0)
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
