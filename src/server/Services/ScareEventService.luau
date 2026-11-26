--!strict
-- Пугалки: сервер решает КОГДА (здесь), клиент решает КАК выглядит (HorrorController, T19).
-- На каждом перегоне SCARES_PER_LEG_MIN..MAX событий + SCARE_EXTRA_PER_ANOMALY за каждую аномалию в салоне,
-- в случайные моменты, но не в первые секунды после остановки. Ни одна пугалка не подсказывает, кто аномалия.

local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local QUIET_AFTER_STOP = 5 -- сек тишины после отъезда (по заданию T18)
local SCARE_WINDOW = 22 -- сек, в которые раскидываем пугалки перегона (перегон ≈ 35 сек)
local BACKSEAT_DURATION = 4 -- сек силуэта на заднем сиденье, пока темно
local STARE_DURATION = 3
local LEG_SCARES = { "WindowKnock", "RoofBang", "FigureOnRoad", "PhoneRing", "Stare" }

local ScareEventService = {}

local registry: { [string]: any } = {}
local leg = 0 -- номер текущего перегона: запланированное на старый перегон не срабатывает
local lastScare = ""

local function send(name: string, data: { [string]: any })
	local round = registry.RoundService
	if not round then
		return
	end
	local scareEvent = Remotes.Event("ScareEvent")
	for _, player in round:GetRiders() do
		scareEvent:FireClient(player, name, data)
	end
	if game:GetService("RunService"):IsStudio() then
		print(`[Scare] {name}`) -- пока нет клиента (T19), проверять по этим строкам
	end
end

-- Силуэт на заднем сиденье — только вместе с Blackout (AnomalyService зовёт при эскалации).
function ScareEventService:OnEscalation(effect: string)
	if effect == "Blackout" then
		send("BackSeatFigure", { Duration = BACKSEAT_DURATION })
	end
end

-- Скример при поражении (RoundService). Остальные пугалки рейса отменяются.
function ScareEventService:Jumpscare()
	leg += 1
	send("Jumpscare", {})
end

function ScareEventService:Init(services: { [string]: any })
	registry = services
end

function ScareEventService:Start()
	local route = registry.RouteService
	local bus = Workspace:WaitForChild("Map"):WaitForChild("Bus") :: Model
	if not (route and bus.PrimaryPart) then
		warn("[ScareEventService] Нет RouteService или Bus.PrimaryPart — пугалок не будет")
		return
	end
	local busLength = bus:GetExtentsSize().Z -- в осях PrimaryPart: длина вдоль автобуса

	-- Данные для клиента по таблице «Пугалки» из ARCHITECTURE.
	local function dataFor(name: string): { [string]: any }
		if name == "WindowKnock" then
			return { Side = if math.random() < 0.5 then "Left" else "Right", Z = (math.random() - 0.5) * (busLength - 4) }
		elseif name == "FigureOnRoad" then
			return { Distance = math.random(60, 120) }
		elseif name == "PhoneRing" then
			local seats = bus:FindFirstChild("Seats")
			local list = if seats then seats:GetChildren() else {}
			return { Seat = if #list > 0 then list[math.random(#list)].Name else "" }
		elseif name == "Stare" then
			return { Duration = STARE_DURATION }
		end
		return {}
	end

	-- Случайная пугалка, не та же, что в прошлый раз (иначе приедается).
	local function pickScare(): string
		local name = lastScare
		while name == lastScare do
			name = LEG_SCARES[math.random(#LEG_SCARES)]
		end
		lastScare = name
		return name
	end

	local function startLeg()
		leg += 1
		local thisLeg = leg
		local anomalies = registry.AnomalyService
		local extra = if anomalies then anomalies:CountAboard() * Config.SCARE_EXTRA_PER_ANOMALY else 0
		local count = math.random(Config.SCARES_PER_LEG_MIN, Config.SCARES_PER_LEG_MAX) + extra
		for _ = 1, count do
			task.delay(QUIET_AFTER_STOP + math.random() * SCARE_WINDOW, function()
				if leg == thisLeg then -- перегон ещё идёт: не доехали, рейс не кончился
					local name = pickScare()
					send(name, dataFor(name))
				end
			end)
		end
	end

	-- Approaching = остановка стала следующей, то есть начался перегон (и на старте рейса). AtStop — перегон кончился.
	route.StopChanged:Connect(function(_index: number, _name: string, phase: string)
		if phase == "Approaching" then
			startLeg()
		elseif phase == "AtStop" then
			leg += 1
		end
	end)
end

return ScareEventService
