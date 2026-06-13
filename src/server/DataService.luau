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
}

-- Systems that need a player's profile (e.g. cosmetics applying the equipped
-- flag) register here; we fire them once the profile is loaded and replicated.
local loadedCallbacks: { (Player) -> () } = {}

-- Bump the suffix to start everyone fresh on a breaking schema change.
local PlayerStore = ProfileStore.New("PlayerData_v1", PROFILE_TEMPLATE)

-- ProfileStore's typings aren't exported here; `any` keeps this module clean
-- while DataService.get() still returns the strongly-typed Data snapshot.
local profiles: { [Player]: any } = {}

local function pushToClient(player: Player)
	local profile = profiles[player]
	if profile then
		Net.getEvent(Net.Events.ProfileUpdate):FireClient(player, profile.Data)
	end
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
	end

	pushToClient(player)
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

	-- XP for the match (doubled on bonus weekends; level-up notified once below).
	local beforeLevel = Progression.levelFromXp(data.XP)
	local matchXp = goals * Progression.XpPerGoal
		+ saves * Progression.XpPerSave
		+ (if won then Progression.XpPerWin else Progression.XpPerLoss)
	if Progression.isBonusWeekend() then
		matchXp *= Progression.WeekendXpMultiplier
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

	updateLeaderstats(player)
	pushToClient(player)
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
