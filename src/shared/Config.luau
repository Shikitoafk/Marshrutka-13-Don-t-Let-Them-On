--!strict
-- ОБЩИЕ НАСТРОЙКИ ИГРЫ (баланс, тайминги, ID).
-- Агенты читают отсюда и НЕ хардкодят эти числа в своих модулях.
-- Менять значения баланса можно в PR, но только с пояснением зачем.

local Config = {
	GAME_NAME = "Marshrutka 13",

	-- Лобби и раунд
	MAX_PLAYERS_PER_BUS = 4,
	MIN_PLAYERS_TO_START = 1,
	LOBBY_COUNTDOWN = 15, -- сек до старта после первого «Готов»
	RESULTS_SCREEN_TIME = 10, -- сек экрана результатов

	-- Маршрут
	ROUTE_NUMBER = "13",
	STOP_NAMES = {
		"Рынок",
		"Больница",
		"Школа №13",
		"Старый мост",
		"Завод",
		"Кладбище",
		"Подстанция",
		"Конечная",
	},
	STOP_DOOR_TIME = 8, -- сек, сколько двери открыты автоматически
	STOP_ZONE_LENGTH = 14, -- studs, зона, где автобус «на остановке»
	STOP_SKIP_DAMAGE = 25, -- B13: проехал остановку, не открыв двери — урон и ошибка ночи (минус звезда)

	-- Автобус (движение по рельсу из точек маршрута)
	BUS_MAX_SPEED = 45, -- studs/сек
	BUS_ACCEL = 9,
	BUS_BRAKE = 22,
	BUS_IDLE_DECEL = 4, -- замедление, если газ отпущен
	BUS_MAX_HEALTH = 100,

	-- Пассажиры и аномалии
	PASSENGERS_PER_STOP_MIN = 1,
	PASSENGERS_PER_STOP_MAX = 3,
	MAX_PASSENGERS_ON_BUS = 10,
	ANOMALY_CHANCE = 0.35, -- шанс, что новый пассажир — аномалия
	MAX_ANOMALIES_AT_ONCE = 2,
	ANOMALY_DAMAGE = 25, -- урон автобусу, если аномалия едет дальше остановки
	ESCALATION_EFFECTS = { "LightsFlicker", "Blackout", "Whispers", "RadioStatic" }, -- Blackout на 2-м ударе: силуэт на заднем сиденье виден в середине рейса, а не перед смертью

	-- Инструменты кондуктора
	INSPECT_RANGE = 10, -- studs, дистанция проверки (сервер проверяет!)
	INSPECT_COOLDOWN = 1.5, -- сек
	FLASHLIGHT_BATTERY = 60, -- сек работы за рейс

	-- Экономика (валюта — тенге ₸)
	FARE_PER_PASSENGER = 15,
	CATCH_REWARD = 30, -- за высаженную аномалию
	WRONG_EJECT_PENALTY = 20, -- за высаженного нормального пассажира
	FINISH_BONUS = 100,

	-- Монетизация (вставить ID после создания в Creator Dashboard)
	GAMEPASS_VIP = 0, -- VIP-маршрутка: скин + x2 тенге
	GAMEPASS_RADIO = 0, -- радио с музыкой
	PRODUCT_AMULET = 0, -- «Оберег»: один раз за рейс спасает автобус при 0 HP
	AMULET_RESTORE_HEALTH = 30,

	-- Звуки (вставить ID из Creator Store)
	SOUNDS = {
		DoorOpen = "rbxassetid://104970206145568",
		DoorClose = "rbxassetid://98445470555676",
		Horn = "rbxassetid://95557198733467",
		Engine = "rbxassetid://116833562114860",
		RadioStatic = "rbxassetid://70612414709255",
		Whispers = "rbxassetid://138668626617588",
		Ambience = "rbxassetid://75679639068132",
		Jumpscare = "rbxassetid://119146144435977",
		Knock = "rbxassetid://109157623487684", -- стук в окно
		Bang = "rbxassetid://98955331896298", -- удар по крыше
		Heartbeat = "rbxassetid://73591801900686", -- сердцебиение при низкой прочности (loop)
		PhoneRing = "rbxassetid://94997087414745", -- телефон звонит под сиденьем
		StopChime = "rbxassetid://92359031477245", -- «динь» перед объявлением остановки
		Music = "rbxassetid://117865907003168", -- тихая жуткая музыка в рейсе (loop)
		GrandmaLaugh = "rbxassetid://0", -- тихий смешок бабушки (V02)
	},

	-- Пугалки (ScareEventService): сколько событий на перегон
	-- V11: реплики пассажиров и сцена пропуска
	SPEAK_STRANGE_ANOMALY = 0.5, -- опасная аномалия говорит «не то»
	SPEAK_STRANGE_NORMAL = 0.1, -- обычный пассажир иногда тоже
	ATTACK_DARK_TIME = 1.5, -- сек темноты AnomalyAttack до урона

	-- V12: опоздавший и поломка
	LATE_RUNNER_CHANCE = 0.3, -- шанс на остановку (ночи с Events.LateRunner), не больше одного за остановку
	LATE_RUNNER_RUN_TIME = 5, -- сек бега до дверей
	LATE_RUNNER_PENALTY = 10, -- ₸ каждому, если закрыли двери перед обычным
	BREAKDOWN_FIX_HOLD = 6, -- сек держать «Завести»
	BREAKDOWN_TIMEOUT = 30, -- не завели за это время — забирают одного живого

	SCARES_PER_LEG_MIN = 1,
	SCARES_PER_LEG_MAX = 2,
	SCARE_EXTRA_PER_ANOMALY = 1, -- +событие за каждую аномалию в салоне

	-- ===== V2: ночи, контролёр, призраки =====
	NIGHTS_COUNT = 5,
	SAFE_EJECT_PENALTY = 40, -- высадил «своего» (Safe): штраф тенге + проклятие (мигание света)
	CONTROLLER_CHECK_TIME = 10, -- сек после посадки контролёра до проверки салона
	CONTROLLER_PENALTY_PER_ANOMALY = 25, -- урон автобусу за каждую аномалию при проверке
	CONTROLLER_CLEAN_BONUS = 50, -- тенге каждому, если салон чистый
	STOP_REQUEST_DAMAGE = 25, -- остановился между остановками по просьбе «пассажира»
	BLACKOUT_FREEZE_TIME = 5, -- сек «не двигайся» в блэкауте (с 4-й ночи)
	BLACKOUT_MOVE_TOLERANCE = 2.5, -- studs: сдвинулся больше — забирают
	GHOST_KNOCK_COOLDOWN = 8,
	GHOST_FLICKER_COOLDOWN = 12,
	REVIVE_FREE_PER_NIGHT = 1, -- бесплатных возрождений на команду за рейс
	PRODUCT_REVIVE = 0, -- Developer Product «Вернуться в салон»
	STOP_REQUEST_ASK_MIN = 8, -- сек после отъезда, когда «пассажир» может попросить остановить (V02)
	STOP_REQUEST_ASK_MAX = 20,
	ALL_TAKEN_GRACE = 10, -- сек: забрали всех — ждём возвращения, потом поражение (V04)

	-- ===== V09: косметика =====
	-- Price — тенге (0 = бесплатно с начала); ProductId/GamepassId — за Robux (0 = пока не продаётся)
	COSMETICS = {
		Flashlight = {
			{ Id = "Classic", Price = 0 },
			{ Id = "Warm", Price = 500 },
			{ Id = "Neon", Price = 1500 },
			{ Id = "Alarm", Price = 0, GamepassId = 0 }, -- красный «тревога», Robux
			{ Id = "Rainbow", Price = 0, GamepassId = 0 }, -- радужный, Robux
		},
		TakenEffect = {
			{ Id = "Fade", Price = 0 }, -- растворяется
			{ Id = "Hands", Price = 1000 }, -- чёрные руки утягивают под пол
			{ Id = "Ash", Price = 0, GamepassId = 0 }, -- вспышка и пепел, Robux
			{ Id = "Ceiling", Price = 0, GamepassId = 0 }, -- утащило в потолок, Robux
		},
	},
	BADGES = { Night1 = 0, Night2 = 0, Night3 = 0, Night4 = 0, Night5 = 0, PerfectNight = 0, EndingGood = 0, EndingBad = 0 }, -- ID бейджей

	-- DataStore
	DATASTORE_NAME = "PlayerData_v1",
}

return table.freeze(Config)
