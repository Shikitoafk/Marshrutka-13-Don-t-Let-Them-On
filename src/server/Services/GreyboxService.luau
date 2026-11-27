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

-- Ночной город вокруг дороги (T20). Только декор: Anchored, без запросов и касаний, без теней (телефоны).
local CITY_SEED = 1313 -- один и тот же город при каждом запуске
local LAMP_STEP = 120 -- studs между фонарными столбами
local RANDOM_LIGHTS_MAX = 4 -- горящие где-то на перегоне; плюс у каждой остановки свой фонарь у навеса; остальные столбы тёмные
local LIGHTS_LIMIT = 25 -- всего источников света на карте вместе с салоном (телефоны)
local SIGN_OFFSET = 10.5 -- табличка с названием над центром тротуара: её низ выше крыши навеса, иначе крыша и столбы режут надпись
local FLICKER_LIGHTS = 4 -- сколько горящих фонарей мигает
local HOUSE_DARK = { Color3.fromRGB(28, 28, 32), Color3.fromRGB(36, 34, 33), Color3.fromRGB(24, 27, 30), Color3.fromRGB(40, 38, 42) }
local WINDOW_LIT = { Color3.fromRGB(255, 200, 110), Color3.fromRGB(150, 190, 255), Color3.fromRGB(255, 170, 90) }
local SODIUM = Color3.fromRGB(255, 170, 90) -- натриевый фонарь
local METAL = Color3.fromRGB(45, 45, 50)
local WOOD = Color3.fromRGB(60, 45, 35)

local function decor(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean?): BasePart
	local p = make("Part", parent, name, size, cframe, color)
	p.CanQuery = false
	p.CanTouch = false
	p.CanCollide = solid == true
	p.CastShadow = false
	return p
end

-- Мигание: свет почти всё время горит и изредка гаснет на миг. Без скриптов в карте — цикл в этом сервисе.
local function flicker(light: PointLight, head: BasePart, rng: Random)
	task.spawn(function()
		while light.Parent do
			task.wait(if light.Enabled then rng:NextNumber(0.4, 4) else rng:NextNumber(0.05, 0.3))
			light.Enabled = not light.Enabled
			head.Material = if light.Enabled then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end)
end

local function buildCity(map: Instance, points: { Vector3 }, stopFrames: { CFrame })
	local rng = Random.new(CITY_SEED)
	local city = folder(map, "City")

	-- Положение на дороге в d studs от начала: CFrame смотрит по ходу, право = +X (сторона остановок).
	local function roadFrame(d: number): CFrame
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local len = (b - a).Magnitude
			if d <= len or i == #points - 1 then
				return CFrame.lookAt(a:Lerp(b, math.clamp(d / len, 0, 1)), b)
			end
			d -= len
		end
		return CFrame.new(points[1])
	end
	local total = 0
	for i = 1, #points - 1 do
		total += (points[i + 1] - points[i]).Magnitude
	end
	local function nearStop(frame: CFrame, radius: number): boolean
		for _, s in stopFrames do
			if (s.Position - frame.Position).Magnitude < radius then
				return true
			end
		end
		return false
	end
	local ground = GROUND_TOP - ROAD_TOP -- высота земли относительно поверхности дороги

	-- Дома: тёмные коробки разной высоты по обе стороны, у некоторых светится окно-другое. Не ближе 32 и не дальше ~90 studs.
	for d = 30, total, 55 do
		local frame = roadFrame(d)
		if not nearStop(frame, 60) then
			for _, side in { -1, 1 } do
				if rng:NextNumber() < 0.8 then
					local w, depth, h = rng:NextNumber(14, 26), rng:NextNumber(12, 22), rng:NextNumber(10, 40)
					local edge = rng:NextNumber(32, 60)
					local house = decor(city, "House", Vector3.new(depth, h, w), frame * CFrame.new(side * (edge + depth / 2), ground + h / 2, 0), HOUSE_DARK[rng:NextInteger(1, #HOUSE_DARK)], true)
					if rng:NextNumber() < 0.3 then
						for _ = 1, rng:NextInteger(1, 2) do
							local spot = CFrame.new(-side * (depth / 2 + 0.1), rng:NextNumber(3, h - 3) - h / 2, rng:NextNumber(-w / 2 + 2, w / 2 - 2))
							decor(city, "Window", Vector3.new(0.2, 2.5, 2), house.CFrame * spot, WINDOW_LIT[rng:NextInteger(1, #WINDOW_LIT)]).Material = Enum.Material.Neon
						end
					end
				end
			end
		end
	end

	-- Заборы вдоль дороги (местами), телеграфные столбы справа за тротуаром.
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local mid = CFrame.lookAt((a + b) / 2, b)
		if not nearStop(mid, 90) then
			for _, side in { -1, 1 } do
				if rng:NextNumber() < 0.4 then
					decor(city, "Fence", Vector3.new(0.3, 3.5, (b - a).Magnitude * 0.8), mid * CFrame.new(side * 24, ground + 1.75, 0), WOOD, true)
				end
			end
			decor(city, "Pole", Vector3.new(0.7, 18, 0.7), mid * CFrame.new(26, ground + 9, 0), WOOD, true)
		end
	end

	-- Фонарь: столб + кронштейн + плафон над краем дороги; side = -1 слева, 1 справа (сторона остановок).
	local function lamp(frame: CFrame, side: number): BasePart
		decor(city, "LampPost", Vector3.new(0.5, 14, 0.5), frame * CFrame.new(side * 12, ground + 7, 0), METAL, true)
		decor(city, "LampArm", Vector3.new(4, 0.3, 0.3), frame * CFrame.new(side * 10, ground + 13.8, 0), METAL)
		return decor(city, "LampHead", Vector3.new(1.6, 0.5, 0.9), frame * CFrame.new(side * 8.2, ground + 13.5, 0), METAL)
	end
	local flickering = 0
	local function lightUp(head: BasePart)
		head.Color = SODIUM
		head.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = SODIUM
		light.Range = 40
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = head
		if flickering < FLICKER_LIGHTS and rng:NextNumber() < 0.3 then
			flickering += 1
			flicker(light, head, rng)
		end
	end

	-- Фонари слева через LAMP_STEP: почти все тёмные, изредка горят на перегоне. У остановок светит свой фонарь у навеса.
	local randomLit = 0
	for d = 0, total, LAMP_STEP do
		local frame = roadFrame(d)
		local head = lamp(frame, -1)
		if not nearStop(frame, 80) and randomLit < RANDOM_LIGHTS_MAX and rng:NextNumber() < 0.1 then
			randomLit += 1
			lightUp(head)
		end
	end

	-- Остановки: навес с лавкой и табличкой за тротуаром; у тематических — свои декорации.
	for k, frame in stopFrames do
		local name = Config.STOP_NAMES[k]
		local walk = 0.4 -- верх тротуара относительно дороги
		decor(city, "ShelterWall", Vector3.new(0.4, 7, 12), frame * CFrame.new(19.5, walk + 3.5, 0), METAL, true).Transparency = 0.4
		decor(city, "ShelterRoof", Vector3.new(7, 0.4, 13), frame * CFrame.new(16.2, walk + 7.2, 0), METAL, true)
		for _, z in { -6.3, 6.3 } do
			decor(city, "ShelterPost", Vector3.new(0.3, 7, 0.3), frame * CFrame.new(13, walk + 3.5, z), METAL)
		end
		decor(city, "Bench", Vector3.new(1.6, 0.4, 7), frame * CFrame.new(18.2, walk + 1.6, 0), WOOD, true)
		-- Столб держит табличку (BillboardGui в Stops.Spawn, высота 4) за правый край, доходит ровно до её низа.
		local signBottom = (GROUND_TOP + 0.3 - ROAD_TOP) + SIGN_OFFSET - 2 -- центр Spawn + сдвиг таблички − половина её высоты
		decor(city, "SignPost", Vector3.new(0.3, signBottom - walk, 0.3), frame * CFrame.new(ROAD_WIDTH / 2 + 4, (walk + signBottom) / 2, 8), METAL)
		lightUp(lamp(frame * CFrame.new(0, 0, -9), 1)) -- у переднего края остановки, светит на навес и посадку

		if string.find(name, "Кладбище") then
			for _, x in { 28, 60 } do
				decor(city, "CemeteryWall", Vector3.new(0.4, 3, 56), frame * CFrame.new(x, ground + 1.5, 0), METAL, true)
			end
			for _, z in { -28, 28 } do
				decor(city, "CemeteryWall", Vector3.new(32, 3, 0.4), frame * CFrame.new(44, ground + 1.5, z), METAL, true)
			end
			for _, x in { 34, 42, 50, 56 } do
				for _, z in { -20, -8, 4, 16 } do
					local tilt = CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.15, 0.15)) -- покосившиеся
					local base = frame * CFrame.new(x, ground, z) * tilt
					decor(city, "Cross", Vector3.new(0.5, 4, 0.5), base * CFrame.new(0, 2, 0), Color3.fromRGB(150, 150, 145), true)
					decor(city, "Cross", Vector3.new(0.5, 0.5, 2), base * CFrame.new(0, 3, 0), Color3.fromRGB(150, 150, 145))
				end
			end
		elseif string.find(name, "Завод") then
			decor(city, "Factory", Vector3.new(30, 24, 50), frame * CFrame.new(58, ground + 12, 0), HOUSE_DARK[1], true)
			for _, z in { -14, 0, 14 } do
				local chimney = decor(city, "Chimney", Vector3.new(50, 5, 5), frame * CFrame.new(68, ground + 25, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 55, 50), true) :: Part
				chimney.Shape = Enum.PartType.Cylinder
				decor(city, "ChimneyLight", Vector3.new(0.6, 0.6, 0.6), frame * CFrame.new(68, ground + 50.5, z), Color3.fromRGB(255, 40, 40)).Material = Enum.Material.Neon
			end
		elseif string.find(name, "Больница") then
			decor(city, "Hospital", Vector3.new(24, 20, 44), frame * CFrame.new(52, ground + 10, 0), Color3.fromRGB(215, 215, 210), true)
			local facade = frame * CFrame.new(39.8, ground + 15, 0) -- стена, обращённая к дороге
			decor(city, "RedCross", Vector3.new(0.3, 8, 2.4), facade, Color3.fromRGB(220, 30, 30)).Material = Enum.Material.Neon
			decor(city, "RedCross", Vector3.new(0.3, 2.4, 8), facade, Color3.fromRGB(220, 30, 30)).Material = Enum.Material.Neon
		end
	end
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
	local stopFrames: { CFrame } = {}
	for k, stopName in Config.STOP_NAMES do
		local a, b = points[k * SEGMENTS_PER_LEG], points[k * SEGMENTS_PER_LEG + 1]
		local cf = CFrame.lookAt((a + b) / 2, b)
		stopFrames[k] = cf
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
		sign.StudsOffset = Vector3.new(0, SIGN_OFFSET, 0)
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

	buildCity(map, points, stopFrames)

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
	local lights, parts = 0, 0
	for _, item in map:GetDescendants() do
		if item:IsA("Light") then
			lights += 1
		elseif item:IsA("BasePart") then
			parts += 1
		end
	end
	assert(lights <= LIGHTS_LIMIT, `Greybox: источников света {lights} > {LIGHTS_LIMIT} — на телефонах будет тормозить`)

	map.Parent = Workspace
	print(`[Greybox] Тестовая карта готова: {#points} точек, {#Config.STOP_NAMES} остановок, деталей {parts}, источников света {lights}`)
end

return GreyboxService
