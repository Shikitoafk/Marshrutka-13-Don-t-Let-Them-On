--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))

local changed = Instance.new("BindableEvent")
local current: PlayerSettings.Values = table.clone(PlayerSettings.Default)
local ClientSettings = { Changed = changed.Event }

function ClientSettings.get(): PlayerSettings.Values
	return current
end

function ClientSettings.set(values: PlayerSettings.Values)
	current = table.freeze(table.clone(values))
	changed:Fire()
end

return ClientSettings
