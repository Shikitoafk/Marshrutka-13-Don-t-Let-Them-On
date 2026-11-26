--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AtmosphereController = {}

local FLICKER_STEP = 0.25
local BLACKOUT_DURATION = 1.8

local function setNight()
	Lighting.ClockTime = 0.3
	Lighting.Brightness = 1.4
	Lighting.Ambient = Color3.fromRGB(58, 64, 87)
	Lighting.OutdoorAmbient = Color3.fromRGB(58, 76, 103)
	Lighting.FogColor = Color3.fromRGB(43, 55, 75)
	Lighting.FogStart = 38
	Lighting.FogEnd = 165

	-- Atmosphere заменяет обычный туман Lighting, если он уже есть в плейсе.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = Lighting.FogColor
		atmosphere.Decay = Color3.fromRGB(68, 84, 110)
		atmosphere.Density = 0.37
		atmosphere.Haze = 1.3
		atmosphere.Glare = 0
	end
end

local function makeSound(name: string, id: string, parent: Instance, volume: number, looped: boolean): Sound?
	if id == "" or id == "rbxassetid://0" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Marshrutka" .. name
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = 65
	sound.Parent = parent
	return sound
end

local function replay(sound: Sound?)
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function getBus(): Model?
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	return if bus and bus:IsA("Model") then bus else nil
end

function AtmosphereController:Init(_controllers: { [string]: any }) end

function AtmosphereController:Start()
	setNight()
	local blackout = Instance.new("ColorCorrectionEffect")
	blackout.Name = "MarshrutkaBlackout"
	blackout.Brightness = -0.36
	blackout.Contrast = 0.18
	blackout.Saturation = -0.42
	blackout.TintColor = Color3.fromRGB(175, 191, 224)
	blackout.Enabled = false
	blackout.Parent = Lighting

	local soundIds = Config.SOUNDS
	local spatialSounds = {
		{ name = "Engine", id = soundIds.Engine, volume = 0.32, looped = true },
		{ name = "DoorOpen", id = soundIds.DoorOpen, volume = 0.6, looped = false },
		{ name = "DoorClose", id = soundIds.DoorClose, volume = 0.6, looped = false },
		{ name = "RadioStatic", id = soundIds.RadioStatic, volume = 0.47, looped = false },
	}
	local ambient = makeSound("Ambience", soundIds.Ambience, SoundService, 0.26, true)
	if ambient then
		ambient:Play()
	end
	local whispers = makeSound("Whispers", soundIds.Whispers, SoundService, 0.53, false)
	local scare = makeSound("Jumpscare", soundIds.Jumpscare, SoundService, 0.7, false)

	local roundState: string? = nil
	local ended = false
	local cabinDark = false
	local lightVersion = 0
	local originalLights: { [Light]: boolean } = {}
	local currentBus: Model? = nil
	local currentRoot: BasePart? = nil
	local cabinSounds: { [string]: Sound } = {}
	local lastDoorsOpen: boolean? = nil

	local function restoreLights()
		for light, enabled in originalLights do
			light.Enabled = enabled
		end
		table.clear(originalLights)
	end

	local function syncLights()
		local bus = currentBus
		local fixtures = if bus then bus:FindFirstChild("InteriorLights") else nil
		for light, enabled in originalLights do
			if not fixtures or not light:IsDescendantOf(fixtures) then
				light.Enabled = enabled
				originalLights[light] = nil
			end
		end
		if fixtures then
			for _, child in fixtures:GetDescendants() do
				if child:IsA("Light") and originalLights[child] == nil then
					originalLights[child] = child.Enabled
					child.Enabled = false
				end
			end
		end
	end

	local function syncBus()
		local bus = getBus()
		local root = if bus then bus.PrimaryPart else nil
		if bus ~= currentBus then
			restoreLights()
			currentBus = bus
		end
		if root ~= currentRoot then
			for _, sound in cabinSounds do
				sound:Destroy()
			end
			table.clear(cabinSounds)
			currentRoot = root
			lastDoorsOpen = nil
			if root then
				for _, cue in spatialSounds do
					local sound = makeSound(cue.name, cue.id, root, cue.volume, cue.looped)
					if sound then
						cabinSounds[cue.name] = sound
					end
				end
			end
		end
		if cabinDark then
			syncLights()
		end
	end

	local function applyLightState(dark: boolean, dimView: boolean)
		cabinDark = dark
		blackout.Enabled = dimView
		if not dark then
			restoreLights()
		end
		syncBus()
	end

	local function clearEffects()
		lightVersion += 1
		applyLightState(false, false)
		for _, sound in cabinSounds do
			sound:Stop()
		end
		if whispers then
			whispers:Stop()
		end
		if scare then
			scare:Stop()
		end
	end

	local function isRunning(): boolean
		-- Пока RoundService не подключён, RouteService запускает greybox сам.
		return not ended and (roundState == nil or roundState == "Running")
	end

	local function applyBusState(speed: number, _health: number, doorsOpen: boolean)
		syncBus()
		if not isRunning() then
			return
		end
		local engine = cabinSounds.Engine
		if engine then
			local fraction = math.clamp(math.abs(speed) / Config.BUS_MAX_SPEED, 0, 1)
			engine.PlaybackSpeed = 0.72 + 0.83 * fraction
			engine.Volume = 0.28 + 0.23 * fraction
			if not engine.Playing then
				engine:Play()
			end
		end
		if lastDoorsOpen ~= nil and doorsOpen ~= lastDoorsOpen then
			replay(if doorsOpen then cabinSounds.DoorOpen else cabinSounds.DoorClose)
		end
		lastDoorsOpen = doorsOpen
	end

	local function onEscalation(_level: number, effect: string)
		if not isRunning() or not table.find(Config.ESCALATION_EFFECTS, effect) then
			return
		end
		syncBus()
		if effect == "RadioStatic" then
			replay(cabinSounds.RadioStatic)
		elseif effect == "Whispers" then
			replay(whispers)
		elseif effect == "LightsFlicker" then
			if blackout.Enabled then
				return
			end
			lightVersion += 1
			local version = lightVersion
			applyLightState(true, false)
			task.spawn(function()
				for _, dark in { false, true, false } do
					task.wait(FLICKER_STEP)
					if lightVersion ~= version then
						return
					end
					applyLightState(dark, false)
				end
			end)
		elseif effect == "Blackout" then
			lightVersion += 1
			local version = lightVersion
			applyLightState(true, true)
			task.delay(BLACKOUT_DURATION, function()
				if lightVersion == version then
					applyLightState(false, false)
				end
			end)
		end
	end

	local function applyResult(summary: { Won: boolean })
		if ended or roundState == "Lobby" or roundState == "Countdown" then
			return
		end
		ended = true
		clearEffects()
		if summary.Won == false then
			applyLightState(true, true)
			replay(scare)
		end
	end

	local function applyRoundState(state: string)
		if state == roundState then
			return
		end
		roundState = state
		lastDoorsOpen = nil
		if state ~= "Results" then
			ended = false
			clearEffects()
		elseif not ended then
			-- Итоги с причиной завершения могут прийти после RoundState.
			clearEffects()
		end
	end

	if RunService:IsStudio() and Workspace:GetAttribute("StudioAtmospherePreview") == true then
		local preview = Instance.new("BindableEvent")
		preview.Name = "StudioAtmospherePreview"
		preview.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		preview.Event:Connect(function(effect: string)
			if effect == "Depot" then
				applyRoundState("Lobby")
			elseif effect == "Defeat" then
				applyRoundState("Running")
				applyResult({ Won = false })
			else
				applyRoundState("Running")
				onEscalation(1, effect)
			end
		end)
	end

	Remotes.Event("BusState").OnClientEvent:Connect(applyBusState)
	Remotes.Event("RoundState").OnClientEvent:Connect(applyRoundState)
	Remotes.Event("AnomalyEscalated").OnClientEvent:Connect(onEscalation)
	Remotes.Event("RunEnded").OnClientEvent:Connect(applyResult)
end

return AtmosphereController
