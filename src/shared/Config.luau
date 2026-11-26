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
	ESCALATION_EFFECTS = { "LightsFlicker", "RadioStatic", "Whispers", "Blackout" },

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
		DoorOpen = "rbxassetid://0",
		DoorClose = "rbxassetid://0",
		Horn = "rbxassetid://0",
		Engine = "rbxassetid://0",
		RadioStatic = "rbxassetid://0",
		Whispers = "rbxassetid://0",
		Ambience = "rbxassetid://0",
		Jumpscare = "rbxassetid://0",
	},

	-- DataStore
	DATASTORE_NAME = "PlayerData_v1",
}

return table.freeze(Config)
