--!strict

export type Values = {
	MusicVolume: number,
	EffectsVolume: number,
	DriverSensitivity: number,
	ReducedEffects: boolean,
}

local PlayerSettings = {}
PlayerSettings.Default = table.freeze({
	MusicVolume = 1,
	EffectsVolume = 1,
	DriverSensitivity = 1,
	ReducedEffects = false,
})
PlayerSettings.MinSensitivity = 0.25
PlayerSettings.MaxSensitivity = 2

local function within(value: any, minimum: number, maximum: number): boolean
	return type(value) == "number" and value >= minimum and value <= maximum
end

function PlayerSettings.normalize(raw: any): Values?
	if type(raw) ~= "table" or not within(raw.MusicVolume, 0, 1)
		or not within(raw.EffectsVolume, 0, 1)
		or not within(raw.DriverSensitivity, PlayerSettings.MinSensitivity, PlayerSettings.MaxSensitivity)
		or type(raw.ReducedEffects) ~= "boolean"
	then return nil end
	return {
		MusicVolume = raw.MusicVolume,
		EffectsVolume = raw.EffectsVolume,
		DriverSensitivity = raw.DriverSensitivity,
		ReducedEffects = raw.ReducedEffects,
	}
end

return PlayerSettings
