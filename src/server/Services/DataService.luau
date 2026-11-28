--!strict

local BadgeService = game:GetService("BadgeService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Nights = require(Shared:WaitForChild("Nights"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AUTOSAVE_INTERVAL = 2 * 60
local LOAD_RETRY_INTERVAL = 30
local LEASE_DURATION = 3 * AUTOSAVE_INTERVAL
local MAX_ATTEMPTS = 4
local SHUTDOWN_TIMEOUT = 29 -- Roblox даёт серверу 30 секунд.
local MAX_SAFE_INTEGER = 2 ^ 53 - 1

type StatName = "Runs" | "Wins" | "Caught"
export type Profile = {
	Tenge: number,
	Stats: { [StatName]: number },
	OwnedSkins: { string },
	UnlockedNight: number,
	BestStars: { [string]: number },
}

type Session = {
	player: Player,
	key: string,
	id: string,
	profile: Profile?,
	tutorialOffered: boolean,
	expiresAt: number,
	loading: boolean,
	recovering: boolean,
	saving: boolean,
	closing: boolean,
	changed: BindableEvent,
}

type Transform = (any, DataStoreKeyInfo?) -> (any, { number }?, { [string]: any }?)

local DataService = {}
local store: GlobalDataStore? = nil
local memoryOnly = false
local currencyChanged = Remotes.Event("CurrencyChanged")
local notify = Remotes.Event("Notify")
local sessions: { [Player]: Session } = {}
local departed: { [Player]: boolean } = {}
setmetatable(departed, { __mode = "k" })
local shuttingDown = false
local monetization: { HasVIP: (any, Player) -> boolean }? = nil

local function asInteger(value: any): number?
	if type(value) == "number" and math.abs(value) <= MAX_SAFE_INTEGER and value % 1 == 0 then
		return value
	end
	return nil
end

local function readProfile(raw: any): Profile
	local data = if type(raw) == "table" then raw else {}
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local skins: { string } = {}
	local bestStars: { [string]: number } = {}
	if type(data.BestStars) == "table" then
		for night = 1, #Nights do
			local key = tostring(night)
			local stars = asInteger(data.BestStars[key])
			if stars and stars >= 1 and stars <= 3 then
				bestStars[key] = stars
			end
		end
	end
	if type(data.OwnedSkins) == "table" then
		for _, skin in ipairs(data.OwnedSkins) do
			if type(skin) == "string" then
				table.insert(skins, skin)
			end
		end
	end
	return {
		Tenge = asInteger(data.Tenge) or 0,
		Stats = {
			Runs = math.max(0, asInteger(stats.Runs) or 0),
			Wins = math.max(0, asInteger(stats.Wins) or 0),
			Caught = math.max(0, asInteger(stats.Caught) or 0),
		},
		OwnedSkins = skins,
		UnlockedNight = math.clamp(asInteger(data.UnlockedNight) or 1, 1, #Nights),
		BestStars = bestStars,
	}
end

local function copyProfile(profile: Profile): Profile
	return {
		Tenge = profile.Tenge,
		Stats = table.clone(profile.Stats),
		OwnedSkins = table.clone(profile.OwnedSkins),
		UnlockedNight = profile.UnlockedNight,
		BestStars = table.clone(profile.BestStars),
	}
end

local function leaseExpiry(info: DataStoreKeyInfo?, sessionId: string): number?
	if not info then
		return nil
	end
	local metadata = info:GetMetadata()
	return if metadata.SessionId == sessionId then asInteger(metadata.SessionExpiresAt) else nil
end

local function updateWithRetry(key: string, transform: Transform, expectedOwner: string?): (any, DataStoreKeyInfo?, boolean)
	local reason: any = "профиль занят или повреждён"
	for attempt = 1, MAX_ATTEMPTS do
		if memoryOnly then
			return nil, nil, false
		end
		local ok, result, keyInfo = pcall(function()
			local currentStore = store or DataStoreService:GetDataStore(Config.DATASTORE_NAME)
			store = currentStore
			return currentStore:UpdateAsync(key, transform)
		end)
		if ok and (not expectedOwner or (result ~= nil and leaseExpiry(keyInfo, expectedOwner))) then
			return result, keyInfo, true
		end
		if not ok then
			if RunService:IsStudio() and string.find(string.lower(tostring(result)), "you must publish this place", 1, true) then
				if not memoryOnly then
					memoryOnly = true
					warn("[DataService] Плейс не опубликован. Профили доступны на время теста и не сохраняются.")
				end
				return nil, nil, false
			end
			reason = result
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end
	warn(`[DataService] Не удалось обновить профиль {key}: {reason}`)
	return nil, nil, false
end

local function keyMetadata(info: DataStoreKeyInfo?): { [string]: any }
	return if info then table.clone(info:GetMetadata()) else {}
end

local function keyUsers(info: DataStoreKeyInfo?, userId: number): { number }
	local users = if info then info:GetUserIds() else {}
	if userId > 0 and not table.find(users, userId) then
		users = table.clone(users)
		table.insert(users, userId)
	end
	return users
end

local function publishTenge(player: Player, tenge: number)
	local existing = player:FindFirstChild("leaderstats")
	local folder: Instance
	if existing then
		folder = existing
	else
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
		folder = leaderstats
	end
	local stat = folder:FindFirstChild("₸")
	if not stat then
		local balance = Instance.new("IntValue")
		balance.Name = "₸"
		balance.Value = tenge
		balance.Parent = folder
	elseif stat:IsA("IntValue") then
		stat.Value = tenge
	end
	currencyChanged:FireClient(player, tenge)
end

local function retryLoad(session: Session, load: (Session) -> ())
	if session.closing or shuttingDown or session.player.Parent ~= Players then
		return
	end
	if not session.recovering then
		session.recovering = true
		notify:FireClient(session.player, "notify.balance_unavailable", "Warn")
	end
	task.delay(LOAD_RETRY_INTERVAL, function()
		if not shuttingDown and not session.closing and not session.loading and sessions[session.player] == session and session.player.Parent == Players then
			session.loading = true
			load(session)
		end
	end)
end

local function loadSession(session: Session)
	local raw, info = updateWithRetry(session.key, function(current, currentInfo)
		local metadata = keyMetadata(currentInfo)
		local owner, expiresAt = metadata.SessionId, metadata.SessionExpiresAt
		if owner ~= session.id and type(owner) == "string" and type(expiresAt) == "number" and expiresAt > os.time() then
			return nil
		end
		if current ~= nil and type(current) ~= "table" then
			return nil
		end
		metadata.SessionId = session.id
		metadata.SessionExpiresAt = os.time() + LEASE_DURATION
		return current or readProfile(nil), keyUsers(currentInfo, session.player.UserId), metadata
	end, session.id)

	local expiresAt = leaseExpiry(info, session.id)
	if (raw and expiresAt) or memoryOnly then
		local profile = readProfile(raw)
		session.profile = profile
		session.tutorialOffered = session.tutorialOffered or (raw ~= nil and raw.TutorialOffered == true)
		session.expiresAt = expiresAt or math.huge
		if not session.closing and session.player.Parent == Players then
			session.player:SetAttribute("ShowTutorial", not session.tutorialOffered)
			session.player:SetAttribute("UnlockedNight", profile.UnlockedNight)
			session.tutorialOffered = true
			publishTenge(session.player, profile.Tenge)
			if session.recovering then
				notify:FireClient(session.player, "notify.balance_restored", "Good")
			end
		end
		session.recovering = false
	else
		retryLoad(session, loadSession)
	end
	session.loading = false
	session.changed:Fire()
end

local function openSession(player: Player): Session?
	if shuttingDown or departed[player] or player.Parent ~= Players then
		return nil
	end
	local existing = sessions[player]
	if existing then
		return existing
	end
	local session: Session = {
		player = player,
		key = tostring(player.UserId),
		id = HttpService:GenerateGUID(false),
		profile = nil,
		tutorialOffered = false,
		expiresAt = 0,
		loading = true,
		recovering = false,
		saving = false,
		closing = false,
		changed = Instance.new("BindableEvent"),
	}
	sessions[player] = session
	task.spawn(loadSession, session)
	return session
end

local function saveSession(session: Session, final: boolean)
	local profile = session.profile
	if not profile or memoryOnly or session.saving or (session.closing and not final) then
		return
	end
	session.saving = true
	local snapshot = copyProfile(profile)
	local tutorialOffered = session.tutorialOffered
	local written, info, ok = updateWithRetry(session.key, function(current, currentInfo)
		local metadata = keyMetadata(currentInfo)
		if metadata.SessionId ~= session.id or type(current) ~= "table" then
			return nil
		end
		-- Сохраняем только поля профиля, чтобы не потерять незнакомые поля записи.
		local record = table.clone(current)
		local stats = if type(record.Stats) == "table" then table.clone(record.Stats) else {}
		for name, value in snapshot.Stats do
			stats[name] = value
		end
		record.Tenge = snapshot.Tenge
		record.Stats = stats
		record.OwnedSkins = snapshot.OwnedSkins
		record.UnlockedNight = snapshot.UnlockedNight
		record.BestStars = snapshot.BestStars
		record.TutorialOffered = tutorialOffered
		metadata.SessionId = if final then nil else session.id
		metadata.SessionExpiresAt = if final then nil else os.time() + LEASE_DURATION
		return record, keyUsers(currentInfo, session.player.UserId), metadata
	end, nil)

	if memoryOnly then
		session.expiresAt = math.huge
	elseif ok and not final then
		local expiresAt = leaseExpiry(info, session.id)
		if written and expiresAt then
			session.expiresAt = expiresAt
		else
			session.profile = nil
			session.expiresAt = 0
			retryLoad(session, loadSession)
		end
	end
	session.saving = false
	session.changed:Fire()
end

local function closeSession(session: Session)
	if session.closing then
		return
	end
	session.closing = true
	session.changed:Fire()
	while session.loading or session.saving do
		session.changed.Event:Wait()
	end
	saveSession(session, true)
	sessions[session.player] = nil
end

local function mutableProfile(player: Player): Profile?
	local session = openSession(player)
	if not session then
		return nil
	end
	while session.loading and not session.closing and not shuttingDown do
		session.changed.Event:Wait()
	end
	if session.closing or shuttingDown or session.expiresAt <= os.time() then
		return nil
	end
	return session.profile
end

function DataService:GetProfile(player: Player): Profile?
	local session = sessions[player]
	if shuttingDown or not session or session.closing or session.expiresAt <= os.time() then
		return nil
	end
	local profile = session.profile
	return if profile then copyProfile(profile) else nil
end

function DataService:GetUnlockedNight(player: Player): number
	local profile = mutableProfile(player)
	return if profile then profile.UnlockedNight else 1
end

local function awardBadge(player: Player, id: number)
	if id <= 0 or player.UserId <= 0 then return end
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
				BadgeService:AwardBadgeAsync(player.UserId, id)
			end
		end)
		if not ok then warn(`[DataService] Бейдж {id}: {err}`) end
	end)
end

function DataService:RecordNight(player: Player, night: number, stars: number): boolean
	if not asInteger(night) or not Nights[night] or not asInteger(stars) or stars < 1 or stars > 3 then
		return false
	end
	local profile = mutableProfile(player)
	if not profile then return false end

	local key = tostring(night)
	profile.BestStars[key] = math.max(profile.BestStars[key] or 0, stars)
	profile.UnlockedNight = math.max(profile.UnlockedNight, math.min(night + 1, #Nights))
	player:SetAttribute("UnlockedNight", profile.UnlockedNight)
	local badges: { [string]: number } = Config.BADGES
	awardBadge(player, badges["Night" .. key] or 0)
	if stars == 3 then awardBadge(player, Config.BADGES.PerfectNight) end
	return true
end

function DataService:AddTenge(player: Player, amount: number): boolean
	if asInteger(amount) == nil then
		return false
	end
	local profile = mutableProfile(player)
	if not profile then
		return false
	end
	local passes = monetization
	local multiplier = if amount > 0 and passes and passes:HasVIP(player) then 2 else 1
	local balance = asInteger(profile.Tenge + amount * multiplier)
	if balance == nil then
		return false
	end
	if balance ~= profile.Tenge then
		profile.Tenge = balance
		publishTenge(player, balance)
	end
	return true
end

function DataService:IncrementStat(player: Player, name: string): boolean
	if name ~= "Runs" and name ~= "Wins" and name ~= "Caught" then
		return false
	end
	local profile = mutableProfile(player)
	if not profile then
		return false
	end
	local value = asInteger(profile.Stats[name] + 1)
	if value == nil then
		return false
	end
	profile.Stats[name] = value
	return true
end

function DataService:Init(services: { [string]: any })
	monetization = services.MonetizationService
	Remotes.Function("GetProfile").OnServerInvoke = function(player)
		return self:GetProfile(player)
	end
end

function DataService:Start()
	Players.PlayerRemoving:Connect(function(player)
		departed[player] = true
		local session = sessions[player]
		if session then
			closeSession(session)
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local deadline = os.clock() + SHUTDOWN_TIMEOUT
		for _, session in sessions do
			task.spawn(closeSession, session)
		end
		while next(sessions) and os.clock() < deadline do
			task.wait()
		end
		if next(sessions) then
			warn("[DataService] Сервер закрылся не дождавшись сохранения всех профилей")
		end
	end)

	Players.PlayerAdded:Connect(openSession)
	for _, player in Players:GetPlayers() do
		openSession(player)
	end

	task.spawn(function()
		while not shuttingDown do
			task.wait(AUTOSAVE_INTERVAL)
			if not shuttingDown then
				for _, session in sessions do
					task.spawn(saveSession, session, false)
				end
			end
		end
	end)
end

return DataService
