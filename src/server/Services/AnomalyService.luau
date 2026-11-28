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
local Outfit = require(script.Parent.Parent:WaitForChild("Outfit"))
local AnomalyTypes = require(Shared:WaitForChild("AnomalyTypes"))
local Nights = require(Shared:WaitForChild("Nights"))

type AnomalyType = AnomalyTypes.AnomalyType

local MAX_ID_LENGTH = 64 -- GUID короче; длиннее — мусор от клиента
local TOOL_RATE = 5 -- Inspect/Eject в секунду на игрока: сверх — отбрасываем до проверок
local WRONG_ROUTES = { "№31", "№18", "№130" }
local FARE_COIN = "coin.tenge_100" -- «передайте за проезд»: так платят люди (ключ Strings)
local STRANGE_COINS = { "coin.kopeck_1961", "coin.blank" } -- так платит StrangeCoin
local SCARF = Color3.fromRGB(150, 45, 55) -- платок бабушки
local BAG = Color3.fromRGB(105, 80, 50) -- котомка
local LAUGH_EVERY_MIN, LAUGH_EVERY_MAX = 12, 25 -- сек между «тихими смешками» бабушки

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
local dangerousBoarded = false -- V11: в этом рейсе уже садилась опасная аномалия (для FirstAnomalyByStop)
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
		return { Route = route, Date = today, Coin = FARE_COIN }
	end
	if math.random() < 0.5 then
		return { Route = WRONG_ROUTES[math.random(#WRONG_ROUTES)], Date = today, Coin = FARE_COIN }
	end
	return { Route = route, Date = string.sub(today, 1, 6) .. "1986", Coin = FARE_COIN }
end

-- Тип по весам ночи; двойник — только если есть с кого копировать. Пустой пул — nil (пассажир обычный).
local function pickType(pool: { [string]: number }, canTwin: boolean): AnomalyType?
	local function usable(id: string): boolean
		return byId[id] ~= nil and (canTwin or id ~= "Twin")
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

-- V11 «первая минута»: гарантированная аномалия — опасная и заметная сразу (зеркало, глаза, голова), если такие есть
-- в наборе ночи; иначе любая опасная из набора. Двойника не берём: ему нужен оригинал в салоне.
local OBVIOUS = { NoReflection = true, GlowingEyes = true, WrongHead = true }
local function guaranteedPool(pool: { [string]: number }): { [string]: number }
	local obvious: { [string]: number }, any: { [string]: number } = {}, {}
	for id, weight in pool do
		local kind = byId[id]
		if kind and (kind.Class or "Dangerous") == "Dangerous" and id ~= "Twin" then
			any[id] = weight
			if OBVIOUS[id] then
				obvious[id] = weight
			end
		end
	end
	return if next(obvious) then obvious else any
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
	-- Причёска, шапка, сумка (папка Look, V11): своё снять, копию оригинала приварить к своим частям тела.
	local own, look = to:FindFirstChild("Look"), from:FindFirstChild("Look")
	if own then
		own:Destroy()
	end
	if look then
		local copy = look:Clone() -- пока копия вне Workspace, её сварки не двигают оригинал
		for _, part in copy:GetChildren() do
			local weld = part:FindFirstChildOfClass("WeldConstraint")
			local base = if weld then weld.Part0 else nil
			local myBase = if base then to:FindFirstChild(base.Name) else nil
			if weld and base and part:IsA("BasePart") and myBase and myBase:IsA("BasePart") then
				part.CFrame = myBase.CFrame * base.CFrame:ToObjectSpace(part.CFrame)
				weld.Part0 = myBase
			else
				part:Destroy()
			end
		end
		copy.Parent = to
	end
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

-- Повернуть голову относительно исходного положения. Шея в старых R15 — Motor6D (C0), в новых ригах Roblox —
-- AnimationConstraint: его Transform клиентам не передаётся, поэтому крутим Attachment0 (CFrame реплицируется).
local function neckTurner(model: Model): ((CFrame) -> ())?
	local neck = model:FindFirstChild("Neck", true)
	if neck and neck:IsA("Motor6D") then
		local rest = neck.C0
		return function(turn: CFrame)
			neck.C0 = rest * turn
		end
	elseif neck and neck:IsA("AnimationConstraint") and neck.Attachment0 then
		local attachment = neck.Attachment0
		local rest = attachment.CFrame
		return function(turn: CFrame)
			attachment.CFrame = rest * turn
		end
	end
	return nil
end

local function turnHead(model: Model)
	local turn = neckTurner(model)
	if turn then
		turn(CFrame.Angles(0, math.pi, 0))
	end
end

-- Бабушка (Safe): платок поверх волос (лицо открыто) и котомка в правой руке. Случайной шапки/сумки (Look) у неё нет.
local function grandmaLook(model: Model)
	local look = model:FindFirstChild("Look")
	if look then
		look:Destroy()
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local s = head.Size
		Outfit.attach(head, "Headscarf", Vector3.new(s.X * 1.15, s.Y * 0.75, s.Z * 1.1), CFrame.new(0, s.Y * 0.2, s.Z * 0.12), SCARF)
	end
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		Outfit.attach(hand, "Bag", Vector3.new(1, 1.1, 0.6), CFrame.new(0.3, -0.8, 0), BAG)
	end
end

-- «Иногда тихо смеётся»: голова мелко трясётся и, когда ID вписан в Config, слышен смешок (как сигнал — играет сервер).
local function laughSometimes(id: string, model: Model)
	local turn = neckTurner(model)
	if not turn then
		return
	end
	local laugh: Sound? = nil
	local head = model:FindFirstChild("Head")
	if Config.SOUNDS.GrandmaLaugh ~= "rbxassetid://0" and head then
		local sound = Instance.new("Sound")
		sound.Name = "GrandmaLaugh"
		sound.SoundId = Config.SOUNDS.GrandmaLaugh
		sound.Volume = 0.4
		sound.RollOffMaxDistance = 30 -- тихо: слышно только рядом с ней
		sound.Parent = head
		laugh = sound
	end
	task.spawn(function()
		while model.Parent and truth[id] do
			task.wait(math.random(LAUGH_EVERY_MIN, LAUGH_EVERY_MAX))
			if not (model.Parent and truth[id]) then
				break
			end
			log("бабушка тихо смеётся")
			if laugh then
				laugh:Play()
			end
			for i = 1, 6 do
				turn(CFrame.Angles(math.rad(if i % 2 == 0 then 7 else -4), 0, 0))
				task.wait(0.12)
			end
			turn(CFrame.identity)
		end
	end)
end

function AnomalyService:GetHealth(): number
	return health
end

-- Урон автобусу с эскалацией (контролёр нашёл аномалии, V03; остановка по просьбе, V02). Настоящая функция — в :Start().
local damageNow = function(_amount: number) end
function AnomalyService:Damage(amount: number)
	damageNow(amount)
end

-- Мигнуть светом у всех: проклятие за высаженную «свою» (V01), призрак мигает (V04).
function AnomalyService:Flicker()
	Remotes.Event("AnomalyEscalated"):FireAllClients(hits, "LightsFlicker")
end

-- Тенге всем в рейсе и в итоги (бонус контролёра за чистый салон, V03).
function AnomalyService:Reward(amount: number)
	earnedPlus += amount
	payRiders(amount)
end

-- Есть ли в салоне аномалия этого типа (NightService: просьбы остановиться, V02).
function AnomalyService:HasAboard(kindId: string): boolean
	local passengers = registry.PassengerService
	local aboard: { [string]: Model } = if passengers then passengers:GetOnboard() else {}
	for id, kind in truth do
		if kind.Id == kindId and aboard[id] then
			return true
		end
	end
	return false
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
-- forced — Id аномалии особого пассажира (фальшивый контролёр, V03): без шанса, лимита и платы за проезд.
function AnomalyService:OnBoarded(id: string, model: Model, forced: string?): boolean
	tickets[id] = ticket(false)
	if forced then
		local kind = byId[forced]
		if not kind then
			return false
		end
		truth[id] = kind
		boardedAt[id] = atStop
		if kind.CueAttribute then
			model:SetAttribute(kind.CueAttribute, true)
		end
		log(`сел пассажир-аномалия: {kind.Name}`)
		return true
	end
	earnedPlus += Config.FARE_PER_PASSENGER -- плату начисляет PassengerService, здесь только считаем для итогов
	local count = 0
	for _ in truth do
		count += 1
	end
	local night = nightData()
	-- V11: к остановке FirstAnomalyByStop опасной ещё не было — этот пассажир будет ей без броска шанса.
	local byStop = night.FirstAnomalyByStop
	local guarantee = byStop ~= nil and not dangerousBoarded and atStop >= byStop
	if count >= Config.MAX_ANOMALIES_AT_ONCE or (not guarantee and math.random() >= night.AnomalyChance) then
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
	local kind = pickType(if guarantee then guaranteedPool(night.Anomalies) else night.Anomalies, originalId ~= nil)
	if not kind then
		return false
	end
	truth[id] = kind
	dangerousBoarded = dangerousBoarded or dangerous(kind)
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
	elseif kind.Id == "StrangeCoin" then
		tickets[id].Coin = STRANGE_COINS[math.random(#STRANGE_COINS)]
	elseif kind.Id == "Grandma" then
		grandmaLook(model)
		laughSometimes(id, model)
	elseif kind.Id == "Standing" and passengers then
		passengers:StandInAisle(id) -- в проходе в конце салона, спиной ко всем
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
		dangerousBoarded = false
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

	local function damage(amount: number)
		if health <= 0 then
			return
		end
		health = math.max(0, health - amount)
		hits += 1
		local effects = Config.ESCALATION_EFFECTS
		local effect = effects[math.min(hits, #effects)]
		escalated:FireAllClients(hits, effect)
		local scares, ghosts = registry.ScareEventService, registry.GhostService
		if scares then
			scares:OnEscalation(effect) -- Blackout → силуэт на заднем сиденье
		end
		if ghosts and effect == "Blackout" then
			ghosts:OnBlackout() -- с 4-й ночи: «замри»
		end
		log(`урон: прочность {health}`)
		if health <= 0 then
			onBroken()
		end
	end
	damageNow = damage

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
					damage(Config.ANOMALY_DAMAGE)
				end
			end
		end
	end)

	-- Кондуктор рядом с пассажиром в салоне? Возвращает модель или nil.
	local function conductorNear(player: Player, id: string): Model?
		local roles, ghosts = registry.RoleService, registry.GhostService
		if not table.find(riders(), player) or (roles and roles:GetDriver() == player) or (ghosts and ghosts:IsGhost(player)) then
			return nil -- призраку инструменты недоступны (V04)
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
		-- Правило ночи 4: на стоящего спиной не светить. Посветил — забирают (GhostService, V04) и правило нарушено.
		local kind = truth[passengerId]
		if tool == "Flashlight" and kind and kind.Id == "Standing" then
			local nights, ghosts = registry.NightService, registry.GhostService
			if nights then
				nights:BreakRule()
			end
			log(`посветили на стоящего: забирают {player.Name}`)
			if ghosts and ghosts.Take then
				ghosts:Take(player, "flashlight_standing")
			end
		end
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
			AnomalyService:Flicker()
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
