--!strict
-- «Забрали» и призраки (V2, GDD §9 п.6). Нарушил правило ночи (посветил на стоящего спиной, двинулся в блэкауте) —
-- игрок становится призраком: остаётся в салоне полупрозрачным и без столкновений, без инструментов кондуктора,
-- может стучать в окно у пассажира и мигать светом (GhostAction), чтобы подсказать живым.
-- Возвращение: ReviveRequest (бесплатно REVIVE_FREE_PER_NIGHT на команду за рейс) или продукт PRODUCT_REVIVE —
-- после оплаты MonetizationService зовёт Revive. Забрали всех и никто не вернулся — поражение.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RateLimit = require(script.Parent.Parent:WaitForChild("RateLimit"))

local ACTION_RATE = 4 -- GhostAction/ReviveRequest в секунду на игрока: сверх — отбрасываем до проверок
local MAX_ID_LENGTH = 64
local GHOST_TRANSPARENCY = 0.7
-- shortcut: тайминг не из Config (нет ключа) — сек, которые даём на возвращение, когда забрали всех; перенести в Config.
local ALL_TAKEN_GRACE = 10
local FREEZE_STEP = 0.1 -- как часто проверяем, не сдвинулся ли кто в блэкауте

local GhostService = {}

local registry: { [string]: any } = {}
local ghosts: { [Player]: boolean } = {}
local lastAction: { [Player]: { [string]: number } } = {}
local reviving: { [Player]: boolean } = {} -- новый персонаж ещё грузится: второй запрос не принимаем
local revivesLeft = 0 -- бесплатные возвращения команды на этот рейс
local taken = 0 -- сколько раз за рейс кого-то забрали (RunEnded.Taken)
local runId = 0
local running = false

local notify = Remotes.Event("Notify")
local ghostState = Remotes.Event("GhostState")

local function log(text: string)
	if RunService:IsStudio() then
		print(`[Ghost] {text}`)
	end
end

local function riders(): { Player }
	local round = registry.RoundService
	return if round then round:GetRiders() else {}
end

local function living(): { Player }
	local list = {}
	for _, player in riders() do
		if not ghosts[player] then
			table.insert(list, player)
		end
	end
	return list
end

-- Полупрозрачный, сквозь всех проходит, лучи (подсказки, проверки) его не видят. На полу стоит: Humanoid держит
-- высоту лучом вниз, столкновения частей тела для этого не нужны.
local function ghostLook(character: Model)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = math.max(part.Transparency, GHOST_TRANSPARENCY)
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		end
	end
end

local function stateData(reason: string?): { [string]: any }
	return { RevivesLeft = revivesLeft, ProductId = Config.PRODUCT_REVIVE, Reason = reason }
end

-- Все в рейсе — призраки: ждём ALL_TAKEN_GRACE, вдруг кто-то вернётся; нет — поражение.
local function checkAllTaken()
	local list = riders()
	if not running or #list == 0 or #living() > 0 then
		return
	end
	log(`забрали всех — поражение через {ALL_TAKEN_GRACE} с, если никто не вернётся`)
	local run = runId
	task.delay(ALL_TAKEN_GRACE, function()
		if run ~= runId or not running or #riders() == 0 or #living() > 0 then
			return
		end
		local round = registry.RoundService
		if round then
			round:EndRun(false)
		end
	end)
end

function GhostService:IsGhost(player: Player): boolean
	return ghosts[player] == true
end

function GhostService:CountTaken(): number
	return taken
end

-- Забрать игрока рейса (AnomalyService: посветил на стоящего; блэкаут-«замри» здесь же). Водителя не забирают.
function GhostService:Take(player: Player, reason: string)
	local roles = registry.RoleService
	local character = player.Character
	if not running or ghosts[player] or not character or not table.find(riders(), player) or (roles and roles:GetDriver() == player) then
		return
	end
	ghosts[player] = true
	taken += 1
	ghostLook(character)
	log(`забрали {player.Name}: {reason}`)
	for _, other in riders() do
		Remotes.Event("PlayerTaken"):FireClient(other, player.UserId, reason)
		notify:FireClient(other, "notify.player_taken", "Bad", { player = player.DisplayName })
	end
	ghostState:FireClient(player, true, stateData(reason))
	checkAllTaken()
end

-- Вернуть призрака в салон: новый персонаж (RoundService сам посадит его в автобус). Ждёт LoadCharacterAsync (B05):
-- true — только если персонаж загрузился и рейс тот же; false — не призрак, уже возвращается, ошибка загрузки
-- или рейс кончился, пока грузились (тогда ни бесплатная попытка, ни купленный заряд не тратятся).
local function revive(player: Player): boolean
	if not running or not ghosts[player] or reviving[player] then
		return false
	end
	reviving[player] = true
	local run = runId
	local ok, err = pcall(player.LoadCharacterAsync, player)
	reviving[player] = nil
	if not ok then
		warn(`[GhostService] Не удалось вернуть {player.Name}: {err}`)
		return false
	end
	if run ~= runId or not ghosts[player] then
		return false -- пока грузились, рейс кончился: FinishRun уже всех вернул
	end
	ghosts[player] = nil
	lastAction[player] = nil
	ghostState:FireClient(player, false, {})
	for _, other in riders() do
		Remotes.Event("PlayerRevived"):FireClient(other, player.UserId)
		notify:FireClient(other, "notify.player_revived", "Good", { player = player.DisplayName })
	end
	log(`вернулся {player.Name}`)
	return true
end

-- MonetizationService после оплаты PRODUCT_REVIVE (V07). Ждёт загрузки персонажа. true — вернули; false — заряд не тратить
-- (не призрак, уже возвращается, персонаж не загрузился или рейс кончился).
function GhostService:Revive(player: Player): boolean
	return revive(player)
end

-- RoundService: рейс начался.
function GhostService:StartRun()
	table.clear(ghosts)
	table.clear(lastAction)
	revivesLeft, taken = Config.REVIVE_FREE_PER_NIGHT, 0
	runId += 1
	running = true
end

-- RoundService: рейс окончен. Персонажей вернёт LoadCharacterAsync в депо; здесь — сказать призракам, что всё.
function GhostService:FinishRun()
	runId += 1
	running = false
	for player in ghosts do
		ghostState:FireClient(player, false, {})
	end
	table.clear(ghosts)
	table.clear(lastAction)
end

-- AnomalyService: начался блэкаут. В ночи с BlackoutFreeze живым кондукторам — «замри»: кто сдвинулся относительно
-- автобуса больше BLACKOUT_MOVE_TOLERANCE за BLACKOUT_FREEZE_TIME, того забирают (правило нарушено).
local blackoutNow = function() end
function GhostService:OnBlackout()
	blackoutNow()
end

function GhostService:Init(services: { [string]: any })
	registry = services
end

function GhostService:Start()
	local root = (Workspace:WaitForChild("Map"):WaitForChild("Bus") :: Model).PrimaryPart
	if not root then
		warn("[GhostService] У Map.Bus нет PrimaryPart — призраков не будет")
		return
	end
	local scareEvent = Remotes.Event("ScareEvent")
	local allowAction, allowRevive = RateLimit.new(ACTION_RATE), RateLimit.new(ACTION_RATE)

	Remotes.Event("GhostAction").OnServerEvent:Connect(function(player: Player, action: unknown, passengerId: unknown)
		if not allowAction(player) or not running or not ghosts[player] or (action ~= "Knock" and action ~= "Flicker") then
			return
		end
		local last: { [string]: number } = lastAction[player] or {}
		lastAction[player] = last
		local cooldown = if action == "Knock" then Config.GHOST_KNOCK_COOLDOWN else Config.GHOST_FLICKER_COOLDOWN
		if time() - (last[action :: string] or -math.huge) < cooldown then
			return
		end
		if action == "Knock" then
			-- стук в окно рядом с пассажиром: живые видят и слышат его там (ScareEvent WindowKnock)
			local passengers = registry.PassengerService
			if type(passengerId) ~= "string" or #passengerId > MAX_ID_LENGTH or not passengers then
				return
			end
			local model = passengers:GetModel(passengerId)
			if not model then
				return
			end
			last.Knock = time()
			local spot = root.CFrame:PointToObjectSpace(model:GetPivot().Position)
			local data = { Side = if spot.X < 0 then "Left" else "Right", Z = spot.Z }
			for _, other in living() do
				scareEvent:FireClient(other, "WindowKnock", data)
			end
			log(`{player.Name} стучит у пассажира`)
		else
			local anomalies = registry.AnomalyService
			if anomalies then
				last.Flicker = time()
				anomalies:Flicker()
				log(`{player.Name} мигает светом`)
			end
		end
	end)

	Remotes.Event("ReviveRequest").OnServerEvent:Connect(function(player: Player)
		if not allowRevive(player) or revivesLeft <= 0 or not running or not ghosts[player] or reviving[player] then
			return
		end
		-- Попытку занимаем сразу: пока грузится персонаж, второй призрак её не возьмёт. Не вернулся — отдаём обратно (B05).
		revivesLeft -= 1
		local run = runId
		if not revive(player) then
			if run == runId then
				revivesLeft += 1
			end
			return
		end
		for other in ghosts do
			ghostState:FireClient(other, true, stateData()) -- бесплатных стало меньше
		end
	end)

	blackoutNow = function()
		local nights, roles = registry.NightService, registry.RoleService
		local night = if nights then nights:GetNightData() else nil
		if not (running and night and night.Events.BlackoutFreeze) then
			return
		end
		local driver = if roles then roles:GetDriver() else nil
		local start: { [Player]: Vector3 } = {}
		for _, player in living() do
			local body = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
			if player ~= driver and body and body:IsA("BasePart") then
				start[player] = root.CFrame:PointToObjectSpace(body.Position)
				notify:FireClient(player, "notify.freeze", "Warn")
			end
		end
		local run, ends = runId, time() + Config.BLACKOUT_FREEZE_TIME
		task.spawn(function()
			while time() < ends and run == runId and next(start) do
				task.wait(FREEZE_STEP)
				for player, from in start do
					local body = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
					if body and body:IsA("BasePart") and (root.CFrame:PointToObjectSpace(body.Position) - from).Magnitude > Config.BLACKOUT_MOVE_TOLERANCE then
						start[player] = nil
						if nights then
							nights:BreakRule()
						end
						GhostService:Take(player, "moved_in_blackout")
					end
				end
			end
		end)
	end

	-- Призрак сбросил персонажа (меню → Reset) — новый тоже призрак. Но не при Возвращении: CharacterAdded
	-- срабатывает внутри LoadCharacterAsync, пока ghosts[player] ещё true (снимаем его только после успеха).
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			if ghosts[player] and running and not reviving[player] then
				task.defer(ghostLook, character) -- после того, как подгрузится внешность
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ghosts[player] = nil
		lastAction[player] = nil
		task.defer(checkAllTaken) -- RoundService убирает его из рейса в своём обработчике
	end)
end

return GhostService
