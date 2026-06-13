--!strict
-- Sound: tiny client-side SFX player. One Sound instance per named effect,
-- played as a 2D one-shot via SoundService:PlayLocalSound (overlaps cleanly).
-- IDs live in Config.Sounds; a placeholder ("rbxassetid://0") is skipped, so
-- every hook is a safe no-op until real audio is dropped in.

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Sound = {}

local PLACEHOLDER = "rbxassetid://0"
local cache: { [string]: Sound } = {}

local function getSound(name: string): Sound?
	local id = (Config.Sounds :: { [string]: string })[name]
	if not id or id == "" or id == PLACEHOLDER then
		return nil
	end
	local existing = cache[name]
	if existing then
		return existing
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Parent = SoundService
	cache[name] = sound
	return sound
end

function Sound.play(name: string)
	local sound = getSound(name)
	if sound then
		SoundService:PlayLocalSound(sound)
	end
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

return Sound
