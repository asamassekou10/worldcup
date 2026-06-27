--!strict
-- FieldCoinsService: respawning coin pickups along the hub's two walkways (the shopping plaza +side
-- and the activities row -side), so wandering the map is rewarded and the hub feels alive instead of
-- everyone parked at FIND MATCH.
--
-- Anti-farm guardrails (the reason a free coin faucet is normally a bad idea):
--   * each grant goes through DataService.grantFieldCoin, which enforces a per-player DAILY CAP;
--   * each coin has a respawn cooldown (you can't immediately re-grab the same spot);
--   * coins are small (a trickle, not a primary income), so they don't inflate the economy.
-- Coins sit just inside the touchlines (never out on the pitch) so they line the walking paths.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))

local Assets = require(script.Parent:WaitForChild("Assets"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local FieldCoinsService = {}

local COIN_REWARD = 4 -- small on purpose (ambient flavour, not real income)
local RESPAWN = 45 -- seconds before a collected coin returns
local COIN_H = 4 -- model height in studs
local SIDE = 60 -- |distance from pitch centre| -- just inside the touchline (PLAZA_DIST = 64)
local TS = { -48, -32, -16, 0, 16, 32, 48 } -- positions along each walkway

local function playerFromHit(hit: BasePart): Player?
	local char = hit.Parent
	if not char or not char:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

function FieldCoinsService.start()
	local geo = MapLayout.geo()
	if not geo then
		return -- no pitch markers -> nothing to anchor to
	end
	local folder = Instance.new("Folder")
	folder.Name = "FieldCoins"
	folder.Parent = workspace

	local floorY = geo.center.Y
	local coinTemplate = Assets.template(Config.Models.ChoicesCoin) -- one cached load for all coins

	local function buildCoin(pos: Vector3)
		-- invisible hitbox: the robust catcher; also carries the glow + ding so a coin reads + works
		-- even if the model asset fails to load.
		local hit = Instance.new("Part")
		hit.Name = "FieldCoin"
		hit.Size = Vector3.new(6, 7, 6)
		hit.Anchored = true
		hit.CanCollide = false
		hit.CanQuery = false
		hit.Transparency = 1
		hit.CFrame = CFrame.new(pos)
		hit.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 205, 60)
		light.Range = 8
		light.Brightness = 1.1
		light.Parent = hit
		local aura = Instance.new("ParticleEmitter")
		aura.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140))
		aura.LightEmission = 1
		aura.Rate = 8
		aura.Lifetime = NumberRange.new(0.5, 0.9)
		aura.Speed = NumberRange.new(0.5, 1.5)
		aura.Size = NumberSequence.new(0.8)
		aura.Transparency = NumberSequence.new(0.4)
		aura.Parent = hit
		local ding = Instance.new("Sound")
		ding.SoundId = "rbxassetid://135483737426662"
		ding.Volume = 0.55
		ding.RollOffMaxDistance = 60
		ding.Parent = hit

		local model: Instance? = nil
		if coinTemplate then
			-- base rests at pos.Y - COIN_H/2 -> the coin floats centred on `pos`
			model = Assets.place(
				folder,
				Config.Models.ChoicesCoin,
				CFrame.new(pos.X, pos.Y - COIN_H / 2, pos.Z),
				COIN_H
			)
		else
			local disc = Instance.new("Part")
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.4, 3, 3)
			disc.Anchored = true
			disc.CanCollide = false
			disc.CanQuery = false
			disc.Material = Enum.Material.Neon
			disc.Color = Color3.fromRGB(255, 205, 60)
			disc.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0)
			disc.Parent = folder
			model = disc
		end

		local available = true
		hit.Touched:Connect(function(part: BasePart)
			if not available then
				return
			end
			local plr = playerFromHit(part)
			if not plr then
				return
			end
			if not DataService.grantFieldCoin(plr, COIN_REWARD) then
				return -- daily cap reached; leave the coin alone (no exploit, no double-deduct)
			end
			available = false
			aura:Emit(20) -- sparkle pop
			ding:Play()
			if model then
				model.Parent = nil -- visually "collected"
			end
			light.Enabled = false
			task.delay(RESPAWN, function()
				available = true
				light.Enabled = true
				if model then
					model.Parent = folder
				end
			end)
		end)
	end

	for _, t in TS do
		local plaza = geo.center + geo.side * SIDE + geo.axis * t
		local activities = geo.center - geo.side * SIDE + geo.axis * t
		buildCoin(Vector3.new(plaza.X, floorY + 2, plaza.Z))
		buildCoin(Vector3.new(activities.X, floorY + 2, activities.Z))
	end
end

return FieldCoinsService
