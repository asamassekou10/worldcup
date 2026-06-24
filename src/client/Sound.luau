--!strict
-- Sound: tiny client-side SFX player. One Sound instance per named effect,
-- played as a 2D one-shot via SoundService:PlayLocalSound (overlaps cleanly).
-- IDs live in Config.Sounds; a placeholder ("rbxassetid://0") is skipped, so
-- every hook is a safe no-op until real audio is dropped in.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Sound = {}

local PLACEHOLDER = "rbxassetid://0"
local cache: { [string]: Sound } = {} -- keyed by resolved SoundId (so variants cache apart)

-- Per-effect playback volume (0..1). Anything not listed plays at full.
local VOLUME: { [string]: number } = {
	CrowdGroan = 0.4, -- user asked: keep the groan from being too loud
	CrowdRoar = 0.9,
}

-- One Sound instance per resolved id (shared across names that reuse the same clip).
local function shotFor(id: string, volume: number): Sound
	local s = cache[id]
	if s then
		return s
	end
	s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = SoundService
	cache[id] = s
	return s
end

-- Play a named effect. A config value may list SEVERAL space-separated ids; one is
-- chosen at random each time so repeated effects (e.g. Miss) stay fresh.
function Sound.play(name: string)
	local raw = (Config.Sounds :: { [string]: string })[name]
	if not raw or raw == "" or raw == PLACEHOLDER then
		return
	end
	local ids: { string } = {}
	for _, id in string.split(raw, " ") do
		if id ~= "" and id ~= PLACEHOLDER then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return
	end
	local chosen = ids[math.random(#ids)]
	SoundService:PlayLocalSound(shotFor(chosen, VOLUME[name] or 1))
end

-- ===== looping audio (ambience + music) =====

local loops: { [string]: Sound } = {}

local function makeLoop(id: string, volume: number): Sound?
	if id == "" or id == PLACEHOLDER then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

-- Stadium ambience -- starts once and loops quietly for the whole session.
function Sound.startCrowd()
	if loops.Crowd then
		return
	end
	local sound = makeLoop(Config.Audio.Crowd, 0.35)
	if sound then
		loops.Crowd = sound
		sound:Play()
	end
end

-- Lobby/entrance music -- played in the menu, stopped during a match.
function Sound.playMusic()
	local music = loops.Music
	if not music then
		local created = makeLoop(Config.Audio.LobbyMusic, 0.5)
		if not created then
			return
		end
		loops.Music = created
		music = created
	end
	music:Play()
end

function Sound.stopMusic()
	local music = loops.Music
	if music then
		music:Stop()
	end
end

-- ===== Reactive crowd audio =====
-- Smoothly lerps crowd volume between a quiet baseline (0.35) and a roaring
-- peak (0.80) to react to goals, saves, and misses. Call with a target
-- intensity (0 = quiet, 1 = roar) and an optional fade duration in seconds.

local CROWD_BASE   = 0.35
local CROWD_PEAK   = 0.80
local crowdTween: Tween?

function Sound.setCrowdIntensity(intensity: number, duration: number?)
	local crowd = loops.Crowd
	if not crowd then
		return
	end
	if crowdTween then
		crowdTween:Cancel()
	end
	local targetVol = CROWD_BASE + math.clamp(intensity, 0, 1) * (CROWD_PEAK - CROWD_BASE)
	crowdTween = TweenService:Create(
		crowd,
		TweenInfo.new(duration or 0.4, Enum.EasingStyle.Sine),
		{ Volume = targetVol }
	)
	crowdTween:Play()
end

-- Convenience: goal roar → fades back after `holdSeconds`. Layers a dedicated
-- roar one-shot over the ambience swell if one is configured (else just the swell).
function Sound.crowdGoalReact(holdSeconds: number?)
	Sound.play("CrowdRoar")
	Sound.setCrowdIntensity(1, 0.25)
	task.delay(holdSeconds or 3, function()
		Sound.setCrowdIntensity(0.15, 2)
	end)
end

function Sound.crowdSaveReact()
	Sound.setCrowdIntensity(0.75, 0.3)
	task.delay(2, function()
		Sound.setCrowdIntensity(0.15, 1.5)
	end)
end

function Sound.crowdMissReact()
	Sound.play("CrowdGroan")
	Sound.setCrowdIntensity(0.25, 0.5)
	task.delay(1.5, function()
		Sound.setCrowdIntensity(0.15, 1)
	end)
end

return Sound
