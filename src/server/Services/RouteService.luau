--!strict
-- Маршрутка едет по точкам Map.Route: скорость от водителя или автопилота, зоны остановок → StopChanged,
-- двери, BusState. Автобус — физическая сборка: его двигает LinearVelocity, а не телепорт через CFrame.
-- Поэтому у пола настоящая скорость, и стоящих в салоне игроков Roblox везёт сам — без клиентских скриптов.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local WHEELBASE = 20 -- studs между «осями»: поворот растягивается на эту длину, без рывков
local POSITION_GAIN = 10 -- как быстро гасим отклонение от дороги (1/сек)
local STOPPED_SPEED = 1 -- медленнее — считаем, что стоим (так же проверяем двери)
local DOOR_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad)
local DOOR_SLIDE_OUT = 0.4 -- открытая дверь отъезжает наружу, чтобы не входить в стену
local DOOR_COOLDOWN = 0.7
local BUS_STATE_INTERVAL = 0.2 -- BusState не чаще 5 раз/сек
local HORN_COOLDOWN = 1
local START_DELAY = 3 -- сек после старта рейса: игроков сажают в автобус, пусть встанут на места

type Stop = { index: number, name: string, from: number, center: number, to: number, served: boolean }
type Door = { weld: Weld, closed: CFrame, open: CFrame }

local RouteService = {}

local registry: { [string]: any } = {}
local path: { Vector3 } = {}
local along: { number } = {} -- along[i] — сколько studs по дороге от первой точки до i-й

-- Сигналы для других серверных сервисов (клиентам уходят ремоуты): StopChanged(index, name, phase), DoorsChanged(open).
local stopSignal = Instance.new("BindableEvent")
local doorsSignal = Instance.new("BindableEvent")
RouteService.StopChanged = stopSignal.Event
RouteService.DoorsChanged = doorsSignal.Event

-- Управление рейсом для RoundService; настоящие функции появляются в :Start(), когда автобус найден.
local startRun = function() end
local resetRun = function() end
local isFinished = function(): boolean
	return false
end

-- Начать рейс с места, где стоит автобус (после ResetRun — с начала маршрута).
function RouteService:StartRun()
	startRun()
end

-- Вернуть автобус на старт для нового рейса. Только когда в салоне никого: автобус переносится телепортом.
function RouteService:ResetRun()
	resetRun()
end

-- Доехали до конечной?
function RouteService:IsFinished(): boolean
	return isFinished()
end

-- Точка на дороге в d studs от начала; за концами — продолжение крайнего отрезка.
local function positionAt(d: number): Vector3
	local n = #path
	if d <= 0 then
		return path[1] + (path[2] - path[1]).Unit * d
	end
	for i = 2, n do
		if d <= along[i] then
			return path[i - 1]:Lerp(path[i], (d - along[i - 1]) / (along[i] - along[i - 1]))
		end
	end
	return path[n] + (path[n] - path[n - 1]).Unit * (d - along[n])
end

-- Сколько studs по дороге до места, ближайшего к точке p.
local function distanceAlong(p: Vector3): number
	local best, bestGap = 0, math.huge
	for i = 2, #path do
		local a, ab = path[i - 1], path[i] - path[i - 1]
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		local gap = (a + ab * t - p).Magnitude
		if gap < bestGap then
			best, bestGap = along[i - 1] + ab.Magnitude * t, gap
		end
	end
	return best
end

-- Положение автобуса: «передняя ось» и «задняя ось» на дороге, центр между ними, нос вперёд.
local function poseAt(d: number): CFrame
	local front, rear = positionAt(d + WHEELBASE / 2), positionAt(d - WHEELBASE / 2)
	return CFrame.lookAt((front + rear) / 2, front)
end

function RouteService:Init(services: { [string]: any })
	registry = services
end

function RouteService:Start()
	local map = Workspace:WaitForChild("Map")
	local bus = map:WaitForChild("Bus") :: Model
	local root = bus.PrimaryPart
	if not root then
		warn("[RouteService] У Map.Bus нет PrimaryPart — автобус не поедет")
		return
	end

	-- Дорога: точки Route по порядку номеров, совпадающие подряд пропускаем (иначе деление на 0).
	local points: { BasePart } = {}
	for _, child in map:WaitForChild("Route"):GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	for _, part in points do
		local p = part.Position
		if #path == 0 then
			path[1], along[1] = p, 0
		elseif (p - path[#path]).Magnitude > 0.01 then
			table.insert(along, along[#along] + (p - path[#path]).Magnitude)
			table.insert(path, p)
		end
	end
	assert(#path >= 2, "[RouteService] В Map.Route меньше двух точек")

	-- Остановки: проецируем центр зоны на дорогу; длина зоны по ходу движения — её Size.Z.
	local stops: { Stop } = {}
	for _, zone in map:WaitForChild("Stops"):GetChildren() do
		local index, name = zone:GetAttribute("StopIndex"), zone:GetAttribute("StopName")
		if zone:IsA("BasePart") and type(index) == "number" and type(name) == "string" then
			local center = distanceAlong(zone.Position)
			local half = zone.Size.Z / 2
			table.insert(stops, { index = index, name = name, from = center - half, center = center, to = center + half, served = false })
		end
	end
	table.sort(stops, function(a, b)
		return a.index < b.index
	end)
	-- Самопроверка: остановки 1..N идут по ходу движения.
	assert(#stops > 0, "[RouteService] В Map.Stops нет зон с StopIndex/StopName")
	for k, s in stops do
		assert(s.index == k and (k == 1 or s.center > stops[k - 1].center), `[RouteService] Остановка {k} стоит не по порядку вдоль Route`)
	end

	-- Двери на Weld: открыть = сдвинуть C0 наружу и назад вдоль борта на ширину двери.
	local doors: { Door } = {}
	for _, doorName in { "DoorFront", "DoorBack" } do
		local door = bus:FindFirstChild(doorName)
		local weld = (if door then door:FindFirstChildWhichIsA("Weld", true) else nil) :: Weld?
		local part = if weld then weld.Part1 else nil
		if weld and part then
			table.insert(doors, { weld = weld, closed = weld.C0, open = CFrame.new(DOOR_SLIDE_OUT, 0, part.Size.Z) * weld.C0 })
		else
			warn(`[RouteService] У {doorName} нет Weld — дверь не будет двигаться`)
		end
	end

	-- Физика: скорость задаём в центре масс (иначе автобус клюёт носом при разгоне), курс держит AlignOrientation.
	bus:PivotTo(poseAt(0))
	local attachment = Instance.new("Attachment")
	attachment.Name = "RouteDrive"
	attachment.Parent = root
	attachment.WorldPosition = root.AssemblyCenterOfMass
	local offset = attachment.Position
	local drive = Instance.new("LinearVelocity")
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drive.MaxForce = math.huge
	drive.VectorVelocity = Vector3.zero
	drive.Parent = root
	local heading = Instance.new("AlignOrientation")
	heading.Mode = Enum.OrientationAlignmentMode.OneAttachment
	heading.Attachment0 = attachment
	heading.RigidityEnabled = true
	heading.MaxTorque = math.huge
	heading.MaxAngularVelocity = math.huge
	heading.CFrame = poseAt(0)
	heading.Parent = root
	root.Anchored = false
	local ok, err = pcall(root.SetNetworkOwner, root, nil)
	if not ok then
		warn(`[RouteService] Не удалось отдать автобус серверу (заякорены другие детали?): {err}`)
	end

	local distance, speed, throttle = 0, 0, 0
	local doorsOpen, running, finished = false, false, false
	local dwellUntil, departAt, lastDoorsAt = 0, 0, 0
	local nextStop = 1
	local lastDriver: Player? = nil
	local lastStop: Stop? = nil
	local lastPhase = ""

	local stopChanged = Remotes.Event("StopChanged")
	local busState = Remotes.Event("BusState")

	-- shortcut: водителя назначает RoleService (T04); пока его нет — всегда автопилот.
	local function getDriver(): Player?
		local roles = registry.RoleService
		return if roles and roles.GetDriver then roles:GetDriver() else nil
	end

	-- shortcut: прочность ведёт AnomalyService (T07); пока его нет — полная.
	local function getHealth(): number
		local anomalies = registry.AnomalyService
		return if anomalies and anomalies.GetHealth then anomalies:GetHealth() else Config.BUS_MAX_HEALTH
	end

	local function announce(s: Stop, phase: string)
		lastStop, lastPhase = s, phase
		stopChanged:FireAllClients(s.index, s.name, phase)
		stopSignal:Fire(s.index, s.name, phase)
		if RunService:IsStudio() then
			print(`[Route] Остановка {s.index} «{s.name}»: {phase}`) -- HUD покажет это только с RoundService (T04)
		end
	end

	local function setDoors(open: boolean)
		if open == doorsOpen then
			return
		end
		doorsOpen = open
		if open then
			dwellUntil = time() + Config.STOP_DOOR_TIME
		else
			departAt = time() + DOOR_TWEEN.Time -- не трогаемся, пока двери не закрылись
		end
		for _, door in doors do
			TweenService:Create(door.weld, DOOR_TWEEN, { C0 = if open then door.open else door.closed }):Play()
		end
		doorsSignal:Fire(open)
	end

	-- Зашедший посреди рейса сразу видит, какая остановка.
	Players.PlayerAdded:Connect(function(player)
		if lastStop then
			stopChanged:FireClient(player, lastStop.index, lastStop.name, lastPhase)
		end
	end)

	Remotes.Event("DriverInput").OnServerEvent:Connect(function(player: Player, value: unknown)
		-- value == value отсекает NaN: с ним автобус улетел бы в никуда
		if player == getDriver() and type(value) == "number" and value == value then
			throttle = math.clamp(value, -1, 1)
		end
	end)

	Remotes.Event("DoorsRequest").OnServerEvent:Connect(function(player: Player, open: unknown)
		if player ~= getDriver() or type(open) ~= "boolean" or speed >= STOPPED_SPEED or time() - lastDoorsAt < DOOR_COOLDOWN then
			return
		end
		lastDoorsAt = time()
		setDoors(open)
	end)

	-- Сигнал: только водитель, не чаще раза в секунду. Звук играет на сервере — слышат все.
	local horn: Sound? = nil
	if Config.SOUNDS.Horn ~= "rbxassetid://0" then -- пока ID не вписан, звука нет (и нет ошибки загрузки)
		local sound = Instance.new("Sound")
		sound.Name = "Horn"
		sound.SoundId = Config.SOUNDS.Horn
		sound.Parent = root
		horn = sound
	end
	local lastHornAt = 0
	Remotes.Event("HornRequest").OnServerEvent:Connect(function(player: Player)
		if player ~= getDriver() or time() - lastHornAt < HORN_COOLDOWN then
			return
		end
		lastHornAt = time()
		if horn then
			horn:Play()
		end
		if RunService:IsStudio() then
			print("[Route] Сигнал")
		end
	end)

	local sinceBusState, sinceLog = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceBusState += dt
		if sinceBusState >= BUS_STATE_INTERVAL then
			sinceBusState = 0
			busState:FireAllClients(speed, getHealth(), doorsOpen)
		end

		local s = stops[nextStop]
		if running and not finished and s then
			local driver = getDriver()
			if driver ~= lastDriver then
				lastDriver, throttle = driver, 0
			end

			if doorsOpen or time() < departAt then
				speed = 0 -- с открытыми дверями не едем
				if doorsOpen and not driver and time() >= dwellUntil then
					setDoors(false)
				end
			else
				-- Автопилот едет к ближайшей необслуженной остановке, водитель — свободно, но у конечной тормозим сами.
				local goal = if driver then stops[#stops] elseif s.served then stops[nextStop + 1] else s
				local accel = Config.BUS_ACCEL
				if driver then
					accel = if throttle > 0
						then Config.BUS_ACCEL * throttle
						elseif throttle < 0 then Config.BUS_BRAKE * throttle
						else -Config.BUS_IDLE_DECEL
				end
				local brakingCap = math.sqrt(2 * Config.BUS_BRAKE * math.max(goal.center - distance, 0))
				speed = math.clamp(math.min(speed + accel * dt, brakingCap), 0, Config.BUS_MAX_SPEED)
				distance += speed * dt
			end

			if distance > s.to then
				announce(s, "Departed")
				nextStop += 1
				announce(stops[nextStop], "Approaching")
			elseif distance >= s.from and speed < STOPPED_SPEED and not s.served then
				s.served = true
				announce(s, "AtStop")
				if nextStop == #stops then
					finished, speed = true, 0 -- конечная: рейс окончен, Departed не будет
					setDoors(true)
				elseif not driver then
					setDoors(true)
				end
			end
		end

		-- Скорость по дороге + мягкая поправка к точной позиции; на стоянке держит автобус на месте.
		local pose = poseAt(distance)
		local target = pose:PointToWorldSpace(offset)
		drive.VectorVelocity = pose.LookVector * speed + (target - attachment.WorldPosition) * POSITION_GAIN
		heading.CFrame = pose

		-- Для разбора в Studio: если игроков в салоне будет сносить, эти строки покажут почему.
		sinceLog += dt
		if RunService:IsStudio() and speed > 0 and sinceLog >= 2 then
			sinceLog = 0
			print(string.format("[Route] скорость %.1f, факт %.1f, отклонение %.2f studs", speed, root.AssemblyLinearVelocity.Magnitude, (target - attachment.WorldPosition).Magnitude))
		end
	end)

	startRun = function()
		running, finished = true, false
		departAt = time() + START_DELAY
		announce(stops[1], "Approaching")
	end
	resetRun = function()
		running, finished = false, false
		distance, speed, throttle, nextStop = 0, 0, 0, 1
		lastStop = nil
		for _, s in stops do
			s.served = false
		end
		setDoors(false)
		bus:PivotTo(poseAt(0))
	end
	isFinished = function(): boolean
		return finished
	end
end

return RouteService
