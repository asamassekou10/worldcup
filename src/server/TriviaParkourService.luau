--!strict
-- TriviaParkourService: the "Choices" runner (Would-You-Rather + World Cup trivia).
-- A hub portal drops you onto a long split-lane road. Two glass doors appear across the
-- lanes; you run through the side you pick. Most gates are no-fail "Would You Rather"
-- dilemmas that show a GLOBAL vote tally after you choose (the viral hook); every few
-- gates is a scored World Cup trivia gate (right door = points). Reach the World Cup
-- trophy at the end for the big reward.
--
-- Server-authoritative: owns the dilemmas/questions, the door triggers, the vote tallies,
-- scoring, the leaderboard and rewards. Bright, no falling, no hazards -- it's about
-- choosing, not surviving. Door content is mounted ON the doors (big SurfaceGui), so the
-- world stays clean -- no floating banners.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local TriviaBank = require(Shared:WaitForChild("TriviaBank"))
local ChoiceBank = require(Shared:WaitForChild("ChoiceBank"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Progression = require(Shared:WaitForChild("Progression"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local Assets = require(script.Parent:WaitForChild("Assets"))
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
local BadgeService = require(script.Parent:WaitForChild("BadgeService"))
local TreadmillService = require(script.Parent:WaitForChild("TreadmillService"))

local TriviaParkourService = {}

-- ----- layout -----
local COURSE_ORIGIN = Vector3.new(0, 500, 0) -- a quiet area well clear of the stadium
local LANE_W = 11 -- each running lane
local DIVIDER_W = 2 -- the low center rail between the lanes
local ROAD_W = LANE_W * 2 + DIVIDER_W
local LANE_OFF = DIVIDER_W / 2 + LANE_W / 2 -- |X| of each lane's center
local GATE_SPACING = 62 -- more runway between choices (splash clears before the next gate)
local NUM_GATES = 22
local TRIVIA_EVERY = 4 -- every Nth gate is a scored World Cup trivia gate
local WALL_H = 15 -- taller gate walls -> taller, more imposing choice doors
local RUN_SPEED = 22 -- everyone runs quick (it's a runner)

-- ----- rewards / scoring -----
local REWARD_CORRECT = 25
local REWARD_FINISH = 150
local FRIEND_BONUS = 50 -- extra coins on finish if a friend was in the server
local XP_FINISH = 30
local LETTERS = { "A", "B", "C", "D" }
local POINTS_CORRECT = 100
local POINTS_STREAK = 25
local POINTS_FINISH = 500
local TARGET_TIME = 150 -- finish under this (sec) for a speed bonus (5 pts/sec saved)
local BOARD_TOP_N = 8
local BOARD_REFRESH = 60

-- ----- door colors -----
local LEFT_ACCENT = Color3.fromRGB(60, 130, 230)
local RIGHT_ACCENT = Color3.fromRGB(235, 120, 55)

-- Earned cosmetic auras: collect this many legends to unlock each (rarer needs more). On a run
-- you automatically wear your rarest one. Synergises with the legend collection.
local AURA_UNLOCKS = {
	{ at = 3, key = "sparkle", label = "✨ Sparkle aura" },
	{ at = 6, key = "wind", label = "💨 Gale aura" },
	{ at = 10, key = "ice", label = "❄️ Frost aura" },
	{ at = 14, key = "fire", label = "🔥 Inferno aura" },
	{ at = ChoiceBank.legendCount(), key = "thunder", label = "⚡ Thunder aura" },
}
local AURA_PRIORITY = { "thunder", "fire", "ice", "wind", "sparkle" } -- rarest-first (auto-equip)

type RunState = {
	points: number,
	streak: number,
	startedAt: number,
	agreed: number, -- dilemmas where you picked the crowd-majority side
	dilemmas: number, -- dilemmas you answered this run
	newLegends: { string }, -- legend display names first unlocked this run
	friend: boolean, -- a friend was in the server when you started (bonus on finish)
	dailyHit: { [string]: boolean }, -- which of today's featured "Daily 5" you've answered
}

local startCF = CFrame.new(COURSE_ORIGIN + Vector3.new(-LANE_OFF, 4, 0))
local finishing: { [Player]: boolean } = {}
local runState: { [Player]: RunState } = {}
local nameCache: { [number]: string } = {}
-- Each player's avatar BEFORE any choice morphed it, so we can restore it on exit.
local originalDesc: { [Player]: HumanoidDescription } = {}

-- Best-points board (degrades to empty without API access, like LeaderboardService).
local parkourStore: OrderedDataStore? = (function(): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("ParkourPoints_v1")
	end)
	return if ok then store else nil
end)()

-- Global vote tallies, persisted per dilemma id. Cached in memory so the "X% chose A"
-- splash is instant; writes are fire-and-forget UpdateAsync (degrades silently in Studio).
local votesStore: DataStore? = (function(): DataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("ChoiceVotes_v1")
	end)
	return if ok then store else nil
end)()
type Tally = { a: number, b: number }
local voteCache: { [string]: Tally } = {}

local function getVotes(id: string): Tally
	local cached = voteCache[id]
	if cached then
		return cached
	end
	local v: Tally = { a = 0, b = 0 }
	if votesStore then
		pcall(function()
			local d = (votesStore :: DataStore):GetAsync(id)
			if type(d) == "table" then
				v = { a = tonumber((d :: any).a) or 0, b = tonumber((d :: any).b) or 0 }
			end
		end)
	end
	voteCache[id] = v
	return v
end

local function addVote(id: string, pickedA: boolean): Tally
	local v = getVotes(id)
	if pickedA then
		v.a += 1
	else
		v.b += 1
	end
	if votesStore then
		task.spawn(function()
			pcall(function()
				(votesStore :: DataStore):UpdateAsync(id, function(old: any): Tally
					local t: Tally = if type(old) == "table"
						then { a = tonumber(old.a) or 0, b = tonumber(old.b) or 0 }
						else { a = 0, b = 0 }
					if pickedA then
						t.a += 1
					else
						t.b += 1
					end
					return t
				end)
			end)
		end)
	end
	return v
end

local function resolveName(userId: number): string
	local known = nameCache[userId]
	if known then
		return known
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok then name else ("Player" .. userId)
	nameCache[userId] = result
	return result
end

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

local function playerFromHit(hit: BasePart): Player?
	local char = hit.Parent
	if not char or not char:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

local function teleport(player: Player, cf: CFrame)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CFrame = cf
	end
end

-- Real catalog particle-aura templates (red -> "fire", thunder -> "thunder"), loaded once at
-- start; cloned onto a character on an aura effect. Empty until loaded -> procedural fallback.
local auraEmitters: { [string]: { ParticleEmitter } } = {}
local function loadAuraEmitters(id: number): { ParticleEmitter }
	local out: { ParticleEmitter } = {}
	if id <= 0 then
		return out
	end
	local ok, c = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if ok and c then
		for _, d in c:GetDescendants() do
			if d:IsA("ParticleEmitter") and #out < 6 then
				local em = d:Clone()
				em.Name = "ChoicesAura"
				out[#out + 1] = em
			end
		end
		c:Destroy()
	end
	return out
end

-- Park the rain particles + lava sky in ReplicatedStorage so the client weather can use them.
local function preloadWeatherFX()
	if Config.Models.EffectRain > 0 and not ReplicatedStorage:FindFirstChild("ChoicesRainFX") then
		local ok, c = pcall(function()
			return InsertService:LoadAsset(Config.Models.EffectRain)
		end)
		if ok and c then
			local f = Instance.new("Folder")
			f.Name = "ChoicesRainFX"
			local n = 0
			for _, d in c:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d:Clone().Parent = f
					n += 1
				end
			end
			c:Destroy()
			if n > 0 then
				f.Parent = ReplicatedStorage
			else
				f:Destroy()
			end
		end
	end
	if
		Config.Models.EffectLavaSky > 0 and not ReplicatedStorage:FindFirstChild("ChoicesLavaSky")
	then
		local ok, c = pcall(function()
			return InsertService:LoadAsset(Config.Models.EffectLavaSky)
		end)
		if ok and c then
			local sky = c:FindFirstChildWhichIsA("Sky", true)
			if sky then
				local s = sky:Clone()
				s.Name = "ChoicesLavaSky"
				s.Parent = ReplicatedStorage
			end
			c:Destroy()
		end
	end
end

-- Full-body COSTUMES (e.g. the team mascot). The mascot asset is a static mesh model
-- (no rig), so we can't swap the character -- instead we weld every part of the costume
-- to the player's HumanoidRootPart and hide their real body. Restored on exit.
local costumeTemplates: { [string]: Model? } = {}
local function loadCostume(id: number): Model?
	if id <= 0 then
		return nil
	end
	local ok, c = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not c then
		return nil
	end
	local model = c:FindFirstChildWhichIsA("Model")
	local template = if model then model:Clone() else nil
	c:Destroy()
	if not template then
		return nil
	end
	for _, d in template:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Humanoid") or d:IsA("Tool") then
			d:Destroy()
		end
	end
	return template
end

-- True WORLD axis-aligned bounding box of a model (every part's 8 corners). We can't trust
-- Model:GetBoundingBox here: the mascot's saved PIVOT is tilted relative to its geometry, so
-- the pivot box is misleading -- the asset actually stands ~8 studs tall along world Y.
local function worldAABB(model: Model): (Vector3, Vector3)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = -min
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, h = d.CFrame, d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						min = min:Min(corner)
						max = max:Max(corner)
					end
				end
			end
		end
	end
	return (min + max) / 2, (max - min)
end

local MASCOT_HEIGHT = 6.4 -- studs tall once worn (a touch bigger than the player)
local MASCOT_FACE_DEG = 0 -- flip to 180 if the mascot ends up facing backwards
local function applyCostume(player: Player, template: Model)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then
		return
	end
	local old = char:FindFirstChild("ChoicesCostume")
	if old then
		old:Destroy()
	end
	local costume = template:Clone()
	costume.Name = "ChoicesCostume"
	-- 1) scale the (world-upright) asset down to roughly player height
	local _, size0 = worldAABB(costume)
	if size0.Y > 0.1 then
		costume:ScaleTo(MASCOT_HEIGHT / size0.Y)
	end
	-- 2) rigidly move it onto the player by its TRUE world box (not its tilted pivot), keeping
	--    it upright and yaw-matched to the player so it turns with them once welded.
	local center = worldAABB(costume)
	local hrpCF = (hrp :: BasePart).CFrame
	local look = hrpCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local target = CFrame.lookAt((hrp :: BasePart).Position, (hrp :: BasePart).Position + flat)
		* CFrame.Angles(0, math.rad(MASCOT_FACE_DEG), 0)
	local fromUpright = CFrame.new(center) -- identity rotation at the asset's world center
	for _, d in costume:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = target * fromUpright:ToObjectSpace(d.CFrame)
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = hrp :: BasePart
			w.Part1 = d
			w.Parent = d
		end
	end
	costume.Parent = char
	-- hide the real body (parts + face decals) so only the costume shows.
	for _, d in char:GetDescendants() do
		if d:IsDescendantOf(costume) then
			continue
		end
		local isBody = d:IsA("BasePart") and d.Name ~= "HumanoidRootPart"
		if isBody or d:IsA("Decal") then
			(d :: any).Transparency = 1
		end
	end
end

-- Change the player's avatar to match the door they ran through. Two kinds of morph:
--   bodyColor -- recolour the whole body (the reliable approximation legends).
--   shirt/pants -- a REAL kit. These ids are clothing TEMPLATE images, so they go on a
--                  Shirt/Pants INSTANCE (named "ChoicesKit"), not the HumanoidDescription
--                  (whose Shirt/Pants want catalog item ids). We snapshot the pre-morph
--                  HumanoidDescription once so we can fully restore the avatar on exit.
local function applyMorph(player: Player, morph: ChoiceBank.Morph, legendId: string?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then
		return
	end
	-- Universal cue: a team-coloured Highlight + a "You are: X" nametag. The kit/body-colour
	-- below only show on standard avatars; this shows the transform on ANY avatar (custom
	-- bundles, Rthro, etc.) so the change is always visible.
	if legendId then
		local color = ChoiceBank.LegendColor[legendId] or Color3.fromRGB(255, 220, 120)
		local existing = char:FindFirstChild("ChoicesMorphFX")
		if existing then
			existing:Destroy()
		end
		local hl = Instance.new("Highlight")
		hl.Name = "ChoicesMorphFX"
		hl.FillColor = color
		hl.FillTransparency = 0.55
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hl.Parent = char
		local head = char:FindFirstChild("Head")
		if head then
			local old = head:FindFirstChild("ChoicesMorphTag")
			if old then
				old:Destroy()
			end
			local bb = Instance.new("BillboardGui")
			bb.Name = "ChoicesMorphTag"
			bb.Size = UDim2.fromScale(6, 1.3)
			bb.StudsOffset = Vector3.new(0, 2.6, 0)
			bb.AlwaysOnTop = true
			bb.Adornee = head
			bb.Parent = head
			local tag = Instance.new("TextLabel")
			tag.Size = UDim2.fromScale(1, 1)
			tag.BackgroundTransparency = 1
			tag.Font = Enum.Font.GothamBlack
			tag.TextScaled = true
			tag.TextColor3 = color
			tag.TextStrokeTransparency = 0.3
			tag.Text = "⚽ " .. (ChoiceBank.Legends[legendId] or legendId)
			tag.Parent = bb
		end
	end
	task.spawn(function()
		local ok, desc = pcall(function()
			return (hum :: Humanoid):GetAppliedDescription()
		end)
		if ok and desc and not originalDesc[player] then
			originalDesc[player] = desc:Clone() -- the look before this first morph
		end
		-- approximation legends: recolour the body via the description
		if morph.bodyColor and ok and desc then
			local c = morph.bodyColor
			desc.HeadColor = c
			desc.TorsoColor = c
			desc.LeftArmColor = c
			desc.RightArmColor = c
			desc.LeftLegColor = c
			desc.RightLegColor = c
			pcall(function()
				(hum :: Humanoid):ApplyDescription(desc)
			end)
		end
		-- real kit: swap the character's Shirt/Pants instances to the kit templates
		if morph.shirt and morph.shirt > 0 then
			for _, ex in char:GetChildren() do
				if ex:IsA("Shirt") then
					ex:Destroy()
				end
			end
			local s = Instance.new("Shirt")
			s.Name = "ChoicesKit"
			s.ShirtTemplate = "rbxassetid://" .. morph.shirt
			s.Parent = char
		end
		if morph.pants and morph.pants > 0 then
			for _, ex in char:GetChildren() do
				if ex:IsA("Pants") then
					ex:Destroy()
				end
			end
			local p = Instance.new("Pants")
			p.Name = "ChoicesKit"
			p.PantsTemplate = "rbxassetid://" .. morph.pants
			p.Parent = char
		end
	end)
end

local function restoreAvatar(player: Player)
	local desc = originalDesc[player]
	originalDesc[player] = nil
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then
		return
	end
	-- drop the morph FX (highlight + nametag) and any kit clothing we added
	local fx = char:FindFirstChild("ChoicesMorphFX")
	if fx then
		fx:Destroy()
	end
	local head = char:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("ChoicesMorphTag")
	if tag then
		tag:Destroy()
	end
	for _, ex in char:GetChildren() do
		if (ex:IsA("Shirt") or ex:IsA("Pants")) and ex.Name == "ChoicesKit" then
			ex:Destroy()
		end
	end
	-- drop any full-body costume (mascot) so the real avatar shows again
	local costume = char:FindFirstChild("ChoicesCostume")
	if costume then
		costume:Destroy()
	end
	for _, d in char:GetDescendants() do
		if d:IsA("Decal") and d.Transparency >= 0.8 then
			d.Transparency = 0
		end
	end
	-- reset run EFFECTS (size / jump / invisibility / aura) + clear personal weather
	for _, n in { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" } do
		local v = hum:FindFirstChild(n)
		if v and v:IsA("NumberValue") then
			v.Value = 1
		end
	end
	(hum :: Humanoid).JumpPower = 50
	for _, d in char:GetDescendants() do
		if d.Name == "ChoicesAura" or d.Name == "ChoicesCosmeticAura" then
			d:Destroy()
		elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency >= 0.8 then
			d.Transparency = 0
		end
	end
	Net.getEvent(Net.Events.ChoicesEffect):FireClient(player, { weather = "clear" })
	if desc then
		task.spawn(function()
			pcall(function()
				(hum :: Humanoid):ApplyDescription(desc)
			end)
		end)
	end
end

-- Attach a particle aura (named `name`) to a root part: a real catalog emitter if we loaded one
-- for this type (fire/thunder), else a procedural fallback (ice/sparkle/wind). Replaces any
-- existing emitter of the same name. Shared by door effects + the earned cosmetic aura.
local function attachAura(root: BasePart, auraType: string, name: string)
	for _, ch in root:GetChildren() do
		if ch.Name == name then
			ch:Destroy()
		end
	end
	local templates = auraEmitters[auraType]
	if templates and #templates > 0 then
		for _, t in templates do
			local c = t:Clone()
			c.Name = name
			c.Parent = root
		end
		return
	end
	local em = Instance.new("ParticleEmitter")
	em.Name = name
	em.Rate = 26
	em.Lifetime = NumberRange.new(0.5, 0.9)
	em.Speed = NumberRange.new(2, 5)
	em.Size = NumberSequence.new(2)
	em.LightEmission = 0.8
	if auraType == "ice" then
		em.Color = ColorSequence.new(Color3.fromRGB(180, 240, 255), Color3.fromRGB(90, 160, 220))
	elseif auraType == "wind" then
		em.Color = ColorSequence.new(Color3.fromRGB(225, 240, 255), Color3.fromRGB(170, 200, 230))
		em.Speed = NumberRange.new(6, 11)
	elseif auraType == "thunder" then
		em.Color = ColorSequence.new(Color3.fromRGB(185, 200, 255), Color3.fromRGB(120, 90, 230))
	elseif auraType == "fire" then
		em.Color = ColorSequence.new(Color3.fromRGB(255, 160, 40), Color3.fromRGB(230, 40, 20))
		em.Acceleration = Vector3.new(0, 8, 0)
	else -- "sparkle"
		em.Color = ColorSequence.new(Color3.fromRGB(255, 235, 120), Color3.fromRGB(255, 200, 60))
	end
	em.Parent = root
end

-- Apply a door's EFFECT: speed / jump / size / invisibility / aura are server-side (everyone
-- sees them); weather + sound are sent to the player's client. Same-category effects replace.
local function applyEffect(player: Player, effect: ChoiceBank.Effect)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char and hum then
		local h = hum :: Humanoid
		if effect.walkSpeed then
			h.WalkSpeed = math.clamp(RUN_SPEED * effect.walkSpeed, 8, 50)
		end
		if effect.jump then
			h.UseJumpPower = true
			h.JumpPower = math.clamp(effect.jump, 30, 120)
		end
		if effect.scale then
			local s = math.clamp(effect.scale, 0.4, 1.8)
			for _, n in { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" } do
				local v = h:FindFirstChild(n)
				if v and v:IsA("NumberValue") then
					v.Value = s
				end
			end
		end
		if effect.invisible then
			for _, d in char:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
					d.Transparency = math.max(d.Transparency, 0.85)
				end
			end
		end
		if effect.aura then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				attachAura(root, effect.aura, "ChoicesAura")
			end
		end
		if effect.costume then
			local template = costumeTemplates[effect.costume]
			if template then
				applyCostume(player, template)
			end
		end
	end
	if effect.weather or effect.sound then
		Net.getEvent(Net.Events.ChoicesEffect)
			:FireClient(player, { weather = effect.weather, sound = effect.sound })
	end
end

-- Cosmetic "trail" perk: a glowing streak that follows you down the course (gamepass).
local function attachTrail(player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or root:FindFirstChild("ChoicesTrail") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "ChoicesTrailA0"
	a0.Position = Vector3.new(0, 1.6, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "ChoicesTrailA1"
	a1.Position = Vector3.new(0, -1.6, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "ChoicesTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 215, 95), Color3.fromRGB(255, 110, 60))
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = root
end

local function removeTrail(player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, n in { "ChoicesTrail", "ChoicesTrailA0", "ChoicesTrailA1" } do
		local x = root:FindFirstChild(n)
		if x then
			x:Destroy()
		end
	end
end

local function block(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ground(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Players :: Instance }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return Vector3.new(pos.X, if hit then hit.Position.Y else pos.Y, pos.Z)
end

-- Place a catalog model as decor and STRIP its scripts (Assets.place does not), so no
-- untrusted free-model code runs on the server. Returns the placed instance (or nil).
local function placeDecor(
	parent: Instance,
	id: number,
	cf: CFrame,
	targetHeight: number?
): Instance?
	if id <= 0 then
		return nil
	end
	local placed = Assets.place(parent, id, cf, targetHeight)
	if placed then
		for _, d in placed:GetDescendants() do
			-- Strip scripts, humanoids/tools, and physics movers (AlignPosition/RigidConstraint
			-- etc. drift unanchored parts -> the floating-light bug). Keep welds.
			local isMover = (d:IsA("Constraint") and not d:IsA("WeldConstraint"))
				or d:IsA("BodyMover")
			if d:IsA("BaseScript") or d:IsA("Humanoid") or d:IsA("Tool") or isMover then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true -- nothing physics-moves; pure static decor
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		-- re-ground: drop the whole model so its lowest point sits on the turf at cf.Y
		if placed:IsA("Model") then
			local bcf, size = placed:GetBoundingBox()
			local bottom = bcf.Position.Y - size.Y / 2
			placed:PivotTo(placed:GetPivot() + Vector3.new(0, cf.Position.Y - bottom, 0))
		end
	end
	return placed
end

-- Extract just the "Portal1" frame from the portal pack (the pack is a folder of two
-- portals + teleport scripts), strip its scripts, scale to `targetHeight`, and stand it on
-- `pos` with its opening facing `facing`. Returns the placed model (or nil).
local function placePortalFrame(
	parent: Instance,
	pos: Vector3,
	facing: Vector3,
	targetHeight: number
)
	if Config.Models.ChoicesPortalPack <= 0 then
		return
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(Config.Models.ChoicesPortalPack)
	end)
	if not ok or not container then
		return
	end
	local src = container:FindFirstChild("Portal1", true)
	local clone = src and src:Clone()
	container:Destroy()
	if not clone or not clone:IsA("Model") then
		return
	end
	for _, d in clone:GetDescendants() do
		local isMover = (d:IsA("Constraint") and not d:IsA("WeldConstraint")) or d:IsA("BodyMover")
		if d:IsA("BaseScript") or isMover then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	clone.Parent = parent
	local _, sz = clone:GetBoundingBox()
	if sz.Y > 0 then
		clone:ScaleTo(targetHeight / sz.Y)
	end
	-- opening normal is the model's local +X; fromMatrix sets RightVector = facing
	clone:PivotTo(CFrame.fromMatrix(pos, facing, Vector3.yAxis))
	local bcf, s2 = clone:GetBoundingBox()
	clone:PivotTo(clone:GetPivot() + Vector3.new(0, pos.Y - (bcf.Position.Y - s2.Y / 2), 0))
end

-- Place a catalog model with PRECISE control (Assets.place's auto-scale is unreliable for
-- some models -> the giant-arch / floating-pedestal bugs). Loads it, picks the inner model,
-- strips scripts/movers/guis, anchors, scales by its TRUE bounding-box height to
-- `targetHeight`, faces `facing` (optional), and grounds its base at `baseCF.Y`. Returns
-- the placed model (so callers can read its real top, e.g. to sit a cap on it).
local function placeModelFitted(
	parent: Instance,
	id: number,
	baseCF: CFrame,
	targetHeight: number?,
	facing: Vector3?,
	solid: boolean?,
	solidHeight: number?
): Model?
	if id <= 0 then
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not container then
		return nil
	end
	local model = Instance.new("Model")
	for _, ch in container:GetChildren() do
		if not ch:IsA("Camera") then
			ch:Clone().Parent = model
		end
	end
	container:Destroy()
	for _, d in model:GetDescendants() do
		local isMover = (d:IsA("Constraint") and not d:IsA("WeldConstraint")) or d:IsA("BodyMover")
		if
			d:IsA("BaseScript")
			or d:IsA("Humanoid")
			or d:IsA("Tool")
			or d:IsA("ScreenGui")
			or isMover
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	if not model:FindFirstChildWhichIsA("BasePart", true) then
		model:Destroy()
		return nil
	end
	local _, sz = model:GetBoundingBox()
	if targetHeight and sz.Y > 0.01 then
		model:ScaleTo(targetHeight / sz.Y)
	end
	local pos = baseCF.Position
	model:PivotTo(if facing then CFrame.lookAt(pos, pos + facing) else CFrame.new(pos))
	local bcf, s2 = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, pos.Y - (bcf.Position.Y - s2.Y / 2), 0))
	model.Parent = parent
	-- Optional invisible collision hull so players can't walk through the model. `solidHeight`
	-- caps it (e.g. a treadmill: a low box you step onto, not a full-height wall).
	if solid then
		local box, bsz = model:GetBoundingBox()
		local h = if solidHeight then solidHeight else bsz.Y
		local hull = Instance.new("Part")
		hull.Anchored = true
		hull.CanCollide = true
		hull.CanQuery = false
		hull.Transparency = 1
		hull.Size = Vector3.new(bsz.X, h, bsz.Z)
		hull.CFrame = box * CFrame.new(0, h / 2 - bsz.Y / 2, 0)
		hull.Parent = model
	end
	return model
end

-- ----- door content (a big SurfaceGui mounted on the door) -----
local function rounded(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- A one-glyph hint of what a door DOES, so players can anticipate + strategize from a distance.
local function effectIcon(
	effect: ChoiceBank.Effect?,
	morph: ChoiceBank.Morph?,
	legend: string?
): string
	if effect then
		if effect.costume == "mascot" then
			return "🦁"
		end
		local weatherIcon = {
			rain = "🌧️",
			heat = "🔥",
			snow = "❄️",
			storm = "⛈️",
			fog = "🌫️",
			night = "🌙",
		}
		if effect.weather and weatherIcon[effect.weather] then
			return weatherIcon[effect.weather]
		end
		local auraIcon =
			{ fire = "🔥", ice = "❄️", thunder = "⚡", sparkle = "✨", wind = "💨" }
		if effect.aura and auraIcon[effect.aura] then
			return auraIcon[effect.aura]
		end
		if effect.invisible then
			return "👻"
		end
		if effect.scale then
			return if effect.scale < 1 then "🐜" else "🦣"
		end
		if effect.walkSpeed then
			return if effect.walkSpeed >= 1 then "⚡" else "🐌"
		end
		if effect.jump then
			return "🦘"
		end
		if effect.sound then
			return "🔊"
		end
	end
	if legend then
		return "⭐"
	end
	if morph then
		return "👕"
	end
	return "🚪"
end

local function doorPanel(
	door: BasePart,
	optionText: string,
	image: string?,
	accent: Color3,
	icon: string?
)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front -- the -Z face, toward the approaching player
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.Parent = door

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(12, 18, 32)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 6
	stroke.Parent = bg

	-- effect-hint badge in the top-left corner
	if icon and icon ~= "" then
		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.fromScale(0.26, 0.26)
		badge.Position = UDim2.fromScale(0.04, 0.04)
		badge.BackgroundColor3 = accent
		badge.BackgroundTransparency = 0.15
		badge.Font = Enum.Font.GothamBlack
		badge.TextScaled = true
		badge.Text = icon
		badge.TextColor3 = Color3.fromRGB(255, 255, 255)
		badge.Parent = bg
		rounded(badge, 14)
	end

	if image and image ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(0.84, 0.5)
		img.Position = UDim2.fromScale(0.08, 0.08)
		img.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		img.BackgroundTransparency = 0.4
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = image
		img.Parent = bg
		rounded(img, 10)
	end

	local opt = Instance.new("TextLabel")
	opt.Size = UDim2.fromScale(0.9, if image and image ~= "" then 0.34 else 0.74)
	opt.Position = UDim2.fromScale(0.05, if image and image ~= "" then 0.62 else 0.13)
	opt.BackgroundTransparency = 1
	opt.Font = Enum.Font.GothamBlack
	opt.TextScaled = true
	opt.TextWrapped = true
	opt.TextColor3 = Color3.fromRGB(255, 255, 255)
	opt.TextStrokeTransparency = 0.5
	opt.Text = optionText
	opt.Parent = bg
end

local function beamPrompt(beam: BasePart, promptText: string)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.Parent = beam
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(0.96, 0.84)
	t.Position = UDim2.fromScale(0.02, 0.08)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextWrapped = true
	t.TextColor3 = Color3.fromRGB(255, 236, 170)
	t.TextStrokeTransparency = 0.4
	t.Text = promptText
	t.Parent = sg
end

-- Line the course with real "Race Grand Stand" sections (seats face the lane). The model is
-- big + heavy (~1.3k parts each), and the course is ~1100 studs long, so we place SPACED
-- sections (not a full tile) and ground each one. Seats face the model's local -X, so the
-- right side gets no yaw and the left side is spun 180 deg to face back at the lane.
local function buildGrandstands(
	parent: Instance,
	yBase: number,
	template: Model,
	zA: number,
	zB: number
)
	-- Use the TRUE world AABB (the model is authored upright but its saved pivot is tilted, so
	-- GetBoundingBox/PivotTo would tip the stand over -- same gotcha as the mascot). We move each
	-- clone RIGIDLY off that upright frame: yaw only (stays upright) + grounded by the AABB.
	local center, size = worldAABB(template)
	local from = CFrame.new(center)
	local perSide = 6
	local centerX = ROAD_W / 2 + 6 + size.X / 2 -- inner edge ~6 studs past the road edge
	for i = 0, perSide - 1 do
		local z = zA + (zB - zA) * (i + 0.5) / perSide
		for _, dir in { -1, 1 } do
			local s = template:Clone()
			-- seats are authored facing world +X, so the RIGHT side (+X) spins 180 to face the
			-- lane, the LEFT side stays put.
			local yaw = if dir == 1 then math.pi else 0
			local target = CFrame.new(COURSE_ORIGIN.X + dir * centerX, yBase + size.Y / 2, z)
				* CFrame.Angles(0, yaw, 0)
			for _, d in s:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = true -- solid: no clipping through the stands
					d.CanQuery = false
					d.CFrame = target * from:ToObjectSpace(d.CFrame)
				elseif d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Camera") then
					d:Destroy()
				end
			end
			s.Parent = parent
		end
	end
end

-- Rigidly place a model template at a world position: upright (yaw only) + grounded by its TRUE
-- world AABB, optional uniform scale to a target height, scripts stripped. Robust for any model.
local function placeAsset(
	parent: Instance,
	template: Model,
	pos: Vector3,
	yawRad: number,
	height: number?,
	collide: boolean?
): Model
	local clone = template:Clone()
	if height then
		local _, s0 = worldAABB(clone)
		if s0.Y > 0.1 then
			clone:ScaleTo(height / s0.Y)
		end
	end
	local center, size = worldAABB(clone)
	local from = CFrame.new(center)
	local target = CFrame.new(pos.X, pos.Y + size.Y / 2, pos.Z) * CFrame.Angles(0, yawRad, 0)
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = collide == true
			d.CanQuery = false
			d.CFrame = target * from:ToObjectSpace(d.CFrame)
		elseif d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Camera") then
			d:Destroy()
		end
	end
	clone.Parent = parent
	return clone
end

function TriviaParkourService.start()
	local existing = Workspace:FindFirstChild("TriviaParkour")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "TriviaParkour"
	folder.Parent = Workspace

	-- load the effect-system assets (aura particles + rain + lava sky) off-thread
	task.spawn(function()
		auraEmitters.fire = loadAuraEmitters(Config.Models.AuraRed)
		auraEmitters.thunder = loadAuraEmitters(Config.Models.AuraThunder)
		costumeTemplates.mascot = loadCostume(Config.Models.MascotCostume)
		preloadWeatherFX()
	end)

	-- FTUE nudge: the first time a player ever loads in, point them at the Choices portal
	-- (the most shareable first impression). Fires exactly once, ever, per player.
	DataService.onProfileLoaded(function(player: Player)
		if DataService.markChoicesIntro(player) then
			task.delay(10, function()
				if player.Parent then
					notify(
						player,
						"🤔 NEW: find the glowing WOULD YOU RATHER portal — pick doors, become legends, top the board!"
					)
				end
			end)
		end
	end)

	local O = COURSE_ORIGIN
	local Y = O.Y
	local function gateZ(i: number): number
		return O.Z + 30 + i * GATE_SPACING
	end
	local trophyZ = gateZ(NUM_GATES) + 42
	startCF = CFrame.new(O + Vector3.new(-LANE_OFF, 4, 0))

	-- ===== environment: a bright split-lane road =====
	local z0 = O.Z - 24
	local z1 = trophyZ + 30
	local roadLen = z1 - z0
	local roadCz = (z0 + z1) / 2

	-- grass ground (also the floor -- you can't fall, this is a runner). Big enough to reach the
	-- perimeter wall so the map never reads as a thin floating slab.
	local perimX = 200
	local perimZ0, perimZ1 = z0 - 180, z1 + 180
	local grass = block(
		folder,
		Vector3.new(2 * perimX + 60, 2, (perimZ1 - perimZ0) + 60),
		CFrame.new(O.X, Y - 1, roadCz),
		Color3.fromRGB(96, 162, 74),
		Enum.Material.Grass
	)
	-- custom "Grass" MaterialVariant on the ground (registered once in MaterialService)
	if Config.Models.ChoicesGrassMaterial > 0 then
		local variant = MaterialService:FindFirstChild("ChoicesGrass")
		if not variant then
			local ok, gv = pcall(function()
				return InsertService:LoadAsset(Config.Models.ChoicesGrassMaterial)
			end)
			if ok and gv then
				local mv = gv:FindFirstChildWhichIsA("MaterialVariant", true)
				if mv then
					mv.Name = "ChoicesGrass"
					mv.Parent = MaterialService
					variant = mv
				end
			end
		end
		if variant and variant:IsA("MaterialVariant") then
			grass.Material = variant.BaseMaterial
			grass.MaterialVariant = "ChoicesGrass"
		end
	end
	-- a stadium PERIMETER WALL ringing the grounds, so the edge reads as a boundary instead of a
	-- floating grass slab against the sky. (A nicer wall/hedge asset can be swapped in here.)
	local perimH = 42
	for _, px in { -perimX, perimX } do -- long walls down each side
		block(
			folder,
			Vector3.new(3, perimH, (perimZ1 - perimZ0)),
			CFrame.new(O.X + px, Y + perimH / 2, roadCz),
			Color3.fromRGB(146, 148, 156),
			Enum.Material.Concrete
		)
	end
	for _, pz in { perimZ0, perimZ1 } do -- end walls
		block(
			folder,
			Vector3.new(2 * perimX + 3, perimH, 3),
			CFrame.new(O.X, Y + perimH / 2, pz),
			Color3.fromRGB(146, 148, 156),
			Enum.Material.Concrete
		)
	end
	-- stadium AD BOARDS mounted on the perimeter wall, facing the runway (the billboard's screen
	-- faces +Z, so -90 deg points it toward -X on the right wall and +90 toward +X on the left).
	local billboardT = Assets.template(Config.Models.ChoicesBillboard)
	if billboardT and billboardT:IsA("Model") then
		for i = 0, 3 do
			local bz = roadCz + ((i - 1.5) / 4) * (perimZ1 - perimZ0) * 0.8
			placeAsset(folder, billboardT, Vector3.new(O.X + perimX - 3, Y, bz), math.pi / 2, 34)
			placeAsset(folder, billboardT, Vector3.new(O.X - perimX + 3, Y, bz), -math.pi / 2, 34)
		end
	end
	-- looping stadium crowd ambience: a line of quiet spatial speakers so the roar follows you
	-- the whole way down the course (falls off well before the far-off hub).
	for i = 0, 5 do
		local sz = z0 + (z1 - z0) * (i + 0.5) / 6
		local speaker = block(
			folder,
			Vector3.new(1, 1, 1),
			CFrame.new(O.X, Y + 12, sz),
			Color3.new(0, 0, 0),
			Enum.Material.SmoothPlastic,
			1
		)
		speaker.CanCollide = false
		local snd = Instance.new("Sound")
		snd.SoundId = Config.Audio.Crowd
		snd.Looped = true
		snd.Volume = 0.35
		snd.RollOffMaxDistance = 260
		snd.RollOffMinDistance = 30
		snd.Parent = speaker
		snd:Play()
	end
	-- the road surface -- a textured runway, with white lane edge lines down both sides
	local road = block(
		folder,
		Vector3.new(ROAD_W, 1, roadLen),
		CFrame.new(O.X, Y, roadCz),
		Color3.fromRGB(64, 70, 82),
		Enum.Material.SmoothPlastic
	)
	if Config.Models.ChoicesRoadTexture > 0 then
		local tex = Instance.new("Texture")
		tex.Face = Enum.NormalId.Top
		tex.Texture = "rbxassetid://" .. Config.Models.ChoicesRoadTexture
		tex.StudsPerTileU = 24
		tex.StudsPerTileV = 24
		tex.Transparency = 0.25
		tex.Parent = road
	end
	for _, sx in { -(ROAD_W / 2 - 1), ROAD_W / 2 - 1 } do
		block(
			folder,
			Vector3.new(0.5, 0.2, roadLen),
			CFrame.new(O.X + sx, Y + 0.06, roadCz),
			Color3.fromRGB(235, 238, 245),
			Enum.Material.SmoothPlastic
		).CanCollide =
			false
	end
	-- INVISIBLE boundary walls down both edges so you stay on the road and must go through
	-- a gate's doors (can't walk off the side or around the walls). The decorative fence is
	-- non-colliding; these are the real collision.
	for _, sx in { -(ROAD_W / 2 + 0.5), ROAD_W / 2 + 0.5 } do
		block(
			folder,
			Vector3.new(1, 16, roadLen),
			CFrame.new(O.X + sx, Y + 8, roadCz),
			Color3.new(0, 0, 0),
			Enum.Material.SmoothPlastic,
			1
		)
	end
	-- END CAPS so the runway is a sealed box: you can't walk off the front/back onto the grass
	-- (and therefore can't reach/clip the stands, lights, flags). The doors are the only way
	-- forward; the finish teleports you out.
	for _, ez in { z0, z1 } do
		block(
			folder,
			Vector3.new(ROAD_W + 2, 16, 1),
			CFrame.new(O.X, Y + 8, ez),
			Color3.new(0, 0, 0),
			Enum.Material.SmoothPlastic,
			1
		)
	end
	-- center line: a FLAT painted divider (no collision) so you can freely switch lanes
	-- between gates and pick either door, like the video.
	local centerLine = block(
		folder,
		Vector3.new(DIVIDER_W, 0.2, roadLen),
		CFrame.new(O.X, Y + 0.06, roadCz),
		Color3.fromRGB(220, 224, 230),
		Enum.Material.SmoothPlastic
	)
	centerLine.CanCollide = false
	-- yellow lane dashes down each lane
	for zz = z0 + 6, z1 - 6, 12 do
		for _, sx in { -LANE_OFF, LANE_OFF } do
			block(
				folder,
				Vector3.new(1.4, 1.05, 5),
				CFrame.new(O.X + sx, Y + 0.03, zz),
				Color3.fromRGB(232, 196, 54),
				Enum.Material.SmoothPlastic
			)
		end
	end

	-- roadside RACE-TRACK fences (tile the model down both edges; its panel runs along Z, so no
	-- rotation needed). placeAsset grounds + strips each segment.
	local fenceModel = Assets.template(Config.Models.ChoicesRaceFence)
	if fenceModel and fenceModel:IsA("Model") then
		local _, fsize = worldAABB(fenceModel)
		local segLen = math.max(6, fsize.Z)
		local edgeX = ROAD_W / 2 + 1.5
		for zz = z0 + segLen / 2, z1, segLen do
			for _, sx in { -edgeX, edgeX } do
				placeAsset(folder, fenceModel, Vector3.new(O.X + sx, Y, zz), 0, nil, false)
			end
		end
	end

	-- packed grandstands down both sides so you run THROUGH a stadium. Spaced sections along the
	-- GATE stretch only (past the entrance dressing + clear of the finish) so they never crowd
	-- the start flags/lights.
	local standModel = Assets.template(Config.Models.ChoicesGrandstand)
	if standModel and standModel:IsA("Model") then
		buildGrandstands(folder, Y, standModel, O.Z + 70, trophyZ - 50)
	end

	-- START + FINISH checkered lines painted across the runway
	local function checkerLine(zc: number)
		local squares = math.floor(ROAD_W / 1.6)
		local sw = ROAD_W / squares
		for c = 0, squares - 1 do
			block(
				folder,
				Vector3.new(sw, 0.2, 2.4),
				CFrame.new(O.X - ROAD_W / 2 + sw * (c + 0.5), Y + 0.08, zc),
				if c % 2 == 0 then Color3.fromRGB(25, 28, 36) else Color3.fromRGB(240, 242, 248),
				Enum.Material.SmoothPlastic
			).CanCollide =
				false
		end
	end
	checkerLine(O.Z + 24)
	checkerLine(trophyZ - 12)

	-- scattered roadside trees (Forest Pack; scripts stripped, placed on the grass)
	local treeTemplates: { Model } = {}
	do
		local ok, container = pcall(function()
			return InsertService:LoadAsset(Config.Models.GauntletTrees)
		end)
		if ok and container then
			local root = container:FindFirstChildOfClass("Folder") or container
			for _, m in root:GetDescendants() do
				if m:IsA("Model") and m:FindFirstChildWhichIsA("BasePart") then
					-- only UPRIGHT trees (taller than wide) -- skips fallen logs that otherwise
					-- get laid through walls.
					local _, sz = m:GetBoundingBox()
					if sz.Y > sz.X * 1.1 and sz.Y > sz.Z * 1.1 then
						table.insert(treeTemplates, m)
						if #treeTemplates >= 12 then
							break
						end
					end
				end
			end
		end
	end
	local function placeTree(pos: Vector3)
		if #treeTemplates == 0 then
			return
		end
		local t = treeTemplates[math.random(#treeTemplates)]:Clone()
		for _, d in t:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			elseif d:IsA("BaseScript") then
				d:Destroy()
			end
		end
		local _, sz = t:GetBoundingBox()
		if sz.Y > 0 then
			t:ScaleTo(math.clamp(13 / sz.Y, 0.25, 4))
		end
		t:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
		local cf2, sz2 = t:GetBoundingBox()
		-- drop base to ground, then sink ~2.5 studs so trees plant firmly (some tree models have
		-- a bbox that hangs below the visible trunk, which otherwise leaves them floating).
		t:PivotTo(t:GetPivot() + Vector3.new(0, (Y - 2.5) - (cf2.Y - sz2.Y / 2), 0))
		t.Parent = folder
	end
	-- Place trees WELL clear of the road/walls -- at the safe midpoint between two gates
	-- (never near a gate or the banner) and far out past the boundary, so nothing clips
	-- the walls, doors or sign.
	for i = 0, NUM_GATES - 1 do
		local zz = gateZ(i) + GATE_SPACING / 2 -- exactly between gate i and i+1
		-- out PAST the grandstands (which reach ~x50) so trees never clip the stands
		for _, sx in { -(ROAD_W / 2 + 50), ROAD_W / 2 + 50 } do
			if math.random() < 0.7 then
				placeTree(Vector3.new(O.X + sx + math.random(-6, 6), Y, zz))
			end
		end
	end

	-- a football field as a bright backdrop behind the start
	Assets.place(folder, Config.Models.GauntletField, CFrame.new(O.X, Y - 0.5, z0 - 90), nil)

	-- grand START GANTRY arch over the runway (its 50-stud span is along Z, so yaw 90 deg puts it
	-- across the road). Legs land outside the road, so it's decorative (non-colliding).
	local archT = Assets.template(Config.Models.ChoicesStartArch)
	if archT and archT:IsA("Model") then
		placeAsset(folder, archT, Vector3.new(O.X, Y, O.Z + 13), math.pi / 2, nil, false)
	end
	-- Stadium-entrance dressing. Floodlights are set BACK + OUT so they frame the entrance
	-- without crowding the banner arch; flag clusters line the course sides PAST the arch so
	-- they never block the path.
	for _, sx in { -(ROAD_W / 2 + 13), ROAD_W / 2 + 13 } do
		placeDecor(folder, Config.Models.ChoicesFloodlight, CFrame.new(O.X + sx, Y, O.Z - 6), 24)
	end
	-- flag clusters flank the entrance WELL clear of the roadside fence (edge ~13.5): the
	-- cluster models are wide, so at +6 their inner poles were clipping into the fence.
	placeDecor(
		folder,
		Config.Models.ChoicesFlagA,
		CFrame.new(O.X - (ROAD_W / 2 + 17), Y, O.Z + 30),
		11
	)
	placeDecor(
		folder,
		Config.Models.ChoicesFlagB,
		CFrame.new(O.X + (ROAD_W / 2 + 17), Y, O.Z + 30),
		11
	)

	-- start banner arch: a big "WOULD YOU RATHER?" sign you run under
	do
		local signZ = O.Z + 18
		for _, sx in { -(ROAD_W / 2 + 1), ROAD_W / 2 + 1 } do
			block(
				folder,
				Vector3.new(1.6, 16, 1.6),
				CFrame.new(O.X + sx, Y + 8, signZ),
				Color3.fromRGB(230, 180, 40),
				Enum.Material.Neon
			)
		end
		local sign = block(
			folder,
			Vector3.new(ROAD_W + 2, 5, 1),
			CFrame.new(O.X, Y + 14, signZ),
			Color3.fromRGB(18, 22, 34)
		)
		beamPrompt(sign, "🤔 WOULD YOU RATHER?")
	end

	-- ===== gates =====
	type GateRecord = {
		kind: string, -- "dilemma" | "trivia"
		gz: number,
		answered: { [Player]: boolean },
		-- dilemma
		dilemmaId: string?,
		prompt: string?,
		leftText: string,
		rightText: string,
		leftMorph: ChoiceBank.Morph?, -- avatar change if you pick the left door
		rightMorph: ChoiceBank.Morph?,
		leftLegend: string?, -- collection unlock if you pick the left door
		rightLegend: string?,
		leftEffect: ChoiceBank.Effect?, -- weather/speed/size/aura effect of the left door
		rightEffect: ChoiceBank.Effect?,
		-- trivia
		correctLeft: boolean?,
	}
	local gates: { GateRecord } = {}
	-- today's featured "Daily 5" (same for everyone today) -- guaranteed into the run; clearing
	-- all five in one run pays a once-per-day bonus.
	local dailyPack = ChoiceBank.dailyPack(Progression.dayIndex(), 5)
	local dailyIds: { [string]: boolean } = {}
	for _, d in dailyPack do
		dailyIds[d.id] = true
	end
	local dailyTotal = #dailyPack
	-- deal exactly enough for the DILEMMA gates (trivia gates don't use one), so every dilemma
	-- -- including the guaranteed daily 5 -- actually lands on a usable gate.
	local numDilemmaGates = NUM_GATES - math.floor(NUM_GATES / TRIVIA_EVERY)
	local dilemmas = ChoiceBank.deal(numDilemmaGates, dailyPack)
	local dilemmaIdx = 0 -- advances only on dilemma gates (so the daily 5 are never lost to trivia)
	for _, d in dilemmas do
		task.spawn(getVotes, d.id) -- warm the cache so the first splash shows real totals
	end
	local easyPool = TriviaBank.byDifficulty("easy")
	local medPool = TriviaBank.byDifficulty("medium")
	local hardPool = TriviaBank.byDifficulty("hard")

	local function buildGate(i: number): GateRecord
		local gz = gateZ(i)
		local isTrivia = (i % TRIVIA_EVERY == 0)

		-- wall: center pillar + two outer pillars + top beam, leaving a door per lane
		block(
			folder,
			Vector3.new(DIVIDER_W + 2, WALL_H, 1.2),
			CFrame.new(O.X, Y + WALL_H / 2, gz),
			Color3.fromRGB(38, 44, 60)
		)
		for _, sx in { -(ROAD_W / 2 - 0.5), ROAD_W / 2 - 0.5 } do
			block(
				folder,
				Vector3.new(2, WALL_H, 1.2),
				CFrame.new(O.X + sx, Y + WALL_H / 2, gz),
				Color3.fromRGB(38, 44, 60)
			)
		end
		local beam = block(
			folder,
			Vector3.new(ROAD_W, 3.4, 0.6),
			CFrame.new(O.X, Y + WALL_H + 1.4, gz),
			Color3.fromRGB(20, 26, 40),
			Enum.Material.SmoothPlastic
		)

		local doorW = LANE_W - 2.5
		local doorL = block(
			folder,
			Vector3.new(doorW, WALL_H - 2, 0.5),
			CFrame.new(O.X - LANE_OFF, Y + (WALL_H - 2) / 2, gz),
			Color3.fromRGB(150, 200, 255),
			Enum.Material.Glass,
			0.35
		)
		doorL.CanCollide = false
		local doorR = block(
			folder,
			Vector3.new(doorW, WALL_H - 2, 0.5),
			CFrame.new(O.X + LANE_OFF, Y + (WALL_H - 2) / 2, gz),
			Color3.fromRGB(255, 210, 170),
			Enum.Material.Glass,
			0.35
		)
		doorR.CanCollide = false
		-- accent backlight just behind each door so it glows and reads from a distance
		local doorH = WALL_H - 2
		block(
			folder,
			Vector3.new(doorW + 1.2, doorH + 1, 0.3),
			CFrame.new(O.X - LANE_OFF, Y + doorH / 2, gz + 0.45),
			LEFT_ACCENT,
			Enum.Material.Neon,
			0.5
		).CanCollide =
			false
		block(
			folder,
			Vector3.new(doorW + 1.2, doorH + 1, 0.3),
			CFrame.new(O.X + LANE_OFF, Y + doorH / 2, gz + 0.45),
			RIGHT_ACCENT,
			Enum.Material.Neon,
			0.5
		).CanCollide =
			false

		-- Dress each door as a glowing PORTAL: a neon accent frame (jambs + lintel), a light,
		-- a swirl of particles and an accent glow-pad on the floor in front so both choices
		-- read as lit doorways from way down the runway.
		for _, side in { { -LANE_OFF, LEFT_ACCENT }, { LANE_OFF, RIGHT_ACCENT } } do
			local sxoff = side[1] :: number
			local accent = side[2] :: Color3
			local dx = O.X + sxoff
			-- left + right jamb
			for _, jx in { -(doorW / 2 + 0.7), doorW / 2 + 0.7 } do
				block(
					folder,
					Vector3.new(0.7, doorH + 1.4, 0.9),
					CFrame.new(dx + jx, Y + doorH / 2, gz - 0.2),
					accent,
					Enum.Material.Neon
				).CanCollide =
					false
			end
			-- lintel across the top
			block(
				folder,
				Vector3.new(doorW + 2, 0.7, 0.9),
				CFrame.new(dx, Y + doorH + 0.6, gz - 0.2),
				accent,
				Enum.Material.Neon
			).CanCollide =
				false
			-- glow-pad on the floor just in front of the door
			block(
				folder,
				Vector3.new(doorW + 1, 0.1, 4),
				CFrame.new(dx, Y + 0.12, gz - 3),
				accent,
				Enum.Material.Neon,
				0.35
			).CanCollide =
				false
			-- doorway light + a gentle particle shimmer in the opening
			local glow = Instance.new("Part")
			glow.Size = Vector3.new(doorW, doorH, 0.2)
			glow.CFrame = CFrame.new(dx, Y + doorH / 2, gz)
			glow.Anchored = true
			glow.CanCollide = false
			glow.CanQuery = false
			glow.Transparency = 1
			glow.Parent = folder
			local pl = Instance.new("PointLight")
			pl.Color = accent
			pl.Range = 14
			pl.Brightness = 1.4
			pl.Parent = glow
			local shimmer = Instance.new("ParticleEmitter")
			shimmer.Rate = 14
			shimmer.Lifetime = NumberRange.new(0.7, 1.3)
			shimmer.Speed = NumberRange.new(0.4, 1.2)
			shimmer.Size = NumberSequence.new(1.1)
			shimmer.Transparency = NumberSequence.new(0.45)
			shimmer.LightEmission = 1
			shimmer.Color = ColorSequence.new(accent)
			shimmer.Parent = glow
		end

		local rec: GateRecord = {
			kind = if isTrivia then "trivia" else "dilemma",
			gz = gz,
			answered = {},
			leftText = "",
			rightText = "",
		}

		if isTrivia then
			local pool = if i <= NUM_GATES / 3
				then easyPool
				elseif i <= NUM_GATES * 2 / 3 then medPool
				else hardPool
			if #pool == 0 then
				pool = TriviaBank.Questions
			end
			local q = pool[math.random(#pool)]
			local correct = (q.options :: { [string]: string })[q.answer]
			local wrongKeys: { string } = {}
			for _, k in LETTERS do
				if k ~= q.answer then
					table.insert(wrongKeys, k)
				end
			end
			local wrong = (q.options :: { [string]: string })[wrongKeys[math.random(#wrongKeys)]]
			rec.correctLeft = math.random() < 0.5
			rec.prompt = "⚽ " .. q.q
			rec.leftText = if rec.correctLeft then correct else wrong
			rec.rightText = if rec.correctLeft then wrong else correct
			beamPrompt(beam, rec.prompt)
		else
			dilemmaIdx += 1
			local d = dilemmas[dilemmaIdx] or ChoiceBank.Dilemmas[1]
			rec.dilemmaId = d.id
			rec.prompt = "WOULD YOU RATHER…"
			rec.leftText = d.a.text
			rec.rightText = d.b.text
			rec.leftMorph = d.a.morph
			rec.rightMorph = d.b.morph
			rec.leftLegend = d.a.legend
			rec.rightLegend = d.b.legend
			rec.leftEffect = d.a.effect
			rec.rightEffect = d.b.effect
			doorPanel(
				doorL,
				d.a.text,
				d.a.image,
				LEFT_ACCENT,
				effectIcon(d.a.effect, d.a.morph, d.a.legend)
			)
			doorPanel(
				doorR,
				d.b.text,
				d.b.image,
				RIGHT_ACCENT,
				effectIcon(d.b.effect, d.b.morph, d.b.legend)
			)
			beamPrompt(
				beam,
				if dailyIds[d.id]
					then "🗓️ TODAY'S 5 · WOULD YOU RATHER…"
					else "WOULD YOU RATHER…"
			)
		end
		if isTrivia then
			doorPanel(doorL, rec.leftText, nil, LEFT_ACCENT)
			doorPanel(doorR, rec.rightText, nil, RIGHT_ACCENT)
		end

		-- trigger zones just past each door (you "picked" the lane you ran through)
		local function trigger(sx: number, pickedLeft: boolean)
			local zone = block(
				folder,
				Vector3.new(LANE_W, WALL_H, 3),
				CFrame.new(O.X + sx, Y + WALL_H / 2, gz + 2.5),
				Color3.new(1, 1, 1),
				Enum.Material.SmoothPlastic,
				1
			)
			zone.CanCollide = false
			zone.Touched:Connect(function(hit: BasePart)
				local player = playerFromHit(hit)
				if not player or rec.answered[player] then
					return
				end
				rec.answered[player] = true
				-- the door you ran through morphs your avatar + applies its effect
				local morph = if pickedLeft then rec.leftMorph else rec.rightMorph
				local legend = if pickedLeft then rec.leftLegend else rec.rightLegend
				if morph then
					applyMorph(player, morph, legend)
				end
				local effect = if pickedLeft then rec.leftEffect else rec.rightEffect
				if effect then
					applyEffect(player, effect)
				end
				-- "Become a Legend" collection: unlock the legend behind this door (once).
				local rsAny = runState[player]
				if legend and rsAny and DataService.unlockLegend(player, legend) then
					local name = ChoiceBank.Legends[legend] or legend
					table.insert(rsAny.newLegends, name)
					notify(player, string.format("⭐ New legend unlocked: %s!", name))
					-- COLLECTION SET BONUSES: a coin reward each time you cross a milestone.
					local prof = DataService.get(player)
					if prof then
						local n = 0
						for _ in prof.LegendsUnlocked do
							n += 1
						end
						local legTotal = ChoiceBank.legendCount()
						local bonus = if n >= legTotal
							then 1000
							elseif n == 10 then 400
							elseif n == 5 then 200
							else 0
						if bonus > 0 then
							DataService.grantReward(player, bonus, 0)
							notify(
								player,
								string.format(
									"🏅 Collection milestone — %d/%d legends! +%d coins",
									n,
									legTotal,
									bonus
								)
							)
						end
					end
				end
				if rec.kind == "dilemma" and rec.dilemmaId then
					if rsAny and dailyIds[rec.dilemmaId] then
						rsAny.dailyHit[rec.dilemmaId] = true -- toward today's "Daily 5"
					end
					local tally = addVote(rec.dilemmaId, pickedLeft)
					local total = tally.a + tally.b
					local aPct = if total > 0 then math.floor(tally.a / total * 100 + 0.5) else 50
					-- track crowd agreement for the end-of-run personality card
					if rsAny then
						rsAny.dilemmas += 1
						local withCrowd = if pickedLeft
							then tally.a >= tally.b
							else tally.b >= tally.a
						if withCrowd then
							rsAny.agreed += 1
						end
					end
					Net.getEvent(Net.Events.ChoiceResult):FireClient(player, {
						prompt = rec.prompt,
						aText = rec.leftText,
						bText = rec.rightText,
						aPct = aPct,
						bPct = 100 - aPct,
						picked = if pickedLeft then "a" else "b",
						index = i,
						total = NUM_GATES,
					})
				else
					local rs = runState[player]
					local correctSide = rec.correctLeft == true
					local right = pickedLeft == correctSide
					if right then
						local gained = POINTS_CORRECT
						local streak = 1
						if rs then
							rs.streak += 1
							streak = rs.streak
							gained += rs.streak * POINTS_STREAK
							if
								MonetizationService.ownsPass(
									player,
									Config.ParkourBoosts.PointsDoublerPassId
								)
							then
								gained *= Config.ParkourBoosts.PointsMultiplier
							end
							rs.points += gained
						end
						DataService.grantReward(player, REWARD_CORRECT, 0)
						notify(
							player,
							string.format(
								"✅ Correct! +%d pts (🔥 x%d) · +%d coins",
								gained,
								streak,
								REWARD_CORRECT
							)
						)
					else
						if rs then
							rs.streak = 0
						end
						notify(
							player,
							string.format(
								'❌ Not quite — it was "%s". Keep running!',
								if correctSide then rec.leftText else rec.rightText
							)
						)
					end
					Net.getEvent(Net.Events.ChoiceResult):FireClient(player, {
						prompt = rec.prompt,
						aText = rec.leftText,
						bText = rec.rightText,
						aPct = 0,
						bPct = 0,
						picked = if pickedLeft then "a" else "b",
						correct = if correctSide then "a" else "b",
						index = i,
						total = NUM_GATES,
					})
				end
			end)
		end
		trigger(-LANE_OFF, true)
		trigger(LANE_OFF, false)

		return rec
	end

	for i = 1, NUM_GATES do
		gates[i] = buildGate(i)
	end

	-- ===== coin pickups between gates =====
	-- A reward + a breather between choices: a glowing coin sits midway between each pair of gates,
	-- alternating lanes (nudging you to switch sides). Touch grants a few coins once per player per
	-- run -- it varies the rhythm so the runway isn't just choice → choice → choice.
	local COIN_REWARD = 12
	for i = 1, NUM_GATES - 1 do
		local zz = gateZ(i) + GATE_SPACING / 2
		local lane = if i % 2 == 0 then -LANE_OFF else LANE_OFF
		local coin = Instance.new("Part")
		coin.Name = "CoinPickup"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.4, 3, 3)
		coin.Anchored = true
		coin.CanCollide = false
		coin.Material = Enum.Material.Neon
		coin.Color = Color3.fromRGB(255, 205, 60)
		-- the 90° yaw turns the cylinder's flat face toward the approaching runner (who runs +Z)
		coin.CFrame = CFrame.new(O.X + lane, Y + 3.4, zz) * CFrame.Angles(0, math.rad(90), 0)
		coin.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = coin.Color
		light.Range = 7
		light.Brightness = 1.1
		light.Parent = coin
		local aura = Instance.new("ParticleEmitter")
		aura.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140))
		aura.LightEmission = 1
		aura.Rate = 8
		aura.Lifetime = NumberRange.new(0.5, 0.9)
		aura.Speed = NumberRange.new(0.5, 1.5)
		aura.Size = NumberSequence.new(0.8)
		aura.Transparency = NumberSequence.new(0.4)
		aura.Parent = coin
		local ding = Instance.new("Sound")
		ding.SoundId = "rbxassetid://135483737426662"
		ding.Volume = 0.6
		ding.RollOffMaxDistance = 70
		ding.Parent = coin
		local collected: { [Player]: boolean } = {}
		coin.Touched:Connect(function(hit: BasePart)
			local plr = playerFromHit(hit)
			-- NOTE: no runState gate here -- the door triggers don't use one either, and in a solo run
			-- runState may be unset; `collected` already caps it to once per player per coin.
			if not plr or collected[plr] then
				return
			end
			collected[plr] = true
			DataService.grantReward(plr, COIN_REWARD, 0)
			aura:Emit(24) -- a quick sparkle pop on pickup
			ding:Play()
		end)
	end

	-- ===== trophy finish =====
	local podium = block(
		folder,
		Vector3.new(9, 2, 9),
		CFrame.new(O.X, Y + 1, trophyZ),
		Color3.fromRGB(44, 48, 60),
		Enum.Material.Marble
	)
	podium.Shape = Enum.PartType.Cylinder
	podium.CFrame = CFrame.new(O.X, Y + 1, trophyZ) * CFrame.Angles(0, 0, math.rad(90))
	Assets.place(folder, Config.Models.Trophy, CFrame.new(O.X, Y + 2, trophyZ), 6)
	-- finish arch: the real archway gate model you run through (procedural fallback if it
	-- can't load). Sits just before the podium so you pass under it to the trophy.
	local endArch =
		placeDecor(folder, Config.Models.ChoicesEndArch, CFrame.new(O.X, Y, trophyZ - 6), 16)
	if not endArch then
		for _, sx in { -7, 7 } do
			block(
				folder,
				Vector3.new(1.6, 14, 1.6),
				CFrame.new(O.X + sx, Y + 7, trophyZ - 6),
				Color3.fromRGB(230, 180, 40),
				Enum.Material.Neon
			)
		end
		block(
			folder,
			Vector3.new(16, 1.6, 1.6),
			CFrame.new(O.X, Y + 14, trophyZ - 6),
			Color3.fromRGB(230, 180, 40),
			Enum.Material.Neon
		)
	end
	-- festive confetti raining over the trophy
	placeDecor(folder, Config.Models.ChoicesConfetti, CFrame.new(O.X, Y + 9, trophyZ), nil)
	-- stadium floodlights flanking the finish (out + behind the trophy, clear of the arch)
	for _, sx in { -(ROAD_W / 2 + 13), ROAD_W / 2 + 13 } do
		placeDecor(
			folder,
			Config.Models.ChoicesFloodlight,
			CFrame.new(O.X + sx, Y, trophyZ + 6),
			24
		)
	end
	local trophyTrigger = block(
		folder,
		Vector3.new(ROAD_W, 12, 6),
		CFrame.new(O.X, Y + 6, trophyZ - 5),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		1
	)
	trophyTrigger.CanCollide = false

	-- ===== hub portal plaza: a raised dais + a real portal frame you walk up to =====
	local portalAnchor = MapLayout.choices() or MapLayout.activityCenter()
	local pcBase = ground(if portalAnchor then portalAnchor.Position else O)
	local look = if portalAnchor then portalAnchor.LookVector else Vector3.new(0, 0, 1)
	look = Vector3.new(look.X, 0, look.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, 1)
	local right = look:Cross(Vector3.yAxis)

	-- a raised dais with a glowing top, so the portal reads as a destination
	block(
		folder,
		Vector3.new(30, 1.6, 30),
		CFrame.new(pcBase + Vector3.new(0, 0.8, 0)),
		Color3.fromRGB(40, 34, 64),
		Enum.Material.Marble
	)
	-- matte surface to stand on + a thin neon TRIM ring around the edge (not a big glare disc)
	local daisTop = block(
		folder,
		Vector3.new(26, 0.4, 26),
		CFrame.new(pcBase + Vector3.new(0, 1.72, 0)),
		Color3.fromRGB(48, 42, 74),
		Enum.Material.SmoothPlastic
	)
	daisTop.CanCollide = false
	local daisTrim = block(
		folder,
		Vector3.new(30, 0.5, 30),
		CFrame.new(pcBase + Vector3.new(0, 1.66, 0)),
		Color3.fromRGB(150, 110, 240),
		Enum.Material.Neon,
		0.25
	)
	daisTrim.CanCollide = false

	-- a medieval arch that FRAMES the portal: same spot, a touch bigger, same facing, so the
	-- portal frame nests inside its opening (concentric, not two structures in a line).
	placeModelFitted(
		folder,
		Config.Models.ChoicesEntranceGate,
		CFrame.new(pcBase + Vector3.new(0, 1.9, 0)),
		19,
		look
	)
	placePortalFrame(folder, pcBase + Vector3.new(0, 1.9, 0), look, 14)

	-- the glowing vortex surface inside the frame (also the prompt holder)
	local portalMid = pcBase + Vector3.new(0, 9, 0)
	local portal = block(
		folder,
		Vector3.new(9.5, 13, 0.4),
		CFrame.lookAt(portalMid, portalMid + look),
		Color3.fromRGB(150, 90, 255),
		Enum.Material.Neon,
		0.3
	)
	portal.CanCollide = false
	local swirl = Instance.new("ParticleEmitter")
	swirl.Rate = 36
	swirl.Lifetime = NumberRange.new(0.6, 1.1)
	swirl.Speed = NumberRange.new(0)
	swirl.RotSpeed = NumberRange.new(140)
	swirl.Size = NumberSequence.new(1.7)
	swirl.Color = ColorSequence.new(Color3.fromRGB(200, 140, 255), Color3.fromRGB(120, 70, 220))
	swirl.LightEmission = 1
	swirl.Parent = portal
	local portalLight = Instance.new("PointLight")
	portalLight.Color = Color3.fromRGB(150, 90, 255)
	portalLight.Range = 12 -- small + dim so it glows the frame, not the whole plaza pink
	portalLight.Brightness = 1
	portalLight.Parent = portal
	local portalBb = Instance.new("BillboardGui")
	portalBb.Size = UDim2.fromScale(9, 2.6)
	portalBb.StudsOffset = Vector3.new(0, 7, 0)
	portalBb.AlwaysOnTop = false
	portalBb.MaxDistance = 90
	portalBb.Adornee = portal
	portalBb.Parent = portal
	local portalLabel = Instance.new("TextLabel")
	portalLabel.Size = UDim2.fromScale(1, 1)
	portalLabel.BackgroundTransparency = 1
	portalLabel.Font = Enum.Font.GothamBlack
	portalLabel.TextScaled = true
	portalLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	portalLabel.TextStrokeTransparency = 0.3
	portalLabel.Text = "🤔 WOULD YOU RATHER?"
	portalLabel.Parent = portalBb

	-- BEACON: a tall glowing pillar of light + a high floating sign so the portal is visible from
	-- across the hub (the #1 first-session fix -- players couldn't find this mode).
	local beacon = block(
		folder,
		Vector3.new(2.5, 80, 2.5),
		CFrame.new(pcBase + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(150, 90, 255),
		Enum.Material.Neon,
		0.55
	)
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.Shape = Enum.PartType.Cylinder
	local beaconTop = block(
		folder,
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(pcBase + Vector3.new(0, 34, 0)),
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic,
		1
	)
	beaconTop.CanCollide = false
	beaconTop.CanQuery = false
	local skyBb = Instance.new("BillboardGui")
	skyBb.Size = UDim2.fromScale(22, 5)
	skyBb.AlwaysOnTop = false
	skyBb.MaxDistance = 600 -- visible from across the whole hub
	skyBb.Adornee = beaconTop
	skyBb.Parent = beaconTop
	local skyLabel = Instance.new("TextLabel")
	skyLabel.Size = UDim2.fromScale(1, 1)
	skyLabel.BackgroundTransparency = 1
	skyLabel.Font = Enum.Font.GothamBlack
	skyLabel.TextScaled = true
	skyLabel.TextColor3 = Color3.fromRGB(255, 235, 150)
	skyLabel.TextStrokeTransparency = 0.2
	skyLabel.Text = "🤔 WOULD YOU RATHER?\n▼ PLAY HERE ▼"
	skyLabel.Parent = skyBb

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Run the Choices"
	prompt.ObjectText = "🤔 Would You Rather"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = portal
	local function launchRun(player: Player)
		local rsNew: RunState = {
			points = 0,
			streak = 0,
			startedAt = os.clock(),
			agreed = 0,
			dilemmas = 0,
			newLegends = {},
			friend = false,
			dailyHit = {},
		}
		runState[player] = rsNew
		-- Play-with-friends bonus (the 3x-retention lever): if a friend is in the server when
		-- you start, your finish pays extra. IsFriendsWith yields, so check off-thread.
		task.spawn(function()
			for _, other in Players:GetPlayers() do
				if other ~= player then
					local ok, isFriend = pcall(function()
						return player:IsFriendsWith(other.UserId)
					end)
					if ok and isFriend then
						rsNew.friend = true
						notify(
							player,
							"👥 Friend in the server — you'll earn a bonus this run!"
						)
						break
					end
				end
			end
		end)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			local speed = RUN_SPEED
			if MonetizationService.ownsPass(player, Config.ParkourBoosts.SpeedPassId) then
				speed = math.max(speed, Config.ParkourBoosts.BoostWalkSpeed)
			end
			(hum :: Humanoid).WalkSpeed = speed
		end
		-- cosmetic trail perk
		local trailId = Config.ParkourBoosts.TrailPassId
		if trailId > 0 and MonetizationService.ownsPass(player, trailId) then
			attachTrail(player)
		end
		-- EARNED cosmetic aura: wear your rarest unlocked aura for the run
		local prof = DataService.get(player)
		if prof then
			local best: string? = nil
			for _, k in AURA_PRIORITY do
				if prof.ChoicesAurasOwned[k] then
					best = k
					break
				end
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if best and root and root:IsA("BasePart") then
				attachAura(root, best, "ChoicesCosmeticAura")
			end
		end
		teleport(player, startCF)
		-- clean the screen (hide the penalty-game HUD) + send the course so the client can
		-- frame/zoom the doors you're approaching.
		Net.getEvent(Net.Events.ChoicesMode):FireClient(player, { active = true })
		-- Sneak Peek perk: owners get each dilemma's current global vote % in the manifest,
		-- so the client can reveal it BEFORE they choose.
		local peekId = Config.ParkourBoosts.SneakPeekPassId
		local peek = peekId > 0 and MonetizationService.ownsPass(player, peekId)
		local manifest = {}
		for _, g in gates do
			local row: any = { z = g.gz, prompt = g.prompt, a = g.leftText, b = g.rightText }
			if peek and g.dilemmaId then
				local v = getVotes(g.dilemmaId)
				local total = v.a + v.b
				row.aPct = if total > 0 then math.floor(v.a / total * 100 + 0.5) else 50
				row.bPct = 100 - row.aPct
			end
			table.insert(manifest, row)
		end
		Net.getEvent(Net.Events.ChoicesCourse):FireClient(player, { gates = manifest })
		notify(
			player,
			"🤔 Pick your doors! No wrong answers — watch for ⚽ World Cup gates, and clear the 🗓️ Daily 5 for a bonus."
		)
	end

	-- ===== shared HEATS: joining opens a short countdown others can join, then everyone launches
	-- TOGETHER, so groups witness each other transform at every door (the social/viral hook). =====
	local HEAT_COUNTDOWN = 6
	local heatJoined: { [Player]: boolean } = {}
	local heatCounting = false
	local heatBb = Instance.new("BillboardGui")
	heatBb.Size = UDim2.fromScale(8.5, 1.5)
	heatBb.StudsOffset = Vector3.new(0, 10.5, 0)
	heatBb.MaxDistance = 90
	heatBb.Adornee = portal
	heatBb.Enabled = false
	heatBb.Parent = portal
	local heatLbl = Instance.new("TextLabel")
	heatLbl.Size = UDim2.fromScale(1, 1)
	heatLbl.BackgroundTransparency = 1
	heatLbl.Font = Enum.Font.GothamBlack
	heatLbl.TextScaled = true
	heatLbl.TextColor3 = Color3.fromRGB(120, 255, 170)
	heatLbl.TextStrokeTransparency = 0.3
	heatLbl.Parent = heatBb

	local function startHeat()
		if heatCounting then
			return
		end
		heatCounting = true
		heatBb.Enabled = true
		task.spawn(function()
			for t = HEAT_COUNTDOWN, 1, -1 do
				local ready = 0
				for p in heatJoined do
					if p.Parent then
						ready += 1
					end
				end
				heatLbl.Text = string.format("🏁 Heat starts in %d  ·  %d ready", t, ready)
				task.wait(1)
			end
			local toLaunch: { Player } = {}
			for p in heatJoined do
				if p.Parent and not runState[p] then
					table.insert(toLaunch, p)
				end
			end
			heatJoined = {}
			heatCounting = false
			heatBb.Enabled = false
			for _, p in toLaunch do
				launchRun(p)
			end
		end)
	end

	prompt.Triggered:Connect(function(player: Player)
		if runState[player] or heatJoined[player] then
			return -- already running, or already in the next heat
		end
		heatJoined[player] = true
		notify(player, "🏁 You're in the next heat — line up with the others!")
		startHeat()
	end)

	-- ===== red carpet + VIP ropes + perk pedestals leading up to the portal =====
	do
		-- a red carpet from the approach side up to the dais
		local carpetLen = 28
		local carpetCenter = pcBase + look * (16 + carpetLen / 2)
		local carpet = block(
			folder,
			Vector3.new(8, 0.2, carpetLen),
			CFrame.lookAt(carpetCenter + Vector3.new(0, 0.12, 0), carpetCenter + look),
			Color3.fromRGB(150, 28, 38),
			Enum.Material.Fabric
		)
		carpet.CanCollide = false
		-- VIP rope barriers down both sides of the carpet (facing along it)
		for d = 5, carpetLen - 2, 8 do
			local p = pcBase + look * (16 + d)
			placeModelFitted(folder, Config.Models.ChoicesRope, CFrame.new(p - right * 5), 4, look)
			placeModelFitted(folder, Config.Models.ChoicesRope, CFrame.new(p + right * 5), 4, look)
		end

		-- perk pedestals (the gamepass shop) in a row in front of the dais, flanking the carpet
		local rowAt = pcBase + look * 13
		local function perkPedestal(slot: number, title: string, passId: number, color: Color3)
			local pos = rowAt + right * slot
			-- the Statue Stand is wide + low, so scale to a small height -> a tidy ~6-wide plinth
			local ped =
				placeModelFitted(folder, Config.Models.ChoicesPedestal, CFrame.new(pos), 1.8, nil)
			-- sit the glowing cap on the pedestal's ACTUAL top (so it never floats)
			local topY = pos.Y + 1.8
			if ped then
				local bcf, sz = ped:GetBoundingBox()
				topY = bcf.Position.Y + sz.Y / 2
			end
			local cap = block(
				folder,
				Vector3.new(2.6, 0.5, 2.6),
				CFrame.new(Vector3.new(pos.X, topY + 0.25, pos.Z)),
				color,
				Enum.Material.Neon
			)
			cap.CanCollide = false
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromScale(4.5, 1.6)
			bb.StudsOffset = Vector3.new(0, 2.2, 0)
			bb.MaxDistance = 50
			bb.Adornee = cap
			bb.Parent = cap
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.TextColor3 = Color3.fromRGB(255, 255, 255)
			t.TextStrokeTransparency = 0.4
			t.Text = title .. (if passId > 0 then "" else "\n(soon)")
			t.Parent = bb
			local buyPrompt = Instance.new("ProximityPrompt")
			buyPrompt.ActionText = "Buy"
			buyPrompt.ObjectText = title
			buyPrompt.MaxActivationDistance = 9
			buyPrompt.RequiresLineOfSight = false
			buyPrompt.Parent = cap
			buyPrompt.Triggered:Connect(function(player: Player)
				if passId > 0 then
					MarketplaceService:PromptGamePassPurchase(player, passId)
				else
					notify(player, "💎 " .. title .. " — coming soon!")
				end
			end)
		end
		perkPedestal(
			-19,
			"⚡ Speed",
			Config.ParkourBoosts.SpeedPassId,
			Color3.fromRGB(60, 150, 230)
		)
		perkPedestal(
			-13,
			"✖️2 Pts",
			Config.ParkourBoosts.PointsDoublerPassId,
			Color3.fromRGB(230, 170, 50)
		)
		perkPedestal(
			-7,
			"👀 Peek",
			Config.ParkourBoosts.SneakPeekPassId,
			Color3.fromRGB(150, 90, 230)
		)
		perkPedestal(7, "✨ Trail", Config.ParkourBoosts.TrailPassId, Color3.fromRGB(230, 90, 140))
		-- the main-store gamepasses, reachable from the plaza too
		perkPedestal(
			13,
			"🪙 2× Coins",
			Config.Monetization.CoinDoublerGamepassId,
			Color3.fromRGB(240, 200, 60)
		)
		perkPedestal(
			19,
			"🎟️ Season Pass",
			Config.Monetization.SeasonPassId,
			Color3.fromRGB(120, 220, 255)
		)

		-- "CHOICES PERKS" header floating over the row
		local headerAnchor = block(
			folder,
			Vector3.new(0.2, 0.2, 0.2),
			CFrame.new(pcBase + look * 13 + Vector3.new(0, 8.5, 0)),
			Color3.new(0, 0, 0),
			Enum.Material.SmoothPlastic,
			1
		)
		headerAnchor.CanCollide = false
		local headerBb = Instance.new("BillboardGui")
		headerBb.Size = UDim2.fromScale(9, 1.4)
		headerBb.MaxDistance = 70
		headerBb.Adornee = headerAnchor
		headerBb.Parent = headerAnchor
		local headerTxt = Instance.new("TextLabel")
		headerTxt.Size = UDim2.fromScale(1, 1)
		headerTxt.BackgroundTransparency = 1
		headerTxt.Font = Enum.Font.GothamBlack
		headerTxt.TextScaled = true
		headerTxt.TextColor3 = Color3.fromRGB(255, 235, 150)
		headerTxt.TextStrokeTransparency = 0.4
		headerTxt.Text = "💎 CHOICES PERKS"
		headerTxt.Parent = headerBb
	end

	-- ===== Warm-Up Zone: treadmills lined up in the plaza where the photo booth was =====
	-- (the photo booth is gated off in HubService.) Placed along the plaza ROW LINE, all
	-- facing the pitch like the other plaza props. Wormhole dropped (off-theme).
	do
		local photoCF = MapLayout.plaza("photo")
		if photoCF then
			local zb = ground(photoCF.Position)
			local face = photoCF.LookVector
			face = Vector3.new(face.X, 0, face.Z)
			face = if face.Magnitude > 0.01 then face.Unit else Vector3.new(0, 0, 1)
			local along = photoCF.RightVector
			along = Vector3.new(along.X, 0, along.Z)
			along = if along.Magnitude > 0.01 then along.Unit else Vector3.new(1, 0, 0)

			-- gym FLOOR: a dark charcoal platform with a thin CYAN neon trim FRAME around the
			-- edge (4 raised strips, not a full slab -> no z-fighting, cleaner colour).
			local floorCtr = zb + face * -1
			block(
				folder,
				Vector3.new(46, 0.5, 26),
				CFrame.lookAt(
					floorCtr + Vector3.new(0, -0.1, 0),
					floorCtr + Vector3.new(0, -0.1, 0) + face
				),
				Color3.fromRGB(34, 36, 44),
				Enum.Material.Concrete
			)
			local trimColor = Color3.fromRGB(70, 200, 235)
			for _, s in { 13, -13 } do -- front + back edge (span the width)
				local c = floorCtr + face * s + Vector3.new(0, 0.45, 0)
				block(
					folder,
					Vector3.new(46, 0.4, 0.8),
					CFrame.lookAt(c, c + face),
					trimColor,
					Enum.Material.Neon,
					0.2
				).CanCollide =
					false
			end
			for _, s in { 23, -23 } do -- left + right edge (span the depth)
				local c = floorCtr + along * s + Vector3.new(0, 0.45, 0)
				block(
					folder,
					Vector3.new(26, 0.4, 0.8),
					CFrame.lookAt(c, c + along),
					trimColor,
					Enum.Material.Neon,
					0.2
				).CanCollide =
					false
			end

			-- back WALL (tall, so the sign sits ABOVE the ~11-stud machines), facing the pitch.
			local wallMid = zb - face * 13 + Vector3.new(0, 9, 0)
			local wall = block(
				folder,
				Vector3.new(46, 18, 1),
				CFrame.lookAt(wallMid, wallMid + face),
				Color3.fromRGB(28, 32, 44),
				Enum.Material.SmoothPlastic
			)
			local wallSg = Instance.new("SurfaceGui")
			wallSg.Face = Enum.NormalId.Front
			wallSg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			wallSg.PixelsPerStud = 40
			wallSg.Parent = wall
			local wtitle = Instance.new("TextLabel")
			wtitle.Size = UDim2.fromScale(0.96, 0.3) -- top third -> clears the machines
			wtitle.Position = UDim2.fromScale(0.02, 0.04)
			wtitle.BackgroundTransparency = 1
			wtitle.Font = Enum.Font.GothamBlack
			wtitle.TextScaled = true
			wtitle.TextColor3 = Color3.fromRGB(90, 215, 245)
			wtitle.TextStrokeTransparency = 0.4
			wtitle.Text = "🏋️ TRAINING ZONE"
			wtitle.Parent = wallSg

			-- one short "how it works" subtitle ON the wall (upper area, clears the machines) --
			-- replaces the separate floating banner.
			local wsub = Instance.new("TextLabel")
			wsub.Size = UDim2.fromScale(0.96, 0.12)
			wsub.Position = UDim2.fromScale(0.02, 0.34)
			wsub.BackgroundTransparency = 1
			wsub.Font = Enum.Font.GothamBold
			wsub.TextScaled = true
			wsub.TextColor3 = Color3.fromRGB(210, 230, 240)
			wsub.TextStrokeTransparency = 0.4
			wsub.Text = "Stand on a treadmill to earn coins + XP"
			wsub.Parent = wallSg
			-- a flag banner each side of the wall
			placeModelFitted(
				folder,
				Config.Models.ChoicesFlagA,
				CFrame.new(zb - face * 12 - along * 21),
				10,
				face
			)
			placeModelFitted(
				folder,
				Config.Models.ChoicesFlagA,
				CFrame.new(zb - face * 12 + along * 21),
				10,
				face
			)

			-- three treadmills in a line. NOT solid -- you need to be able to step onto them;
			-- the solid floor under them is what you stand on. (Obstacle props below ARE solid.)
			placeModelFitted(
				folder,
				Config.Models.ChoicesTreadmillA,
				CFrame.new(zb - along * 9),
				6,
				face
			)
			placeModelFitted(folder, Config.Models.ChoicesTreadmillA, CFrame.new(zb), 6, face)
			placeModelFitted(
				folder,
				Config.Models.ChoicesTreadmillA,
				CFrame.new(zb + along * 9),
				6,
				face
			)
			-- the glowing "stand here" pad on each treadmill -> earns while you stand on it.
			for _, slot in { -9, 0, 9 } do
				local padPos = zb + along * slot + face * 1.5
				TreadmillService.registerZone(padPos, 3.2)
				local pad = block(
					folder,
					Vector3.new(4, 0.2, 5),
					CFrame.new(padPos + Vector3.new(0, 0.2, 0)),
					Color3.fromRGB(90, 210, 235),
					Enum.Material.Neon,
					0.45
				)
				pad.CanCollide = false
			end
			-- gym props dressing the zone (placed on the platform around the treadmills)
			placeModelFitted(
				folder,
				Config.Models.GymDumbbell,
				CFrame.new(zb - face * 9 - along * 15),
				5,
				face,
				true
			)
			placeModelFitted(
				folder,
				Config.Models.GymBench,
				CFrame.new(zb - face * 8 + along * 14),
				4,
				-along,
				true
			)
			placeModelFitted(
				folder,
				Config.Models.GymMat,
				CFrame.new(zb - face * 8 + along * 14),
				nil,
				face
			)
			placeModelFitted(
				folder,
				Config.Models.GymWaterCooler,
				CFrame.new(zb + face * 8 - along * 17),
				7,
				face,
				true
			)

			-- Energy Drink VENDING MACHINE (dev-product purchase) at the front-right corner
			local vend = placeModelFitted(
				folder,
				Config.Models.GymVending,
				CFrame.new(zb + face * 8 + along * 17),
				8,
				face,
				true
			)
			local vendPart = vend
				and (vend.PrimaryPart or vend:FindFirstChildWhichIsA("BasePart", true))
			if vendPart then
				local fbb = Instance.new("BillboardGui")
				fbb.Size = UDim2.fromScale(5, 1.6)
				fbb.StudsOffset = Vector3.new(0, 6, 0)
				fbb.MaxDistance = 45
				fbb.Adornee = vendPart
				fbb.Parent = vendPart
				local ftx = Instance.new("TextLabel")
				ftx.Size = UDim2.fromScale(1, 1)
				ftx.BackgroundTransparency = 1
				ftx.Font = Enum.Font.GothamBold
				ftx.TextScaled = true
				ftx.TextColor3 = Color3.fromRGB(255, 255, 255)
				ftx.TextStrokeTransparency = 0.4
				ftx.Text = "⚡ Energy Drink"
					.. (if Config.Treadmill.EnergyProductId > 0 then "" else "\n(soon)")
				ftx.Parent = fbb
				local ep = Instance.new("ProximityPrompt")
				ep.ActionText = "Buy"
				ep.ObjectText = "⚡ Energy Drink"
				ep.MaxActivationDistance = 9
				ep.RequiresLineOfSight = false
				ep.Parent = vendPart
				ep.Triggered:Connect(function(player: Player)
					if Config.Treadmill.EnergyProductId > 0 then
						MarketplaceService:PromptProductPurchase(
							player,
							Config.Treadmill.EnergyProductId
						)
					else
						notify(player, "⚡ Energy Drink — coming soon!")
					end
				end)
			end
		end
	end

	-- ===== leaderboard (best run points) =====
	local boardPart = block(
		folder,
		Vector3.new(15, 9, 0.5),
		CFrame.lookAt(
			Vector3.new(O.X - ROAD_W / 2 - 6, Y + 6, O.Z + 9),
			Vector3.new(O.X, Y + 6, O.Z + 9)
		),
		Color3.fromRGB(10, 14, 24)
	)
	local boardSg = Instance.new("SurfaceGui")
	boardSg.Face = Enum.NormalId.Front
	boardSg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	boardSg.PixelsPerStud = 48
	boardSg.Parent = boardPart
	local boardTitle = Instance.new("TextLabel")
	boardTitle.Size = UDim2.fromScale(1, 0.16)
	boardTitle.BackgroundColor3 = Color3.fromRGB(230, 180, 40)
	boardTitle.BorderSizePixel = 0
	boardTitle.Font = Enum.Font.GothamBlack
	boardTitle.TextScaled = true
	boardTitle.TextColor3 = Color3.fromRGB(20, 20, 28)
	boardTitle.Text = "🏆 TOP CHOICES SCORES"
	boardTitle.Parent = boardSg
	local boardRows = Instance.new("Frame")
	boardRows.Size = UDim2.fromScale(0.96, 0.8)
	boardRows.Position = UDim2.fromScale(0.02, 0.18)
	boardRows.BackgroundTransparency = 1
	boardRows.Parent = boardSg
	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 4)
	boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardLayout.Parent = boardRows

	local function refreshBoard()
		if not parkourStore then
			return
		end
		local store = parkourStore :: OrderedDataStore
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, BOARD_TOP_N)
		end)
		if not ok then
			return
		end
		local ok2, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not ok2 then
			return
		end
		for _, c in boardRows:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local rank = 0
		for _, item in page do
			rank += 1
			local uid = tonumber(item.key)
			if uid then
				local row = Instance.new("TextLabel")
				row.Size = UDim2.new(1, 0, 0, 40)
				row.BackgroundTransparency = 1
				row.Font = Enum.Font.GothamBold
				row.TextScaled = true
				row.TextXAlignment = Enum.TextXAlignment.Left
				row.TextColor3 = if rank == 1
					then Color3.fromRGB(255, 220, 90)
					else Color3.fromRGB(235, 235, 245)
				row.Text = string.format(
					"  %d.  %s  —  %s pts",
					rank,
					resolveName(uid),
					tostring(item.value)
				)
				row.LayoutOrder = rank
				row.Parent = boardRows
			end
		end
	end

	local function submitScore(player: Player, points: number)
		if parkourStore then
			local store = parkourStore :: OrderedDataStore
			pcall(function()
				store:UpdateAsync(tostring(player.UserId), function(old: number?)
					return math.max(old or 0, points)
				end)
			end)
		end
		task.spawn(refreshBoard)
	end

	task.spawn(refreshBoard)
	task.spawn(function()
		while true do
			task.wait(BOARD_REFRESH)
			refreshBoard()
		end
	end)

	-- ===== Hot Takes board: global vote splits + Choice of the Day =====
	-- Warm the cache for EVERY dilemma so the board reflects global data, not just this run.
	for _, d in ChoiceBank.Dilemmas do
		task.spawn(getVotes, d.id)
	end
	local htPart = block(
		folder,
		Vector3.new(15, 9, 0.5),
		CFrame.lookAt(
			Vector3.new(O.X + ROAD_W / 2 + 6, Y + 6, O.Z + 9),
			Vector3.new(O.X, Y + 6, O.Z + 9)
		),
		Color3.fromRGB(26, 12, 16)
	)
	local htSg = Instance.new("SurfaceGui")
	htSg.Face = Enum.NormalId.Front
	htSg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	htSg.PixelsPerStud = 48
	htSg.Parent = htPart
	local htTitle = Instance.new("TextLabel")
	htTitle.Size = UDim2.fromScale(1, 0.16)
	htTitle.BackgroundColor3 = Color3.fromRGB(220, 70, 60)
	htTitle.BorderSizePixel = 0
	htTitle.Font = Enum.Font.GothamBlack
	htTitle.TextScaled = true
	htTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	htTitle.Text = "🔥 GLOBAL HOT TAKES"
	htTitle.Parent = htSg
	local htRows = Instance.new("Frame")
	htRows.Size = UDim2.fromScale(0.96, 0.8)
	htRows.Position = UDim2.fromScale(0.02, 0.18)
	htRows.BackgroundTransparency = 1
	htRows.Parent = htSg
	local htLayout = Instance.new("UIListLayout")
	htLayout.Padding = UDim.new(0, 4)
	htLayout.SortOrder = Enum.SortOrder.LayoutOrder
	htLayout.Parent = htRows

	local function refreshHotTakes()
		for _, c in htRows:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local order = 0
		local function addRow(text: string, color: Color3, bg: Color3?)
			order += 1
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 38)
			row.BackgroundColor3 = bg or Color3.fromRGB(0, 0, 0)
			row.BackgroundTransparency = if bg then 0.2 else 1
			row.BorderSizePixel = 0
			row.Font = Enum.Font.GothamBold
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = color
			row.Text = "  " .. text
			row.LayoutOrder = order
			row.Parent = htRows
		end

		-- Choice of the Day (deterministic daily pick, same for everyone today)
		local cotd = ChoiceBank.Dilemmas[(Progression.dayIndex() % #ChoiceBank.Dilemmas) + 1]
		local cv = getVotes(cotd.id)
		local cTotal = cv.a + cv.b
		local cPct = if cTotal > 0 then math.floor(cv.a / cTotal * 100 + 0.5) else 50
		addRow("⭐ CHOICE OF THE DAY", Color3.fromRGB(255, 225, 120), Color3.fromRGB(60, 40, 20))
		addRow(
			string.format("%s  %d%% / %d%%  %s", cotd.a.text, cPct, 100 - cPct, cotd.b.text),
			Color3.fromRGB(255, 245, 200)
		)

		-- the closest-to-50/50 dilemmas globally (the genuinely divisive ones)
		type Ranked = { d: ChoiceBank.Dilemma, aPct: number, close: number }
		local ranked: { Ranked } = {}
		for _, d in ChoiceBank.Dilemmas do
			local v = getVotes(d.id)
			local total = v.a + v.b
			if total >= 4 then
				local aPct = math.floor(v.a / total * 100 + 0.5)
				table.insert(ranked, { d = d, aPct = aPct, close = math.abs(aPct - 50) })
			end
		end
		table.sort(ranked, function(x, y)
			return x.close < y.close
		end)
		if #ranked == 0 then
			addRow("Start picking — splits appear as people vote!", Color3.fromRGB(170, 178, 195))
		else
			for i = 1, math.min(6, #ranked) do
				local r = ranked[i]
				addRow(
					string.format(
						"%s  %d%% / %d%%  %s",
						r.d.a.text,
						r.aPct,
						100 - r.aPct,
						r.d.b.text
					),
					Color3.fromRGB(235, 235, 245)
				)
			end
		end
	end

	task.spawn(function()
		task.wait(2) -- let the warming GetAsyncs land first
		refreshHotTakes()
		while true do
			task.wait(BOARD_REFRESH)
			refreshHotTakes()
		end
	end)

	-- ===== trophy finish =====
	trophyTrigger.Touched:Connect(function(hit: BasePart)
		local player = playerFromHit(hit)
		if not player or finishing[player] then
			return
		end
		finishing[player] = true
		local rs = runState[player]
		local elapsed = if rs then os.clock() - rs.startedAt else 0
		local speedBonus = math.max(0, math.floor((TARGET_TIME - elapsed) * 5))
		local total = (if rs then rs.points else 0) + POINTS_FINISH + speedBonus
		local agreed = if rs then rs.agreed else 0
		local dilemmasAnswered = if rs then rs.dilemmas else 0
		local newLegends = if rs then rs.newLegends else {}
		local hadFriend = if rs then rs.friend else false
		local dailyCleared = 0
		if rs then
			for _ in rs.dailyHit do
				dailyCleared += 1
			end
		end
		runState[player] = nil
		DataService.grantReward(player, REWARD_FINISH, XP_FINISH)
		DataService.grantPack(player, 1) -- a card pack for finishing a run
		submitScore(player, total)
		-- once-per-day "finished a run" bonus
		local dailyBonus = DataService.claimChoicesDaily(player)
		if dailyBonus > 0 then
			notify(player, string.format("📅 Daily Choices bonus — +%d coins!", dailyBonus))
		end
		-- "Daily 5" completion bonus: cleared all of today's featured dilemmas this run
		if dailyTotal > 0 and dailyCleared >= dailyTotal then
			local packBonus = DataService.claimChoicesPack(player)
			if packBonus > 0 then
				notify(player, string.format("🗓️ Daily 5 complete — +%d coins!", packBonus))
			end
		end
		-- play-with-friends bonus
		if hadFriend then
			DataService.grantReward(player, FRIEND_BONUS, 0)
			notify(player, string.format("👥 Friend bonus — +%d coins!", FRIEND_BONUS))
		end
		notify(
			player,
			string.format(
				"🏆 FINISH! %d pts · ⏱️ %ds · +%d coins, +%d XP",
				total,
				math.floor(elapsed),
				REWARD_FINISH,
				XP_FINISH
			)
		)
		-- the shareable end-of-run personality card + collection progress
		local profile = DataService.get(player)
		local unlocked = 0
		if profile then
			for _ in profile.LegendsUnlocked do
				unlocked += 1
			end
		end
		-- earned cosmetic auras unlock as your legend collection grows
		for _, u in AURA_UNLOCKS do
			if unlocked >= u.at and DataService.unlockChoicesAura(player, u.key) then
				notify(player, string.format("%s unlocked — wear it on your next run!", u.label))
			end
		end
		-- a punchy, shareable TITLE earned from how you ran (identity beats a raw score)
		local ratio = if dilemmasAnswered > 0 then agreed / dilemmasAnswered else 0.5
		local title
		if unlocked >= ChoiceBank.legendCount() then
			title = "👑 Legend Collector"
		elseif #newLegends >= 3 then
			title = "🌟 Legend Hunter"
		elseif total >= 2500 then
			title = "🏆 Champion"
		elseif dilemmasAnswered >= 4 and ratio >= 0.8 then
			title = "🐑 The Loyalist"
		elseif dilemmasAnswered >= 4 and ratio <= 0.3 then
			title = "🔥 The Rebel"
		else
			title = "🎲 The Wildcard"
		end
		Net.getEvent(Net.Events.ChoicesSummary):FireClient(player, {
			agreed = agreed,
			dilemmas = dilemmasAnswered,
			points = total,
			legendsUnlocked = unlocked,
			legendsTotal = ChoiceBank.legendCount(),
			newLegends = newLegends,
			title = title,
		})
		-- milestone badges (dormant until ids are set in Config.Badges)
		BadgeService.choicesFirstRun(player)
		BadgeService.choicesLegends(player, unlocked, ChoiceBank.legendCount())
		restoreAvatar(player) -- put their real avatar back
		removeTrail(player) -- drop the cosmetic trail
		Net.getEvent(Net.Events.ChoicesMode):FireClient(player, { active = false }) -- restore HUD
		task.delay(3, function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				(hum :: Humanoid).WalkSpeed = 16
			end
			local spawnPart = Workspace:FindFirstChild("LobbySpawn")
			if spawnPart and spawnPart:IsA("BasePart") then
				teleport(player, spawnPart.CFrame + Vector3.new(0, 4, 0))
			end
			finishing[player] = nil
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		finishing[player] = nil
		runState[player] = nil
		originalDesc[player] = nil
		heatJoined[player] = nil
		for _, gate in gates do
			gate.answered[player] = nil
		end
	end)
end

return TriviaParkourService
