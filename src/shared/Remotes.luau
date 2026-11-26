--!strict
-- КОНТРАКТ СЕТИ. Все RemoteEvent/RemoteFunction игры объявлены ТОЛЬКО здесь.
-- Менять этот файл может только оркестратор (через Рината). Агенты: если нужен
-- новый ремоут — опишите его в PR в разделе «Нужно изменить контракт», не добавляйте сами.
--
-- Использование (сервер и клиент одинаково):
--   local Remotes = require(ReplicatedStorage.Shared.Remotes)
--   Remotes.Event("StopChanged"):FireAllClients(...)
--   Remotes.Event("DriverInput").OnServerEvent:Connect(...)
--
-- Подробное описание аргументов каждого события — docs/ARCHITECTURE.md, раздел «Ремоуты».

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	-- Клиент -> Сервер
	"DriverInput", -- (throttle: number)  -1..1, газ/тормоз водителя
	"DoorsRequest", -- (open: boolean)    водитель открывает/закрывает двери
	"HornRequest", -- ()                  сигнал
	"InspectPassenger", -- (passengerId: string, tool: "Ticket" | "Flashlight")
	"EjectPassenger", -- (passengerId: string)
	"LobbyReady", -- (ready: boolean)

	-- Сервер -> Клиент
	"RoundState", -- (state: string, data: {[string]: any})
	"RoleAssigned", -- (role: "Driver" | "Conductor")
	"StopChanged", -- (index: number, name: string, phase: "Approaching" | "AtStop" | "Departed")
	"BusState", -- (speed: number, health: number, doorsOpen: boolean)
	"PassengerBoarded", -- (passengerId: string)
	"PassengerLeft", -- (passengerId: string, reason: "Exited" | "Ejected" | "Vanished")
	"InspectResult", -- (passengerId: string, tool: string, data: {[string]: any})
	"AnomalyEscalated", -- (level: number, effect: string)
	"RunEnded", -- (summary: {[string]: any})
	"CurrencyChanged", -- (tenge: number)
	"Notify", -- (key: string, kind: "Info" | "Warn" | "Good" | "Bad", params: {[string]: any}?) — ключ из Strings.luau
}

local FUNCTIONS = {
	"GetProfile", -- () -> {Tenge: number, Stats: {...}, OwnedSkins: {string}}
}

local Remotes = {}

local function getFolder(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Instance
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function getOrCreate(name: string, className: string): Instance
	local folder = getFolder()
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name)
end

function Remotes.Event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), `Неизвестный RemoteEvent "{name}". Добавьте его в Remotes.luau через оркестратора.`)
	return getOrCreate(name, "RemoteEvent") :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), `Неизвестная RemoteFunction "{name}".`)
	return getOrCreate(name, "RemoteFunction") :: RemoteFunction
end

-- Сервер создаёт все ремоуты заранее, чтобы клиент не ждал вечно.
if RunService:IsServer() then
	for _, name in EVENTS do
		getOrCreate(name, "RemoteEvent")
	end
	for _, name in FUNCTIONS do
		getOrCreate(name, "RemoteFunction")
	end
end

return Remotes
