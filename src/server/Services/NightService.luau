--!strict
-- Ночи (V2, GDD §9). Какую ночь едем, её правила и пул аномалий (src/shared/Nights.luau), звёзды в конце рейса.
-- Ночь в лобби выбирает лидер рейса — первый нажавший «Готов» (его ведёт RoundService) — через NightSelect,
-- не выше своей открытой ночи. В рейсе ночь не меняется.

local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Nights = require(Shared:WaitForChild("Nights"))
local AnomalyTypes = require(Shared:WaitForChild("AnomalyTypes"))
local RateLimit = require(script.Parent.Parent:WaitForChild("RateLimit"))
local Outfit = require(script.Parent.Parent:WaitForChild("Outfit"))

local SELECT_RATE = 5 -- NightSelect в секунду на игрока: сверх — отбрасываем до проверок
local STOP_WATCH_STEP = 0.25 -- как часто смотрим, не встал ли водитель, пока просьба в силе
local UNIFORM = Color3.fromRGB(30, 60, 150) -- синяя форма настоящего контролёра (правило ночи 5)
local FAKE_UNIFORM = Color3.fromRGB(38, 44, 42) -- у фальшивого: почти чёрная и без жетона
local BADGE = Color3.fromRGB(230, 185, 60)

local NightService = {}

local registry: { [string]: any } = {}
local selected = 1 -- выбранная ночь
local ruleBreaks = 0 -- нарушения правил ночи за рейс (V02/V04 зовут BreakRule): минус ★★
local runId = 0 -- растёт на старте и конце рейса: отложенные проверки старого рейса не срабатывают
local running = false

local function log(text: string)
	if RunService:IsStudio() then
		print(`[Night] {text}`)
	end
end

local function notifyRiders(key: string, kind: string, params: { [string]: any }?)
	local round = registry.RoundService
	for _, player in (if round then round:GetRiders() else {}) do
		Remotes.Event("Notify"):FireClient(player, key, kind, params)
	end
end

local attach = Outfit.attach

-- Форма контролёра: одежда снята, тело в цвет формы, фуражка; у настоящего — золотой жетон на груди.
-- Случайной шапки/сумки пассажира (папка Look, V11) у контролёра нет.
local function uniform(model: Model, color: Color3, badge: boolean)
	local look = model:FindFirstChild("Look")
	if look then
		look:Destroy()
	end
	for _, item in model:GetDescendants() do
		if item:IsA("Clothing") or item:IsA("ShirtGraphic") or item:IsA("BodyColors") then
			item:Destroy()
		elseif item:IsA("BasePart") and (string.find(item.Name, "Torso") or string.find(item.Name, "Arm") or string.find(item.Name, "Leg") or string.find(item.Name, "Foot")) then
			item.Color = color
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		attach(head, "Cap", Vector3.new(head.Size.X * 1.1, 0.3, head.Size.Z * 1.15), CFrame.new(0, head.Size.Y / 2 + 0.1, 0), color)
		attach(head, "CapVisor", Vector3.new(head.Size.X * 0.9, 0.1, 0.4), CFrame.new(0, head.Size.Y / 2 - 0.02, -head.Size.Z / 2 - 0.15), Color3.new(0.05, 0.05, 0.05))
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if badge and torso and torso:IsA("BasePart") then
		attach(torso, "Badge", Vector3.new(0.35, 0.4, 0.08), CFrame.new(-torso.Size.X * 0.25, torso.Size.Y * 0.2, -torso.Size.Z / 2 - 0.04), BADGE)
	end
end

local function dressReal(model: Model)
	uniform(model, UNIFORM, true)
end

local function dressFake(model: Model)
	uniform(model, FAKE_UNIFORM, false)
end

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
-- Синхронно (B08): GetUnlockedNight профиль не ждёт (не загружен — 1), поэтому отсчёт стартует уже с проверенной ночью.
-- RoundService сам разошлёт RoundState после смены лидера.
function NightService:OnLeaderChanged(leader: Player?)
	if leader then
		selected = math.min(selected, unlockedNight(leader))
	end
end

local function sendInfo(player: Player)
	local night = Nights[selected]
	Remotes.Event("NightInfo"):FireClient(player, selected, night.Rules, { NameKey = night.NameKey, Events = night.Events })
end

-- RoundService: рейс начался (после RoundState «Running») — каждому ночь и правила.
function NightService:StartRun(riders: { Player })
	ruleBreaks = 0
	runId += 1
	running = true
	for _, player in riders do
		sendInfo(player)
	end
end

-- Зашёл посреди рейса.
function NightService:SendInfo(player: Player)
	sendInfo(player)
end

-- Финал последней ночи (V10): доехали до «Конечной» — ★★ и больше «Good», ★ «Bad»; не доехали или не последняя — нет.
function NightService.Ending(night: number, stars: number): string?
	if night ~= #Nights or stars <= 0 then
		return nil
	end
	return if stars >= 2 then "Good" else "Bad"
end
assert(
	NightService.Ending(#Nights, 3) == "Good" and NightService.Ending(#Nights, 1) == "Bad"
		and NightService.Ending(#Nights, 0) == nil and NightService.Ending(1, 3) == nil,
	"[NightService] Ending: концовки считаются неверно"
)

-- Бейдж за концовку: Config.BADGES.EndingGood / EndingBad (0 — не выдавать).
local function awardEnding(player: Player, ending: string)
	local id = if ending == "Good" then Config.BADGES.EndingGood else Config.BADGES.EndingBad
	if id <= 0 or player.UserId <= 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
				BadgeService:AwardBadgeAsync(player.UserId, id)
			end
		end)
		if not ok then
			warn(`[NightService] Бейдж концовки {id}: {err}`)
		end
	end)
end

-- AnomalyService: рейс окончен. Возвращает звёзды и концовку (V10); хотя бы одна звезда — записываем в профиль.
function NightService:FinishRun(won: boolean, mistakes: number, anomalyHits: number, riders: { Player }): (number, string?)
	runId += 1
	running = false
	local stars = NightService.Stars(won, mistakes + ruleBreaks, anomalyHits)
	local data = registry.DataService
	if stars > 0 and data and data.RecordNight then
		for _, player in riders do
			task.spawn(data.RecordNight, data, player, selected, stars) -- ходит в DataStore
		end
	end
	local ending = NightService.Ending(selected, stars)
	if ending then
		log(`концовка {ending}`)
		for _, player in riders do
			awardEnding(player, ending)
		end
		if ending == "Bad" then
			selected = 1 -- «Маршрут 13 не заканчивается»: снова депо ночи 1
		end
	end
	return stars, ending
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

	-- Контролёр (V03): садится на остановке ControllerAtStop, через CONTROLLER_CHECK_TIME проверяет салон.
	-- В ночь 5 с шансом FakeControllerChance он фальшивый — аномалия FakeController, ничего не проверяет.
	local route, passengers, anomalies = registry.RouteService, registry.PassengerService, registry.AnomalyService
	if not (route and passengers and anomalies) then
		warn("[NightService] Нет RouteService, PassengerService или AnomalyService — контролёра не будет")
		return
	end
	local function check(id: string)
		local run = runId
		task.delay(Config.CONTROLLER_CHECK_TIME, function()
			if run ~= runId or not passengers:GetModel(id) then
				return -- рейс кончился, или контролёра уже высадили
			end
			local found = anomalies:CountAboard()
			log(`контролёр проверил салон: аномалий {found}`)
			if found > 0 then
				for _ = 1, found do
					anomalies:Damage(Config.CONTROLLER_PENALTY_PER_ANOMALY)
				end
				notifyRiders("notify.controller_found", "Bad", { count = found })
			else
				anomalies:Reward(Config.CONTROLLER_CLEAN_BONUS)
				notifyRiders("notify.controller_clean", "Good", { bonus = Config.CONTROLLER_CLEAN_BONUS })
			end
		end)
	end
	route.StopChanged:Connect(function(index: number, _name: string, phase: string)
		local events = Nights[selected].Events
		if not (running and phase == "Approaching" and index == events.ControllerAtStop) then
			return
		end
		local fake = math.random() < (events.FakeControllerChance or 0)
		passengers:SpawnSpecial(index, if fake then dressFake else dressReal, if fake then "FakeController" else nil, function(id: string)
			log(if fake then "сел фальшивый контролёр" else "сел контролёр")
			notifyRiders("notify.controller_boarded", "Info")
			if not fake then
				check(id)
			end
		end)
	end)

	-- Просьбы остановиться (Events.StopRequests): если в салоне аномалия StopRequest, посреди перегона она просит
	-- остановить. Встал вне зоны остановки, пока просьба в силе (до следующей остановки), — урон и нарушение правила.
	-- На автопилоте автобус между остановками не встаёт, поэтому без водителя урона не бывает.
	local leg = 0 -- растёт на каждой остановке: просьба с прошлого перегона больше не действует
	route.StopChanged:Connect(function(_index: number, _name: string, phase: string)
		if phase == "AtStop" then
			leg += 1
		end
		if not (running and phase == "Departed" and Nights[selected].Events.StopRequests) then
			return
		end
		local myLeg, run = leg, runId
		task.delay(math.random(Config.STOP_REQUEST_ASK_MIN, Config.STOP_REQUEST_ASK_MAX), function()
			if leg ~= myLeg or run ~= runId or not anomalies:HasAboard("StopRequest") then
				return
			end
			log("просят остановить между остановками")
			notifyRiders("notify.stop_request", "Warn")
			while leg == myLeg and run == runId do
				if route:IsStoppedBetweenStops() then
					log("остановились по просьбе — урон")
					anomalies:Damage(Config.STOP_REQUEST_DAMAGE)
					NightService:BreakRule()
					return
				end
				task.wait(STOP_WATCH_STEP)
			end
		end)
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
