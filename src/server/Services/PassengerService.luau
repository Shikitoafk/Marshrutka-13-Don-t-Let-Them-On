--!strict
-- Пассажиры. Появляются на остановке, когда она стала следующей (StopChanged Approaching). Когда на ней
-- открываются двери: сначала выходят те, кому сюда (или дальше), потом ждущие подходят к двери и садятся
-- на свободное место через Seat:Sit(). За каждого севшего — FARE_PER_PASSENGER всем игрокам рейса.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local NPC_WALK_SPEED = 12
local MAX_WALK_TIME = 4 -- сек: столько максимум идём к двери, потом садимся или остаёмся
local EXIT_TIME = 2 -- сек: вышедший отходит от автобуса и исчезает
local DOOR_STEP_OUT = 2 -- studs от двери наружу: куда подходят и откуда уходят
local AISLE_BACK_Z = 11 -- studs назад от центра автобуса: где в проходе стоит Standing (V02)
local STAND_STEP = 3

-- Цвета для простых пассажиров, если в ServerStorage.PassengerRigs пусто.
local SKIN = { Color3.fromRGB(234, 192, 158), Color3.fromRGB(198, 145, 105), Color3.fromRGB(141, 95, 64), Color3.fromRGB(255, 220, 190) }
local CLOTHES = { Color3.fromRGB(60, 70, 90), Color3.fromRGB(120, 40, 40), Color3.fromRGB(70, 90, 60), Color3.fromRGB(90, 90, 90), Color3.fromRGB(150, 120, 60), Color3.fromRGB(40, 40, 45) }

-- Особый пассажир (контролёр, V03): kind — Id аномалии, которой он станет (nil — человек, на аномалию не проверяем).
type Special = { kind: string?, onBoarded: (id: string) -> () }
type Passenger = { id: string, model: Model, humanoid: Humanoid, exitStop: number, keptExit: number?, seat: Seat?, special: Special?, standing: boolean? }

local PassengerService = {}

local registry: { [string]: any } = {}
local onboard: { [string]: Passenger } = {}
local waiting: { [number]: { Passenger } } = {} -- [номер остановки] = ждущие там
local reserved: { [Seat]: boolean } = {} -- места, занятые севшими и идущими к ним
local passengerLeft = Remotes.Event("PassengerLeft")

local function pick<T>(list: { T }): T
	return list[math.random(#list)]
end

-- Для разбора в Studio: «никто не сел» отличается от «пассажир не создался».
local function log(text: string)
	if RunService:IsStudio() then
		print(`[Passenger] {text}`)
	end
end

-- Модель пассажира: случайная из ServerStorage.PassengerRigs, иначе простой R15 случайных цветов.
local function makeModel(): Model?
	local rigs = ServerStorage:FindFirstChild("PassengerRigs")
	local options = if rigs then rigs:GetChildren() else {}
	if #options > 0 then
		local rig = pick(options)
		return if rig:IsA("Model") then rig:Clone() else nil
	end
	local description = Instance.new("HumanoidDescription")
	local skin, legs = pick(SKIN), pick(CLOTHES)
	description.HeadColor, description.LeftArmColor, description.RightArmColor = skin, skin, skin
	description.TorsoColor = pick(CLOTHES)
	description.LeftLegColor, description.RightLegColor = legs, legs
	local ok, model = pcall(Players.CreateHumanoidModelFromDescriptionAsync, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn(`[PassengerService] Не удалось создать пассажира: {model}`)
		return nil
	end
	return model
end

-- Снять с сиденья сразу (PivotTo сидящего утащил бы автобус) и освободить место.
local function unseat(p: Passenger)
	local seatPart = p.humanoid.SeatPart
	local weld = if seatPart then seatPart:FindFirstChild("SeatWeld") else nil
	if weld then
		weld:Destroy()
	end
	local body = p.model:FindFirstChild("HumanoidRootPart")
	local stand = if body then body:FindFirstChild("StandWeld") else nil
	if stand then
		stand:Destroy() -- стоявший в проходе приварен к автобусу: иначе PivotTo утащил бы автобус
		p.humanoid.PlatformStand = false
	end
	p.humanoid.Sit = false
	if p.seat then
		reserved[p.seat] = nil
		p.seat = nil
	end
end

-- Убрать всех пассажиров (конец рейса).
function PassengerService:Clear()
	for id, p in onboard do
		passengerLeft:FireAllClients(id, "Vanished")
		p.model:Destroy()
	end
	table.clear(onboard)
	table.clear(reserved)
	for _, list in waiting do
		for _, p in list do
			p.model:Destroy()
		end
		table.clear(list)
	end
end

-- Модель севшего пассажира по PassengerId; nil — такого в салоне нет.
function PassengerService:GetModel(id: string): Model?
	local p = onboard[id]
	return if p then p.model else nil
end

-- Все севшие: [PassengerId] = модель (копия таблицы).
function PassengerService:GetOnboard(): { [string]: Model }
	local result: { [string]: Model } = {}
	for id, p in onboard do
		result[id] = p.model
	end
	return result
end

-- Не выпускать на его остановке (аномалия; оригинал двойника — без него двойника не вычислить).
function PassengerService:KeepAboard(id: string)
	local p = onboard[id]
	if p and not p.keptExit then
		p.keptExit = p.exitStop
		p.exitStop = math.huge
	end
end

-- Снова обычный пассажир: выйдет на своей остановке (или при следующем открытии дверей, если её уже проехали).
function PassengerService:ReleaseAboard(id: string)
	local p = onboard[id]
	if p and p.keptExit then
		p.exitStop = p.keptExit
		p.keptExit = nil
	end
end

-- Высадить (кондуктор): вылетает за дверь, PassengerLeft("Ejected"). false — такого в салоне нет.
local ejectNow = function(_id: string): boolean
	return false
end
function PassengerService:Eject(id: string): boolean
	return ejectNow(id)
end

-- Особый пассажир на остановке stop (зовите на её Approaching): садится первым, без платы за проезд,
-- выходит на следующей (если kind — аномалия, то только когда высадят). dress одевает модель. Возвращает PassengerId.
local spawnSpecialNow = function(_stop: number, _dress: (Model) -> (), _special: Special): string?
	return nil
end
function PassengerService:SpawnSpecial(stop: number, dress: (Model) -> (), kind: string?, onBoarded: (id: string) -> ()): string?
	return spawnSpecialNow(stop, dress, { kind = kind, onBoarded = onBoarded })
end

-- Встать в проходе в конце салона спиной ко всем (аномалия Standing, V02): место освобождается,
-- пассажир приварен к автобусу, чтобы на ходу не сносило.
local standNow = function(_id: string) end
function PassengerService:StandInAisle(id: string)
	standNow(id)
end

function PassengerService:Init(services: { [string]: any })
	registry = services
end

function PassengerService:Start()
	local route = registry.RouteService
	local map = Workspace:WaitForChild("Map")
	local bus = map:WaitForChild("Bus") :: Model
	local root = bus.PrimaryPart
	local seatsFolder = bus:FindFirstChild("Seats")
	if not (route and root and seatsFolder) then
		warn("[PassengerService] Нет RouteService, Bus.PrimaryPart или Bus.Seats — пассажиров не будет")
		return
	end
	local passengersFolder = bus:FindFirstChild("Passengers")
	if not passengersFolder then
		local created = Instance.new("Folder")
		created.Name = "Passengers"
		created.Parent = bus
		passengersFolder = created
	end

	local zones: { [number]: BasePart } = {}
	local lastStop = 0
	for _, zone in map:WaitForChild("Stops"):GetChildren() do
		local index = zone:GetAttribute("StopIndex")
		if zone:IsA("BasePart") and type(index) == "number" then
			zones[index] = zone
			lastStop = math.max(lastStop, index)
		end
	end

	local passengerBoarded = Remotes.Event("PassengerBoarded")
	local currentStop: number? = nil
	local doorsOpen = false

	-- Точка у ближайшей двери снаружи (двери на правом борту).
	local function doorOutside(from: Vector3): Vector3
		local best, bestGap = root.Position, math.huge
		for _, name in { "DoorFront", "DoorBack" } do
			local door = bus:FindFirstChild(name)
			if door and door:IsA("PVInstance") then
				local spot = door:GetPivot().Position + root.CFrame.RightVector * DOOR_STEP_OUT
				if (spot - from).Magnitude < bestGap then
					best, bestGap = spot, (spot - from).Magnitude
				end
			end
		end
		return best
	end

	local function freeSeat(): Seat?
		local taken = 0
		for _ in reserved do
			taken += 1
		end
		if taken >= Config.MAX_PASSENGERS_ON_BUS then
			return nil
		end
		-- Только по своим резервам: Occupant обновляется не сразу после того, как кто-то встал.
		for _, seat in seatsFolder:GetChildren() do
			if seat:IsA("Seat") and not reserved[seat] then
				return seat
			end
		end
		return nil
	end

	local function payFare()
		local round, data = registry.RoundService, registry.DataService
		if not (round and data) then
			return
		end
		for _, player in round:GetRiders() do
			task.spawn(function() -- AddTenge может ждать загрузки профиля
				if not data:AddTenge(player, Config.FARE_PER_PASSENGER) and RunService:IsStudio() then
					warn(`[Passenger] Тенге не начислены {player.Name}: профиль недоступен (плейс не опубликован или выключен доступ к API)`)
				end
			end)
		end
	end

	local function spawnWaiter(stop: number, dress: ((Model) -> ())?, special: Special?): string?
		local zone = zones[stop]
		local spawnPart = if zone then zone:FindFirstChild("Spawn") else nil
		if not (zone and spawnPart and spawnPart:IsA("BasePart")) then
			return nil
		end
		local model = makeModel()
		local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
		local body = if model then model:FindFirstChild("HumanoidRootPart") else nil
		if not (model and humanoid and body and body:IsA("BasePart")) then
			if model then
				model:Destroy()
			end
			return nil
		end
		if dress then
			dress(model)
		end
		local id = HttpService:GenerateGUID(false)
		model.Name = "Passenger"
		model:SetAttribute("PassengerId", id)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.WalkSpeed = NPC_WALK_SPEED
		-- Стоит вдоль тротуара лицом к дороге.
		local along = (math.random() - 0.5) * math.max(spawnPart.Size.Z - 2, 0)
		model:PivotTo(spawnPart.CFrame * CFrame.new(0, spawnPart.Size.Y / 2 + 3, along) * CFrame.Angles(0, math.pi / 2, 0))
		model.Parent = zone
		pcall(body.SetNetworkOwner, body, nil) -- ходит сервер, а не ближайший игрок
		waiting[stop] = waiting[stop] or {}
		local exitStop = if special then math.min(stop + 1, lastStop) else math.random(stop + 1, lastStop)
		local p: Passenger = { id = id, model = model, humanoid = humanoid, exitStop = exitStop, keptExit = nil, seat = nil, special = special }
		table.insert(waiting[stop], if special then 1 else #waiting[stop] + 1, p) -- особый — первым, чтобы точно хватило места
		return id
	end
	spawnSpecialNow = function(stop: number, dress: (Model) -> (), special: Special): string?
		return spawnWaiter(stop, dress, special)
	end

	-- Пол салона — от низа сиденья (как в RoundService): работает и с настоящим автобусом.
	local floorY = 0
	for _, seat in seatsFolder:GetChildren() do
		if seat:IsA("BasePart") then
			floorY = root.CFrame:PointToObjectSpace(seat.Position).Y - seat.Size.Y / 2
			break
		end
	end
	local standing = 0
	standNow = function(id: string)
		local p = onboard[id]
		local body = if p then p.model:FindFirstChild("HumanoidRootPart") else nil
		if not (p and body and body:IsA("BasePart")) then
			return
		end
		unseat(p)
		p.standing = true
		standing += 1
		local back = AISLE_BACK_Z - STAND_STEP * ((standing - 1) % 3) -- не друг в друге, если стоящих несколько
		local height = floorY + p.humanoid.HipHeight + body.Size.Y / 2
		-- Вперёд у автобуса — −Z; поворот на 180° — лицом к задней стенке, спиной к салону.
		p.model:PivotTo(root.CFrame * CFrame.new(0, height, back) * CFrame.Angles(0, math.pi, 0))
		p.humanoid.AutoRotate = false
		p.humanoid.PlatformStand = true -- иначе Humanoid держит равновесие силами и толкает автобус, к которому приварен
		local weld = Instance.new("WeldConstraint")
		weld.Name = "StandWeld"
		weld.Part0, weld.Part1 = root, body
		weld.Parent = body
	end

	local function board(p: Passenger, stop: number)
		local seat = freeSeat()
		if not seat then
			return -- мест нет: остаётся на остановке
		end
		reserved[seat] = true
		p.seat = seat
		task.spawn(function()
			local target = doorOutside(p.model:GetPivot().Position)
			p.humanoid:MoveTo(target)
			task.wait(math.clamp((target - p.model:GetPivot().Position).Magnitude / NPC_WALK_SPEED, 0.5, MAX_WALK_TIME))
			local list = waiting[stop]
			local index = if list then table.find(list, p) else nil
			if not (p.model.Parent and index and doorsOpen and currentStop == stop and p.seat == seat) then
				if p.seat == seat then
					reserved[seat] = nil -- не успел: двери закрылись или рейс сброшен
					p.seat = nil
					log(`Остановка {stop}: пассажир не успел сесть`)
				end
				return
			end
			table.remove(waiting[stop], index)
			p.model:PivotTo(seat.CFrame + Vector3.new(0, 3, 0)) -- рядом с сиденьем, потом Sit (ещё не приварен — можно)
			p.model.Parent = passengersFolder
			onboard[p.id] = p
			-- Кем он будет, решаем ДО Sit: детали внешности (платок бабушки) нельзя приваривать к уже сидящему —
			-- он сварен с автобусом, и автобус уводит с дороги (проверено в Studio).
			-- Аномалия сама не выходит: едет, пока её не высадят. Особый пассажир едет бесплатно, его тип задан заранее.
			local anomalies = registry.AnomalyService
			local special = p.special
			if special then
				if special.kind and anomalies and anomalies:OnBoarded(p.id, p.model, special.kind) then
					PassengerService:KeepAboard(p.id)
				end
			elseif anomalies and anomalies:OnBoarded(p.id, p.model) then
				PassengerService:KeepAboard(p.id)
			end
			if not p.standing then
				seat:Sit(p.humanoid)
			end
			passengerBoarded:FireAllClients(p.id)
			if special then
				special.onBoarded(p.id)
			else
				payFare()
			end
			log(`Остановка {stop}: сел пассажир (выйдет на {p.exitStop})`)
		end)
	end

	local function exitBus(p: Passenger, reason: string)
		onboard[p.id] = nil
		unseat(p)
		passengerLeft:FireAllClients(p.id, reason)
		log(`{reason}: пассажир покинул автобус`)
		local outside = doorOutside(p.model:GetPivot().Position)
		p.model.Parent = map -- из папки Passengers: инструменты кондуктора на него больше не действуют
		p.model:PivotTo(CFrame.lookAt(outside, outside + root.CFrame.RightVector))
		p.humanoid:MoveTo(outside + root.CFrame.RightVector * 10)
		task.delay(EXIT_TIME, function()
			p.model:Destroy()
		end)
	end
	ejectNow = function(id: string): boolean
		local p = onboard[id]
		if not p then
			return false
		end
		exitBus(p, "Ejected")
		return true
	end

	route.StopChanged:Connect(function(index: number, _name: string, phase: string)
		if phase == "Approaching" and index < lastStop then
			for _ = 1, math.random(Config.PASSENGERS_PER_STOP_MIN, Config.PASSENGERS_PER_STOP_MAX) do
				spawnWaiter(index)
			end
			log(`Остановка {index}: ждут {if waiting[index] then #waiting[index] else 0}`)
		elseif phase == "AtStop" then
			currentStop = index
		elseif phase == "Departed" then
			currentStop = nil
			local left = waiting[index]
			if left then
				for _, p in left do
					p.model:Destroy() -- автобус уехал без них
				end
			end
			waiting[index] = nil
		end
	end)

	route.DoorsChanged:Connect(function(open: boolean)
		doorsOpen = open
		local stop = currentStop
		if not (open and stop) then
			return
		end
		-- Сначала выходят (освобождают места): кому сюда, и кто проехал свою остановку при закрытых дверях.
		for _, p in onboard do
			if p.exitStop <= stop then
				exitBus(p, "Exited")
			end
		end
		local list = waiting[stop]
		if list then
			for _, p in table.clone(list) do
				board(p, stop)
			end
		end
	end)
end

return PassengerService
