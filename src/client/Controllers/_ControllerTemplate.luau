--!strict
-- ШАБЛОН КОНТРОЛЛЕРА (клиент). Скопируйте файл, уберите "_" из имени и переименуйте.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ExampleController = {}

local player = Players.LocalPlayer

function ExampleController:Init(_controllers: { [string]: any })
	Remotes.Event("Notify").OnClientEvent:Connect(function(text: string, _kind: string?)
		print(`[Notify for {player.Name}] {text}`)
	end)
end

function ExampleController:Start() end

return ExampleController
