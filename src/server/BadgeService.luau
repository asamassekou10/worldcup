--!strict
-- BadgeService: awards milestone badges (configured in Config.Badges). Badges
-- appear on a player's Roblox profile -- social proof that pulls people back and
-- nudges completion. Every call is pcall'd and an id of 0 is skipped, so this is
-- safe to ship before the badges are created in the Creator Dashboard.

local BadgeService_Roblox = game:GetService("BadgeService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BadgeService = {}

-- Award `badgeId` to `player` if it's configured and they don't already own it.
function BadgeService.tryAward(player: Player, badgeId: number)
	if badgeId <= 0 then
		return -- not configured yet
	end
	task.spawn(function()
		local ok, owned = pcall(function()
			return BadgeService_Roblox:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if ok and owned then
			return
		end
		pcall(function()
			BadgeService_Roblox:AwardBadge(player.UserId, badgeId)
		end)
	end)
end

-- Convenience wrappers keyed off Config.Badges, so callers read clearly.
function BadgeService.firstGoal(player: Player)
	BadgeService.tryAward(player, Config.Badges.FirstGoal)
end
function BadgeService.firstWin(player: Player)
	BadgeService.tryAward(player, Config.Badges.FirstWin)
end
function BadgeService.hatTrick(player: Player)
	BadgeService.tryAward(player, Config.Badges.HatTrick)
end
function BadgeService.streak3(player: Player)
	BadgeService.tryAward(player, Config.Badges.Streak3)
end
-- Choices runner milestones.
function BadgeService.choicesFirstRun(player: Player)
	BadgeService.tryAward(player, Config.Badges.ChoicesFirstRun)
end
-- Legend collection: award the tiers reached given how many of `total` you've collected.
function BadgeService.choicesLegends(player: Player, collected: number, total: number)
	if collected >= total then
		BadgeService.tryAward(player, Config.Badges.ChoicesAllLegends)
	end
	if collected >= 10 then
		BadgeService.tryAward(player, Config.Badges.ChoicesCollector)
	end
end
-- Level milestones: award the ones newly reached this level-up.
function BadgeService.level(player: Player, level: number)
	if level >= 10 then
		BadgeService.tryAward(player, Config.Badges.Level10)
	end
	if level >= 5 then
		BadgeService.tryAward(player, Config.Badges.Level5)
	end
end

return BadgeService
