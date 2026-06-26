--!strict
-- ActivityService: powers the in-HUD "PLAY" menu. Each entry resolves a teleport spot for an
-- activity -- by finding its live prompt/part in the world, or a MapLayout slot -- and GotoActivity
-- drops the player right at it. Fixes the #1 first-session problem: solo players couldn't find the
-- modes (especially Would You Rather) behind a PvP-only "Find Match" button.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))

local ActivityService = {}

local function groundedSpot(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Players :: Instance }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 80, 0), Vector3.new(0, -300, 0), params)
	return Vector3.new(pos.X, (if hit then hit.Position.Y else pos.Y) + 4, pos.Z)
end

-- find the CFrame of the part/model holding a ProximityPrompt matching `pred`
local function promptCF(pred: (ProximityPrompt) -> boolean): CFrame?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and pred(d) then
			local p = d.Parent
			if p and p:IsA("BasePart") then
				return p.CFrame
			elseif p and p:IsA("Model") then
				return p:GetPivot()
			end
		end
	end
	return nil
end

local function partCF(name: string): CFrame?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			return d.CFrame
		end
	end
	return nil
end

-- key -> teleport CFrame resolver. Re-resolved on each request so it's robust to the runtime build.
local LOCATORS: { [string]: () -> CFrame? } = {
	choices = function()
		return promptCF(function(pr)
			return string.find(pr.ObjectText or "", "Would You Rather") ~= nil
		end) or MapLayout.choices()
	end,
	freekick = function()
		return promptCF(function(pr)
			return pr.Name == "WarmupPrompt" or pr.ActionText == "Free Kicks"
		end)
	end,
	gauntlet = function()
		return partCF("GauntletPad")
	end,
	trivia = function()
		return MapLayout.activity("trivia")
	end,
	training = function()
		return MapLayout.plaza("photo")
	end,
}

local function teleport(player: Player, cf: CFrame)
	local char = player.Character
	if not char then
		return
	end
	char:PivotTo(CFrame.new(groundedSpot(cf.Position)))
end

function ActivityService.start()
	Net.getEvent(Net.Events.GotoActivity).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			local key = if type(payload) == "table" then (payload :: any).key else nil
			if type(key) ~= "string" then
				return
			end
			local locate = LOCATORS[key]
			if not locate then
				return
			end
			local cf = locate()
			if cf then
				teleport(player, cf)
			end
		end)
end

return ActivityService
