--!strict
-- Аномалии. При посадке пассажир с шансом ночи (Nights.luau через NightService) становится аномалией
-- (не больше MAX_ANOMALIES_AT_ONCE): тип по весам ночи. Правда хранится ТОЛЬКО здесь, на модель ставится лишь подсказка (CueAttribute).
-- Кондукторы проверяют (InspectPassenger) и высаживают (EjectPassenger). Опасная аномалия в салоне на отъезде от остановки —
-- урон и эскалация; «свою» (Safe) высадил — штраф и проклятие. Прочность 0 — Оберег или поражение. Итоги рейса (RunEnded) тоже отсюда.

local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RateLimit = require(script.Parent.Parent:WaitForChild("RateLimit"))
local AnomalyTypes = require(Shared:WaitForChild("AnomalyTypes"))
local Nights = require(Shared:WaitForChild("Nights"))

type AnomalyType = AnomalyTypes.AnomalyType

local MAX_ID_LENGTH = 64 -- GUID короче; длиннее — мусор от клиента
local TOOL_RATE = 5 -- Inspect/Eject в секунду на игрока: сверх — отбрасываем до проверок
local WRONG_ROUTES = { "№31", "№18", "№130" }
-- shortcut: у этих аномалий ещё нет поведения и примет (V02) — до него из пула ночи их не выдаём.
local NOT_YET = { StrangeCoin = true, Grandma = true, Standing = true, StopRequest = true }

local byId: { [string]: AnomalyType } = {}
for _, kind in AnomalyTypes do
	byId[kind.Id] = kind
end

local AnomalyService = {}

local registry: { [string]: any } = {}
local truth: { [string]: AnomalyType } = {} -- [PassengerId] = тип; только аномалии в салоне
local tickets: { [string]: { [string]: string } } = {} -- [PassengerId] = {Route, Date}
local boardedAt: { [string]: number } = {} -- [PassengerId аномалии] = остановка посадки: бьёт с отъезда от следующей
local twinOf: { [string]: string } = {} -- [PassengerId двойника] = PassengerId оригинала
local atStop = 0 -- на какой остановке стоим (для boardedAt)
local runActive = false -- проверять и высаживать можно только в рейсе (не на экране итогов)
local health = Config.BUS_MAX_HEALTH
local hits = 0 -- сколько раз автобус получил урон за рейс (уровень эскалации)
local amuletTried = false
local caught, mistakes, stopsReached = 0, 0, 0
local earnedPlus, earnedMinus = 0, 0 -- тенге за рейс без VIP: плюсы VIP удваивает, минусы нет

local notify = Remotes.Event("Notify")

local function log(text: string)
	if RunService:IsStudio() then
		print(`[Anomaly] {text}`) -- только в Studio: в игре правду никто не видит
	end
end

local function riders(): { Player }
	local round = registry.RoundService
	return if round then round:GetRiders() else {}
end

-- Notify — ключ и параметры (ARCHITECTURE, «Сообщения Notify»), текст подставит клиент.
local function notifyRiders(key: string, kind: string, params: { [string]: any }?)
	for _, player in riders() do
		notify:FireClient(player, key, kind, params)
	end
end

-- Деньги всем в рейсе; AddTenge может ждать профиль, поэтому в task.spawn.
local function payRiders(amount: number)
	local data = registry.DataService
	if not data then
		return
	end
	for _, player in riders() do
		task.spawn(data.AddTenge, data, player, amount)
	end
end

local function ticket(wrong: boolean): { [string]: string }
	local route = "№" .. Config.ROUTE_NUMBER
	local today = os.date("%d.%m.%Y")
	if not wrong then
		return { Route = route, Date = today }
	end
	if math.random() < 0.5 then
		return { Route = WRONG_ROUTES[math.random(#WRONG_ROUTES)], Date = today }
	end
	return { Route = route, Date = string.sub(today, 1, 6) .. "1986" }
end

-- Тип по весам ночи; двойник — только если есть с кого копировать. Пустой пул — nil (пассажир обычный).
local function pickType(pool: { [string]: number }, canTwin: boolean): AnomalyType?
	local function usable(id: string): boolean
		return byId[id] ~= nil and not NOT_YET[id] and (canTwin or id ~= "Twin")
	end
	local total = 0
	for id, weight in pool do
		if usable(id) then
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	local last: AnomalyType? = nil
	for id, weight in pool do
		if usable(id) then
			last = byId[id]
			roll -= weight
			if roll <= 0 then
				return last
			end
		end
	end
	return last
end

-- Опасная — та, что бьёт автобус и которую надо высадить. «Свои» (Safe) и особые (Special) живут по своим правилам.
local function dangerous(kind: AnomalyType): boolean
	return (kind.Class or "Dangerous") == "Dangerous"
end

local function nightData(): Nights.Night
	local nights = registry.NightService
	return if nights then nights:GetNightData() else Nights[1]
end

local function twinOfValues(): { string }
	local result: { string } = {}
	for _, originalId in twinOf do
		table.insert(result, originalId)
	end
	return result
end

-- Двойник: цвета частей и одежда как у оригинала.
local function copyLook(from: Model, to: Model)
	for _, item in to:GetDescendants() do
		if item:IsA("BasePart") then
			local same = from:FindFirstChild(item.Name, true)
			if same and same:IsA("BasePart") then
				item.Color = same.Color
			end
		elseif item:IsA("Clothing") then
			item:Destroy()
		end
	end
	for _, item in from:GetChildren() do
		if item:IsA("Clothing") then
			item:Clone().Parent = to
		end
	end
end

local function turnHead(model: Model)
	local neck = model:FindFirstChild("Neck", true)
	if neck and neck:IsA("Motor6D") then
		neck.C0 = neck.C0 * CFrame.Angles(0, math.pi, 0)
	end
end

function AnomalyService:GetHealth(): number
	return health
end

-- Сколько аномалий сейчас в салоне (ScareEventService: больше пугалок, когда они рядом).
function AnomalyService:CountAboard(): number
	local passengers = registry.PassengerService
	local aboard: { [string]: Model } = if passengers then passengers:GetOnboard() else {}
	local count = 0
	for id, kind in truth do
		if aboard[id] and dangerous(kind) then
			count += 1
		end
	end
	return count
end

-- PassengerService зовёт при посадке. true — аномалия (сама не выйдет).
function AnomalyService:OnBoarded(id: string, model: Model): boolean
	earnedPlus += Config.FARE_PER_PASSENGER -- плату начисляет PassengerService, здесь только считаем для итогов
	tickets[id] = ticket(false)
	local count = 0
	for _ in truth do
		count += 1
	end
	local night = nightData()
	if count >= Config.MAX_ANOMALIES_AT_ONCE or math.random() >= night.AnomalyChance then
		return false
	end
	local passengers = registry.PassengerService
	-- Оригинал для двойника — только обычный пассажир: не аномалия и не чей-то уже оригинал.
	local candidates: { string } = {}
	local aboard: { [string]: Model } = if passengers then passengers:GetOnboard() else {}
	for otherId in aboard do
		if otherId ~= id and not truth[otherId] and not table.find(twinOfValues(), otherId) then
			table.insert(candidates, otherId)
		end
	end
	local originalId: string? = if #candidates > 0 then candidates[math.random(#candidates)] else nil
	local original = if originalId then aboard[originalId] else nil
	local kind = pickType(night.Anomalies, originalId ~= nil)
	if not kind then
		return false
	end
	truth[id] = kind
	boardedAt[id] = atStop
	if kind.CueAttribute then
		model:SetAttribute(kind.CueAttribute, if kind.Id == "Twin" then originalId else true)
	end
	if kind.Id == "Twin" and originalId and original then
		copyLook(original, model)
		twinOf[id] = originalId
		passengers:KeepAboard(originalId) -- оригинал не выйдет, иначе двойника нечем вычислить
	elseif kind.Id == "WrongHead" then
		turnHead(model)
	elseif kind.Id == "WrongTicket" then
		tickets[id] = ticket(true)
	end
	log(`сел пассажир-аномалия: {kind.Name}`)
	return true
end

-- RoundService зовёт в конце рейса (победа или поражение): итоги каждому, звёзды ночи, бонус, статистика.
function AnomalyService:FinishRun(won: boolean)
	runActive = false
	local data, shop = registry.DataService, registry.MonetizationService
	local nights, ghosts = registry.NightService, registry.GhostService
	local bonus = if won then Config.FINISH_BONUS else 0
	local list = riders()
	local stars = if nights then nights:FinishRun(won, mistakes, hits, list) else 0
	local taken = if ghosts and ghosts.CountTaken then ghosts:CountTaken() else 0 -- GhostService (V04)
	for _, player in list do
		local vip = shop ~= nil and shop:HasVIP(player) -- x2 к плюсам делает DataService; в итогах считаем так же
		Remotes.Event("RunEnded"):FireClient(player, {
			Won = won,
			Tenge = (earnedPlus + bonus) * (if vip then 2 else 1) + earnedMinus,
			Caught = caught,
			Mistakes = mistakes,
			StopsReached = stopsReached,
			Night = if nights then nights:GetNight() else 1,
			Stars = stars,
			Taken = taken,
		})
		if data then
			task.spawn(function()
				if won then
					data:AddTenge(player, bonus)
					data:IncrementStat(player, "Wins")
				end
				data:IncrementStat(player, "Runs")
			end)
		end
	end
end

function AnomalyService:Init(services: { [string]: any })
	registry = services
end

function AnomalyService:Start()
	local route, passengers = registry.RouteService, registry.PassengerService
	if not (route and passengers) then
		warn("[AnomalyService] Нет RouteService или PassengerService — аномалий не будет")
		return
	end
	local escalated = Remotes.Event("AnomalyEscalated")
	local inspectResult = Remotes.Event("InspectResult")
	-- Раздельные кулдауны: «проверил билет → сразу высадил» не должно теряться из-за задержки сети.
	local lastInspectAt: { [Player]: number } = {}
	local lastEjectAt: { [Player]: number } = {}
	local allowInspect, allowEject = RateLimit.new(TOOL_RATE), RateLimit.new(TOOL_RATE)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastInspectAt[player] = nil
		lastEjectAt[player] = nil
	end)

	local function resetRun()
		runActive = true
		table.clear(truth)
		table.clear(tickets)
		table.clear(boardedAt)
		table.clear(twinOf)
		atStop = 0
		health, hits, amuletTried = Config.BUS_MAX_HEALTH, 0, false
		caught, mistakes, stopsReached = 0, 0, 0
		earnedPlus, earnedMinus = 0, 0
	end

	-- Прочность 0: Оберег (один раз за рейс) или поражение через RoundService.
	local function onBroken()
		local round = registry.RoundService
		if amuletTried then
			if round then
				round:EndRun(false)
			end
			return
		end
		amuletTried = true
		task.spawn(function() -- ConsumeAmulet ходит в DataStore — ждёт
			local shop = registry.MonetizationService
			for _, player in riders() do
				if shop and shop:ConsumeAmulet(player) then
					health = Config.AMULET_RESTORE_HEALTH
					notifyRiders("notify.amulet_saved", "Good", { player = player.DisplayName })
					return
				end
			end
			if round then
				round:EndRun(false)
			end
		end)
	end

	local function damage()
		if health <= 0 then
			return
		end
		health = math.max(0, health - Config.ANOMALY_DAMAGE)
		hits += 1
		local effects = Config.ESCALATION_EFFECTS
		local effect = effects[math.min(hits, #effects)]
		escalated:FireAllClients(hits, effect)
		local scares = registry.ScareEventService
		if scares then
			scares:OnEscalation(effect) -- Blackout → силуэт на заднем сиденье
		end
		log(`урон: прочность {health}`)
		if health <= 0 then
			onBroken()
		end
	end

	route.StopChanged:Connect(function(index: number, _name: string, phase: string)
		if phase == "Approaching" and index == 1 then
			resetRun() -- новый рейс
		end
		if phase == "AtStop" then
			atStop = index
		end
		if phase == "AtStop" or phase == "Departed" then
			stopsReached = math.max(stopsReached, index)
		end
		if phase == "Departed" then
			local aboard = passengers:GetOnboard()
			for id, kind in truth do
				-- севшая на этой же остановке ещё не бьёт: у кондукторов должен быть целый перегон
				if aboard[id] and dangerous(kind) and (boardedAt[id] or 0) < index then
					damage()
				end
			end
		end
	end)

	-- Кондуктор рядом с пассажиром в салоне? Возвращает модель или nil.
	local function conductorNear(player: Player, id: string): Model?
		local roles = registry.RoleService
		if not table.find(riders(), player) or (roles and roles:GetDriver() == player) then
			return nil
		end
		local model = passengers:GetModel(id)
		local character = player.Character
		local a = if model then model:FindFirstChild("HumanoidRootPart") else nil
		local b = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not (model and a and b and a:IsA("BasePart") and b:IsA("BasePart")) then
			return nil
		end
		return if (a.Position - b.Position).Magnitude <= Config.INSPECT_RANGE then model else nil
	end

	local function allowed(player: Player, id: unknown, last: { [Player]: number }): boolean
		if not runActive or type(id) ~= "string" or #id > MAX_ID_LENGTH or time() - (last[player] or 0) < Config.INSPECT_COOLDOWN then
			return false
		end
		if not conductorNear(player, id) then
			return false
		end
		last[player] = time()
		return true
	end

	Remotes.Event("InspectPassenger").OnServerEvent:Connect(function(player: Player, id: unknown, tool: unknown)
		if not allowInspect(player) or (tool ~= "Ticket" and tool ~= "Flashlight") or not allowed(player, id, lastInspectAt) then
			return
		end
		local passengerId = id :: string
		local data: { [string]: string } = if tool == "Ticket" then tickets[passengerId] or ticket(false) else {}
		inspectResult:FireClient(player, passengerId, tool, data)
	end)

	Remotes.Event("EjectPassenger").OnServerEvent:Connect(function(player: Player, id: unknown)
		if not allowEject(player) or not allowed(player, id, lastEjectAt) then
			return
		end
		local passengerId = id :: string
		if not passengers:Eject(passengerId) then
			return
		end
		local kind = truth[passengerId]
		truth[passengerId] = nil
		tickets[passengerId] = nil
		-- Двойник: высадка любого из пары — поимка, оставшийся снова обычный пассажир.
		local partner: string? = twinOf[passengerId]
		if not kind then
			for twinId, originalId in twinOf do
				if originalId == passengerId then
					partner, kind = twinId, truth[twinId]
				end
			end
		end
		if partner then
			twinOf[passengerId] = nil
			twinOf[partner] = nil
			truth[partner] = nil
			boardedAt[partner] = nil
			local remaining = passengers:GetModel(partner)
			if remaining then
				remaining:SetAttribute("TwinOf", nil)
			end
			passengers:ReleaseAboard(partner)
		end
		if kind and kind.Class == "Safe" then
			-- «Свою» высадили: штраф, ошибка (минус ★★) и проклятие — мигает свет.
			mistakes += 1
			earnedMinus -= Config.SAFE_EJECT_PENALTY
			payRiders(-Config.SAFE_EJECT_PENALTY)
			notifyRiders("notify.safe_ejected", "Bad", { penalty = Config.SAFE_EJECT_PENALTY })
			escalated:FireAllClients(hits, "LightsFlicker")
		elseif kind then
			caught += 1
			earnedPlus += Config.CATCH_REWARD
			payRiders(Config.CATCH_REWARD)
			notifyRiders("notify.anomaly_ejected", "Good", { anomalyId = kind.Id, reward = Config.CATCH_REWARD })
			local data = registry.DataService
			if data then
				task.spawn(data.IncrementStat, data, player, "Caught")
			end
		else
			mistakes += 1
			earnedMinus -= Config.WRONG_EJECT_PENALTY
			payRiders(-Config.WRONG_EJECT_PENALTY)
			notifyRiders("notify.human_ejected", "Bad", { penalty = Config.WRONG_EJECT_PENALTY })
		end
		log(`высадили: {if kind then kind.Name else "человек"}`)
	end)
end

return AnomalyService
