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
local COIN_H = 2.6 -- model height in studs (small -- a "walk over" coin, not a glowing blob)
local SIDE = 60 -- |distance from pitch centre| -- just inside the touchline (PLAZA_DIST = 64)
-- denser line along each walkway (more coins, as requested)
local TS = { -50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50 }

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
		hit.Size = Vector3.new(3.4, 5, 3.4) -- tight: you must be literally on the coin
		hit.Anchored = true
		hit.CanCollide = false
		hit.CanQuery = false
		hit.Transparency = 1
		hit.CFrame = CFrame.new(pos)
		hit.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 205, 60)
		light.Range = 4.5 -- small halo on the coin, not a glow blob
		light.Brightness = 0.7
		light.Parent = hit
		local aura = Instance.new("ParticleEmitter")
		aura.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140))
		aura.LightEmission = 1
		aura.Rate = 6
		aura.Lifetime = NumberRange.new(0.5, 0.9)
		aura.Speed = NumberRange.new(0.5, 1.2)
		aura.Size = NumberSequence.new(0.6)
		aura.Transparency = NumberSequence.new(0.4)
		aura.Parent = hit
		local ding = Instance.new("Sound")
		ding.SoundId = "rbxassetid://135483737426662"
		ding.Volume = 0.55
		ding.RollOffMaxDistance = 60
		ding.Parent = hit

		local model: Instance? = nil
		if coinTemplate then
			-- centre the coin's geometry exactly on the hitbox (the model's saved pivot is offset, so
			-- a plain PivotTo would float the visible coin away from where it's actually collected)
			model = Assets.placeCentered(folder, Config.Models.ChoicesCoin, pos, COIN_H)
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

	-- place a coin at (s = studs across from centre, t = studs along the pitch from centre)
	local function place(s: number, t: number)
		local p = geo.center + geo.side * s + geo.axis * t
		buildCoin(Vector3.new(p.X, floorY + 2, p.Z))
	end

	-- both touchline walkways
	for _, t in TS do
		place(SIDE, t)
		place(-SIDE, t)
	end

	-- a trail extending the activities walkway toward the WYR portal (wayfinding to that mode)
	for _, t in { 56, 64, 72 } do
		place(-SIDE, t)
	end

	-- ===== more coins, spread across the map (not just the two edges) =====
	-- a spine straight down the middle of the pitch
	for _, t in { -55, -35, -15, 15, 35, 55 } do
		place(0, t)
	end
	-- two rows crossing the pitch, so the coins read as a grid
	for _, t in { -30, 30 } do
		for _, s in { -42, -21, 21, 42 } do
			place(s, t)
		end
	end
	-- the four corners of the apron
	for _, t in { -64, 64 } do
		for _, s in { -48, 48 } do
			place(s, t)
		end
	end
end

return FieldCoinsService
