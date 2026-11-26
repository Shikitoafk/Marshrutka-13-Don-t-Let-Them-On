--!strict
-- Тестовая карта (greybox). Если в Workspace нет Map — строит из простых блоков дорогу,
-- 8 остановок и автобус с теми же именами, что в docs/ARCHITECTURE.md, чтобы остальной код
-- работал одинаково и с ней, и с настоящей картой. Есть Workspace.Map из Studio — ничего не делает.
-- Строим в Init: к :Start() любого сервиса карта уже на месте.

local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

-- Геометрия тестовой карты — не баланс, поэтому здесь, а не в Config.
-- Длина перегона = SEGMENTS_PER_LEG × POINT_SPACING. Сейчас ≈ 1440 studs ≈ 35 сек на автопилоте —
-- время найти аномалии. Для быстрых тестов можно уменьшить SEGMENTS_PER_LEG (3 ≈ 12 сек).
local SEGMENTS_PER_LEG = 9 -- отрезков дороги между остановками
local POINT_SPACING = 160 -- studs между точками
local CURVE_AMPLITUDE = 120 -- насколько дорога виляет вбок
local GROUND_TOP = 2 -- выше стандартного Baseplate (его верх на 0), чтобы поверхности не мерцали
local ROAD_TOP = GROUND_TOP + 0.2
local ROAD_WIDTH = 20

-- Автобус в своих координатах: вперёд = -Z (LookVector), право = +X (там двери и тротуар).
local BUS_LENGTH = 32
local BUS_WIDTH = 11
local FLOOR_TOP = 2 -- пол над дорогой, под ним колёса
local CABIN_HEIGHT = 9
local DOOR_WIDTH = 4
local DOOR_HEIGHT = 7
local FRONT_DOOR_Z = -10
local BACK_DOOR_Z = 8

local YELLOW = Color3.fromRGB(235, 190, 40)
local DARK = Color3.fromRGB(50, 50, 55)
local GLASS = Color3.fromRGB(150, 190, 210)
local SEAT = Color3.fromRGB(120, 40, 40)
local WARM = Color3.fromRGB(255, 214, 150)
local ASPHALT = Color3.fromRGB(40, 40, 45)
local GRASS = Color3.fromRGB(55, 65, 50)
local SIDEWALK = Color3.fromRGB(140, 140, 135)
local STOP_ZONE = Color3.fromRGB(255, 210, 0)
local SIGN = Color3.fromRGB(25, 70, 150)

local GreyboxService = {}

local function make(className: string, parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.Parent = parent
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Невидимый служебный блок: ни с чем не сталкивается, не мешает лучам и касаниям.
local function ghost(p: BasePart)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- Без материала Glass: сквозь него Roblox не рисует прозрачное (зоны остановок пропали бы из вида).
local function glass(p: BasePart, transparency: number)
	p.Transparency = transparency
end

local function buildBus(pivot: CFrame): Model
	local bus = Instance.new("Model")
	bus.Name = "Bus"

	-- Root — невидимый центр автобуса на уровне дороги; RouteService двигает только его.
	local root = make("Part", bus, "Root", Vector3.one, pivot, DARK)
	ghost(root)
	bus.PrimaryPart = root

	local function at(x: number, y: number, z: number): CFrame
		return pivot * CFrame.new(x, y, z)
	end

	local hw, hl = BUS_WIDTH / 2, BUS_LENGTH / 2
	local roofY = FLOOR_TOP + CABIN_HEIGHT
	local wallX = hw - 0.25
	local body = folder(bus, "Body")

	make("Part", body, "Floor", Vector3.new(BUS_WIDTH, 1, BUS_LENGTH), at(0, FLOOR_TOP - 0.5, 0), DARK)
	make("Part", body, "Roof", Vector3.new(BUS_WIDTH, 0.5, BUS_LENGTH), at(0, roofY + 0.25, 0), YELLOW)
	make("Part", body, "BackWall", Vector3.new(BUS_WIDTH, CABIN_HEIGHT, 0.5), at(0, FLOOR_TOP + CABIN_HEIGHT / 2, hl - 0.25), YELLOW)
	make("Part", body, "FrontPanel", Vector3.new(BUS_WIDTH, 3, 0.5), at(0, FLOOR_TOP + 1.5, -hl + 0.25), YELLOW)
	glass(make("Part", body, "Windshield", Vector3.new(BUS_WIDTH, CABIN_HEIGHT - 3, 0.5), at(0, FLOOR_TOP + 3 + (CABIN_HEIGHT - 3) / 2, -hl + 0.25), GLASS), 0.6)

	-- Боковая стена: низ сплошной, посередине окно, сверху полоса.
	local function sideWall(x: number, z0: number, z1: number)
		local len, z = z1 - z0, (z0 + z1) / 2
		make("Part", body, "Wall", Vector3.new(0.5, 4, len), at(x, FLOOR_TOP + 2, z), YELLOW)
		glass(make("Part", body, "Window", Vector3.new(0.5, 4, len), at(x, FLOOR_TOP + 6, z), GLASS), 0.6)
		make("Part", body, "Wall", Vector3.new(0.5, CABIN_HEIGHT - 8, len), at(x, FLOOR_TOP + 8 + (CABIN_HEIGHT - 8) / 2, z), YELLOW)
	end
	sideWall(-wallX, -hl + 0.5, hl - 0.5)
	-- справа (сторона тротуара) — проёмы под двери
	sideWall(wallX, -hl + 0.5, FRONT_DOOR_Z - DOOR_WIDTH / 2)
	sideWall(wallX, FRONT_DOOR_Z + DOOR_WIDTH / 2, BACK_DOOR_Z - DOOR_WIDTH / 2)
	sideWall(wallX, BACK_DOOR_Z + DOOR_WIDTH / 2, hl - 0.5)
	local doors: { [string]: number } = { DoorFront = FRONT_DOOR_Z, DoorBack = BACK_DOOR_Z }
	for name, z in doors do
		local above = CABIN_HEIGHT - DOOR_HEIGHT
		make("Part", body, "Wall", Vector3.new(0.5, above, DOOR_WIDTH), at(wallX, FLOOR_TOP + DOOR_HEIGHT + above / 2, z), YELLOW)
		glass(make("Part", bus, name, Vector3.new(0.3, DOOR_HEIGHT, DOOR_WIDTH), at(wallX, FLOOR_TOP + DOOR_HEIGHT / 2, z), GLASS), 0.3)
	end

	-- Колёса стоят мимо дверных проёмов.
	for _, x in { -hw + 0.5, hw - 0.5 } do
		for _, z in { -hl + 2.5, hl - 3.5 } do
			local wheel = make("Part", body, "Wheel", Vector3.new(1.5, 2.5, 2.5), at(x, 1.25, z), Color3.new(0.1, 0.1, 0.1)) :: Part
			wheel.Shape = Enum.PartType.Cylinder
			wheel.CanCollide = false
		end
	end

	make("Part", body, "Dashboard", Vector3.new(4, 2.5, 1.5), at(-3, FLOOR_TOP + 1.25, -hl + 1.25), DARK)
	make("Seat", bus, "DriverSeat", Vector3.new(2, 1, 2), at(-3, FLOOR_TOP + 0.5, -12), SEAT)

	-- 10 мест лицом вперёд: слева в ряд, справа между дверями; проход посередине шириной 5.
	local seats = folder(bus, "Seats")
	local slots: { Vector3 } = {}
	for k = 0, 5 do
		table.insert(slots, Vector3.new(-3.5, 0, -7 + 3.5 * k))
	end
	for k = 0, 3 do
		table.insert(slots, Vector3.new(3.5, 0, -5.5 + 3.5 * k))
	end
	for i, s in slots do
		make("Seat", seats, `Seat{i}`, Vector3.new(2, 1, 2), at(s.X, FLOOR_TOP + 0.5, s.Z), SEAT)
	end

	-- Зеркало у лобового стекла смотрит назад, в салон (камера зеркала = его CFrame).
	local mirror = make("Part", bus, "Mirror", Vector3.new(2, 0.6, 0.1), at(0, FLOOR_TOP + 8, -hl + 1) * CFrame.Angles(0, math.pi, 0), Color3.new(0.8, 0.8, 0.8))
	mirror.Reflectance = 0.5
	mirror.CanCollide = false

	-- Свет сам по себе в папке не светит, поэтому каждый PointLight — внутри плафона.
	local lights = folder(bus, "InteriorLights")
	for i, z in { -10, 0, 10 } do
		-- Тусклый свет (GDD «Страх»: темно, фонарь реально нужен): плафон без неонового свечения, лампа слабая.
		local lamp = make("Part", lights, `Lamp{i}`, Vector3.new(2, 0.2, 1.5), at(0, roofY - 0.1, z), WARM)
		lamp.Material = Enum.Material.SmoothPlastic
		lamp.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = WARM
		light.Range = 12
		light.Brightness = 0.5
		light.Shadows = false
		light.Parent = lamp
	end

	-- Автобус — одна сборка: всё приварено к Root, якорится только Root.
	-- Двери — через Weld, а не WeldConstraint, чтобы RouteService анимировал их через C0.
	for _, d in bus:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			if d.Name == "DoorFront" or d.Name == "DoorBack" then
				local weld = Instance.new("Weld")
				weld.Part0 = root
				weld.Part1 = d
				weld.C0 = pivot:ToObjectSpace(d.CFrame)
				weld.Parent = d
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = d
				weld.Parent = d
			end
			d.Anchored = false
		end
	end

	return bus
end

function GreyboxService:Init(_services: { [string]: any })
	if Workspace:FindFirstChild("Map") then
		return
	end

	local map = Instance.new("Folder")
	map.Name = "Map"

	-- Точки дороги: плавная «змейка» вдоль X, начало рядом с центром мира, где появляются игроки.
	local points: { Vector3 } = {}
	for i = 1, #Config.STOP_NAMES * SEGMENTS_PER_LEG + 1 do
		points[i] = Vector3.new(30 + (i - 1) * POINT_SPACING, ROAD_TOP, CURVE_AMPLITUDE * math.sin((i - 1) * 0.45))
	end

	local route = folder(map, "Route")
	local road = folder(map, "Road")
	-- асфальт и позади первой точки, где на старте стоит хвост автобуса
	local behind = points[1] + (points[1] - points[2]).Unit * 40
	local tail = make("Part", road, "Road", Vector3.new(ROAD_WIDTH, 0.4, 43), CFrame.lookAt((behind + points[1]) / 2, points[1]) * CFrame.new(0, -0.25, 0), ASPHALT)
	tail.Material = Enum.Material.Asphalt
	for i, p in points do
		ghost(make("Part", route, string.format("%03d", i), Vector3.one, CFrame.new(p), Color3.new(1, 0, 0)))
		local nextPoint = points[i + 1]
		if nextPoint then
			-- Куски дороги внахлёст (без щелей на поворотах); каждый второй чуть ниже, чтобы нахлёст не мерцал.
			local dip = if i % 2 == 0 then 0.05 else 0
			local piece = make("Part", road, "Road", Vector3.new(ROAD_WIDTH, 0.4, (nextPoint - p).Magnitude + 3), CFrame.lookAt((p + nextPoint) / 2, nextPoint) * CFrame.new(0, -0.2 - dip, 0), ASPHALT)
			piece.Material = Enum.Material.Asphalt
		end
	end

	-- Остановка k — в середине каждого SEGMENTS_PER_LEG-го отрезка; последняя (Конечная) — на последнем.
	local stops = folder(map, "Stops")
	for k, stopName in Config.STOP_NAMES do
		local a, b = points[k * SEGMENTS_PER_LEG], points[k * SEGMENTS_PER_LEG + 1]
		local cf = CFrame.lookAt((a + b) / 2, b)
		local zone = make("Part", stops, `Stop{k}`, Vector3.new(ROAD_WIDTH, 0.2, Config.STOP_ZONE_LENGTH), cf * CFrame.new(0, 0.1, 0), STOP_ZONE)
		zone.Transparency = 0.5
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone:SetAttribute("StopIndex", k)
		zone:SetAttribute("StopName", stopName)

		-- Тротуар справа по ходу движения — там ждут пассажиры (двери автобуса тоже справа).
		local spawn = make("Part", zone, "Spawn", Vector3.new(6, 0.6, Config.STOP_ZONE_LENGTH), cf * CFrame.new(ROAD_WIDTH / 2 + 4, GROUND_TOP + 0.3 - ROAD_TOP, 0), SIDEWALK)
		local sign = Instance.new("BillboardGui")
		sign.Size = UDim2.fromScale(16, 4) -- у BillboardGui Scale = studs
		sign.StudsOffset = Vector3.new(0, 7, 0)
		sign.MaxDistance = 400
		sign.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = SIGN
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Text = `{k}. {stopName}`
		label.Parent = sign
		sign.Parent = spawn
	end

	-- Земля: в совсем пустом плейсе иначе падать некуда. Part не бывает длиннее 2048, поэтому кусками.
	local first, last = points[1], points[#points]
	local startX, endX = first.X - 150, last.X + 150
	local tiles = math.ceil((endX - startX) / 2000)
	local tileLength = (endX - startX) / tiles
	for t = 1, tiles do
		make("Part", map, "Ground", Vector3.new(tileLength, 2, 2 * CURVE_AMPLITUDE + 400), CFrame.new(startX + tileLength * (t - 0.5), GROUND_TOP - 1, 0), GRASS)
	end

	local bus = buildBus(CFrame.lookAt(first, points[2]))
	bus.Parent = map

	-- Точка появления сзади-справа от автобуса, лицом к нему (депо сделает RoundService в T04).
	local spawnPos = Vector3.new(first.X - 35, GROUND_TOP + 0.5, first.Z + 15)
	local depot = make("SpawnLocation", map, "DepotSpawn", Vector3.new(8, 1, 8), CFrame.lookAt(spawnPos, Vector3.new(first.X, spawnPos.Y, first.Z)), SIDEWALK) :: SpawnLocation
	depot.Duration = 0

	-- Самопроверка: структура совпадает с договорённостью из ARCHITECTURE.md.
	assert(#route:GetChildren() == #points and #stops:GetChildren() == #Config.STOP_NAMES, "Greybox: маршрут собран не полностью")
	local seats = bus:FindFirstChild("Seats")
	assert(bus.PrimaryPart and seats and #seats:GetChildren() == 10 and bus:FindFirstChild("DriverSeat"), "Greybox: автобус собран не полностью")

	map.Parent = Workspace
	print(`[Greybox] Тестовая карта готова: {#points} точек, {#Config.STOP_NAMES} остановок, автобус с 10 местами`)
end

return GreyboxService
