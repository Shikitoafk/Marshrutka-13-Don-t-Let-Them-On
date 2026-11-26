--!strict
-- Раунд: Lobby → (кто-то «Готов») Countdown → Running → Results → Lobby.
-- В рейсе сажает игроков в автобус, держит водителя на DriverSeat, у всех в салоне отключает прыжок
-- (в прыжке Humanoid теряет скорость автобуса и улетает к задней стенке) и возвращает отставших.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local LEFT_BEHIND_DISTANCE = 25 -- studs от центра автобуса: дальше — игрок отстал, возвращаем в салон
local CHECK_INTERVAL = 0.5
local READY_COOLDOWN = 0.3 -- от спама «Готов» (каждое нажатие рассылается всем)
local AISLE_STEP = 4 -- studs между игроками в проходе

local RoundService = {}

local registry: { [string]: any } = {}
local riders: { Player } = {} -- кто едет в этом рейсе

function RoundService:Init(services: { [string]: any })
	registry = services
end

-- Игроки текущего рейса (копия); вне рейса — пусто.
function RoundService:GetRiders(): { Player }
	return table.clone(riders)
end

-- Закончить рейс победой или поражением (AnomalyService зовёт при прочности 0). Настоящая функция — в :Start().
local endRunNow = function(_won: boolean) end
function RoundService:EndRun(won: boolean)
	endRunNow(won)
end

function RoundService:Start()
	local roles = registry.RoleService
	local route = registry.RouteService
	local bus = Workspace:WaitForChild("Map"):WaitForChild("Bus") :: Model
	local root = bus.PrimaryPart
	local driverSeat = bus:WaitForChild("DriverSeat") :: Seat
	if not (roles and route and root) then
		warn("[RoundService] Нет RoleService, RouteService или Bus.PrimaryPart — раунды не запустятся")
		return
	end
	-- Сиденья — только через Sit(): иначе задевший сиденье кондуктор сядет, а без прыжка уже не встанет.
	for _, seat in bus:GetDescendants() do
		if seat:IsA("BasePart") and (seat.ClassName == "Seat" or seat.ClassName == "VehicleSeat") then
			seat.CanTouch = false
		end
	end

	local roundState = Remotes.Event("RoundState")
	local notify = Remotes.Event("Notify")

	local state = "Lobby"
	local ready: { [string]: boolean } = {} -- [tostring(UserId)] = true
	local countdownEndsAt = 0
	local boarded: { [Player]: boolean } = {}
	local lastReadyAt: { [Player]: number } = {}

	-- Высота пола — от сиденья водителя: так работает и с настоящим автобусом, не только с greybox.
	local floorY = root.CFrame:PointToObjectSpace(driverSeat.Position).Y - driverSeat.Size.Y / 2
	local function aisle(slot: number): CFrame
		return root.CFrame * CFrame.new(0, floorY + 3.5, -4 + (slot - 1) * AISLE_STEP)
	end

	local function snapshot(): { [string]: any }
		if state == "Lobby" then
			return { Ready = ready }
		elseif state == "Countdown" then
			return { Ready = ready, CountdownEndsAt = countdownEndsAt }
		end
		return {}
	end

	local function broadcast()
		roundState:FireAllClients(state, snapshot())
	end

	local function endRun(won: boolean)
		if state ~= "Running" then
			return
		end
		state = "Results"
		broadcast()
		if not won then
			route:StopRun() -- поражение посреди перегона: автобус плавно тормозит
			local scares = registry.ScareEventService
			if scares and #riders > 0 then
				scares:Jumpscare() -- проигрыш = скример (GDD «Страх»)
			end
		else
			for _, player in riders do
				notify:FireClient(player, "notify.trip_finished", "Good")
			end
		end
		local anomalies = registry.AnomalyService
		if anomalies then
			anomalies:FinishRun(won) -- RunEnded с итогами, бонус и статистика
		end
		task.delay(Config.RESULTS_SCREEN_TIME, function()
			roles:ClearRoles()
			for _, player in table.clone(riders) do -- копия: пока ждём персонажа, кто-то может выйти из игры
				if player.Parent then
					-- в депо; заодно вернёт прыжок и снимет с сиденья. pcall: иначе ошибка навсегда оставит раунд в Results
					local ok, err = pcall(player.LoadCharacterAsync, player)
					if not ok then
						warn(`[RoundService] Не удалось вернуть {player.Name} в депо: {err}`)
					end
				end
			end
			table.clear(riders)
			local passengers = registry.PassengerService
			if passengers then
				passengers:Clear()
			end
			route:ResetRun() -- в автобусе никого — можно перенести его на старт
			state = "Lobby"
			broadcast()
		end)
	end

	-- Каждые CHECK_INTERVAL: без прыжка, водитель на месте, отставшие (и только что начавшие рейс) — в салон.
	local function checkRiders()
		local driver = roles:GetDriver()
		for slot, player in riders do
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local body = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if character and humanoid and body and body:IsA("BasePart") and humanoid.Health > 0 then
				humanoid.JumpHeight = 0
				humanoid.JumpPower = 0
				local seat = humanoid.SeatPart
				local mustMove = if player == driver
					then seat ~= driverSeat
					else not boarded[player] or (body.Position - root.Position).Magnitude > LEFT_BEHIND_DISTANCE
				if mustMove and seat then
					-- Сидящий приварен к сиденью: PivotTo утащил бы сиденье (и автобус). Сначала встаём, переносим на следующей проверке.
					humanoid.Sit = false
				elseif mustMove and player == driver then
					character:PivotTo(driverSeat.CFrame + Vector3.new(0, 3, 0))
					driverSeat:Sit(humanoid)
				elseif mustMove then
					character:PivotTo(aisle(slot))
					body.AssemblyLinearVelocity = root.AssemblyLinearVelocity -- иначе в едущем автобусе сразу снесёт назад
					if boarded[player] then
						notify:FireClient(player, "notify.returned_to_bus", "Warn")
					end
				end
				boarded[player] = true
			end
		end
		if route:IsFinished() then
			endRun(true) -- доехали до конечной
		end
	end
	endRunNow = endRun

	local function startRun()
		table.clear(riders)
		table.clear(boarded)
		table.clear(ready)
		for _, player in Players:GetPlayers() do
			if #riders < Config.MAX_PLAYERS_PER_BUS then
				table.insert(riders, player)
			end
		end
		if #riders < Config.MIN_PLAYERS_TO_START then
			state = "Lobby"
			broadcast()
			return
		end
		roles:AssignRoles(riders) -- сначала каждому RoleAssigned,
		state = "Running"
		broadcast() -- потом RoundState("Running")
		route:StartRun()
		checkRiders() -- сразу сажаем всех в автобус
	end

	local function startCountdown()
		state = "Countdown"
		countdownEndsAt = Workspace:GetServerTimeNow() + Config.LOBBY_COUNTDOWN
		local deadline = countdownEndsAt
		task.delay(Config.LOBBY_COUNTDOWN, function()
			if state == "Countdown" and countdownEndsAt == deadline then
				startRun()
			end
		end)
	end

	Remotes.Event("LobbyReady").OnServerEvent:Connect(function(player: Player, isReady: unknown)
		if (state ~= "Lobby" and state ~= "Countdown") or type(isReady) ~= "boolean" or time() - (lastReadyAt[player] or 0) < READY_COOLDOWN then
			return
		end
		lastReadyAt[player] = time()
		if isReady then
			ready[tostring(player.UserId)] = true
		else
			ready[tostring(player.UserId)] = nil
		end
		if next(ready) == nil then
			state = "Lobby" -- все передумали — отсчёт отменяется
		elseif state == "Lobby" then
			startCountdown()
		end
		broadcast()
	end)

	-- Новому игроку — снимок состояния; если рейс идёт и есть место — он кондуктор (роль раньше снимка).
	local function welcome(player: Player)
		if state == "Running" and #riders < Config.MAX_PLAYERS_PER_BUS and not table.find(riders, player) then
			table.insert(riders, player)
			roles:AddConductor(player)
		end
		roundState:FireClient(player, state, snapshot())
	end
	Players.PlayerAdded:Connect(welcome)
	for _, player in Players:GetPlayers() do
		welcome(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastReadyAt[player] = nil
		boarded[player] = nil
		local index = table.find(riders, player)
		if index then
			table.remove(riders, index)
		end
		local key = tostring(player.UserId)
		if ready[key] then
			ready[key] = nil
			if state == "Countdown" and next(ready) == nil then
				state = "Lobby"
			end
			broadcast()
		end
		if state == "Running" and #riders == 0 then
			endRun(false)
		end
	end)

	while true do
		task.wait(CHECK_INTERVAL)
		if state == "Running" then
			checkRiders()
		end
	end
end

return RoundService
