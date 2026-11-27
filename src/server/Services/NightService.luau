--!strict
-- Ночи (V2, GDD §9). Какую ночь едем, её правила и пул аномалий (src/shared/Nights.luau), звёзды в конце рейса.
-- Ночь в лобби выбирает лидер рейса — первый нажавший «Готов» (его ведёт RoundService) — через NightSelect,
-- не выше своей открытой ночи. В рейсе ночь не меняется.

local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Nights = require(Shared:WaitForChild("Nights"))
local AnomalyTypes = require(Shared:WaitForChild("AnomalyTypes"))
local RateLimit = require(script.Parent.Parent:WaitForChild("RateLimit"))

local SELECT_RATE = 5 -- NightSelect в секунду на игрока: сверх — отбрасываем до проверок

local NightService = {}

local registry: { [string]: any } = {}
local selected = 1 -- выбранная ночь
local ruleBreaks = 0 -- нарушения правил ночи за рейс (V02/V04 зовут BreakRule): минус ★★

-- Звёзды (Nights.luau): ★ доехали до «Конечной», ★★ ещё и без ошибок, ★★★ ещё и ни одна аномалия не нанесла урон.
function NightService.Stars(won: boolean, mistakes: number, anomalyHits: number): number
	if not won then
		return 0
	end
	if mistakes > 0 then
		return 1
	end
	return if anomalyHits > 0 then 2 else 3
end

function NightService:GetNight(): number
	return selected
end

function NightService:GetNightData(): Nights.Night
	return Nights[selected]
end

-- Нарушено правило ночи (посветил на стоящего, остановился по просьбе и т.п.): рейс уже не на ★★.
function NightService:BreakRule()
	ruleBreaks += 1
end

-- Сколько ночей открыто у игрока.
-- shortcut: пока у DataService нет GetUnlockedNight (V06, Codex) — в Studio открыты все ночи (для проверки), в игре только первая.
local function unlockedNight(player: Player): number
	local data = registry.DataService
	if data and data.GetUnlockedNight then
		local ok, night = pcall(data.GetUnlockedNight, data, player)
		return if ok and type(night) == "number" then math.clamp(math.floor(night), 1, #Nights) else 1
	end
	return if RunService:IsStudio() then #Nights else 1
end

-- RoundService: у лобби новый лидер. Выбор сохраняется между рейсами, но не выше открытой у нового лидера.
function NightService:OnLeaderChanged(leader: Player?)
	if not leader then
		return
	end
	task.spawn(function() -- профиль может ещё грузиться
		local max = unlockedNight(leader)
		local round = registry.RoundService
		if selected > max and round and round:GetLeader() == leader then
			selected = max
			round:Broadcast()
		end
	end)
end

local function sendInfo(player: Player)
	local night = Nights[selected]
	Remotes.Event("NightInfo"):FireClient(player, selected, night.Rules, { NameKey = night.NameKey, Events = night.Events })
end

-- RoundService: рейс начался (после RoundState «Running») — каждому ночь и правила.
function NightService:StartRun(riders: { Player })
	ruleBreaks = 0
	for _, player in riders do
		sendInfo(player)
	end
end

-- Зашёл посреди рейса.
function NightService:SendInfo(player: Player)
	sendInfo(player)
end

-- AnomalyService: рейс окончен. Возвращает звёзды; хотя бы одна — записываем в профиль (откроет следующую ночь).
function NightService:FinishRun(won: boolean, mistakes: number, anomalyHits: number, riders: { Player }): number
	local stars = NightService.Stars(won, mistakes + ruleBreaks, anomalyHits)
	local data = registry.DataService
	if stars > 0 and data and data.RecordNight then
		for _, player in riders do
			task.spawn(data.RecordNight, data, player, selected, stars) -- ходит в DataStore
		end
	end
	return stars
end

function NightService:Init(services: { [string]: any })
	registry = services
end

function NightService:Start()
	local allowSelect = RateLimit.new(SELECT_RATE)
	Remotes.Event("NightSelect").OnServerEvent:Connect(function(player: Player, night: unknown)
		-- night == floor(night) отсекает дроби и NaN
		if not allowSelect(player) or type(night) ~= "number" or night ~= math.floor(night) or night < 1 or night > #Nights then
			return
		end
		local round = registry.RoundService
		if not round or round:GetLeader() ~= player or night > unlockedNight(player) then
			return
		end
		if round:GetLeader() == player and selected ~= night then -- пока ждали профиль, лидер мог смениться
			selected = night
			round:Broadcast()
		end
	end)
end

-- Самопроверка (только в Studio): звёзды по правилам и данные ночей без опечаток в Id аномалий.
if RunService:IsStudio() then
	local S = NightService.Stars
	assert(S(false, 0, 0) == 0 and S(true, 1, 0) == 1 and S(true, 0, 1) == 2 and S(true, 0, 0) == 3, "[NightService] звёзды считаются не так")
	assert(#Nights == Config.NIGHTS_COUNT, "[NightService] в Nights.luau не столько ночей, сколько Config.NIGHTS_COUNT")
	local known: { [string]: boolean } = {}
	for _, kind in AnomalyTypes do
		known[kind.Id] = true
	end
	for i, night in Nights do
		assert(night.Index == i, `[NightService] ночь {i}: Index {night.Index}`)
		for id in night.Anomalies do
			assert(known[id], `[NightService] ночь {i}: нет аномалии {id} в AnomalyTypes`)
		end
	end
end

return NightService
