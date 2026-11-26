--!strict
-- ШАБЛОН СЕРВИСА. Скопируйте файл, уберите "_" из имени и переименуйте.
-- Файлы, начинающиеся с "_", загрузчик пропускает.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ExampleService = {}

local registry: { [string]: any } = {}

-- Init: подготовка. Создайте состояние, подпишитесь на Remotes.
-- Не вызывайте здесь другие сервисы: они могут быть ещё не готовы.
function ExampleService:Init(services: { [string]: any })
	registry = services
	local _ = Config
	local _event = Remotes.Event("Notify")
end

-- Start: здесь уже можно обращаться к другим сервисам через registry.
function ExampleService:Start()
	local _ = registry
end

return ExampleService
