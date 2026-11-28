--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientSettings = require(script.Parent.ClientSettings)

local function makeGroup(name: string, muffled: boolean): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Parent = SoundService
	if muffled then
		local equalizer = Instance.new("EqualizerSoundEffect")
		equalizer.HighGain = -24
		equalizer.MidGain = -10
		equalizer.Parent = group
	end
	return group
end

local music = makeGroup("GameMusic", false)
local effects = makeGroup("GameEffects", false)
local ghostMusic = makeGroup("GhostMusic", true)
local ghostEffects = makeGroup("GhostEffects", true)
local ghost = false
local sources: { [Sound]: boolean } = {}
setmetatable(sources, { __mode = "k" })

local function route(source: Sound)
	local isMusic = source.Name == "TripMusic" or source.Name == "LocalPersonalRadio"
		or (Config.SOUNDS.Music ~= "rbxassetid://0" and source.SoundId == Config.SOUNDS.Music)
	if isMusic then
		source.SoundGroup = if ghost then ghostMusic else music
	else
		source.SoundGroup = if ghost then ghostEffects else effects
	end
end

local function track(instance: Instance)
	if instance:IsA("Sound") and (not instance.SoundGroup or sources[instance]) then
		sources[instance] = true
		route(instance)
	end
end

for _, scope in { Workspace, SoundService } do
	scope.DescendantAdded:Connect(track)
	for _, instance in scope:GetDescendants() do track(instance) end
end

local function updateVolume()
	local settings = ClientSettings.get()
	music.Volume = settings.MusicVolume
	effects.Volume = settings.EffectsVolume
	ghostMusic.Volume = settings.MusicVolume * 0.36
	ghostEffects.Volume = settings.EffectsVolume * 0.36
end
ClientSettings.Changed:Connect(updateVolume)
updateVolume()

local SettingsAudio = {}

function SettingsAudio.setGhost(enabled: boolean)
	if ghost == enabled then return end
	ghost = enabled
	for source in pairs(sources) do
		if source.Parent then route(source) end
	end
end

return SettingsAudio
