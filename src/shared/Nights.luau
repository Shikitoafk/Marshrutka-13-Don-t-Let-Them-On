--!strict
-- НОЧИ (V2). Данные, а не логика: NightService (сервер) берёт отсюда набор аномалий, шанс и события,
-- клиент (RulesController) — список правил. Тексты правил — в Strings.luau по ключам rule.*.
-- Меняет файл оркестратор. Ночь N открывается, когда команда прошла ночь N-1 (хотя бы 1 звезда).
--
-- Звёзды за ночь: ★ доехали до «Конечной», ★★ без ошибок (не высадили человека/«своего», не нарушили правило),
-- ★★★ ни одна аномалия не нанесла урон.

export type Night = {
	Index: number,
	NameKey: string, -- Strings: night.N.name
	AnomalyChance: number,
	FirstAnomalyByStop: number?, -- V11: не позже этой остановки сядет хотя бы одна опасная аномалия (nil — без гарантии)
	Anomalies: { [string]: number }, -- [AnomalyId] = вес
	Rules: { string }, -- ключи Strings: rule.*
	Events: {
		ControllerAtStop: number?, -- на какой остановке садится контролёр
		FakeControllerChance: number?, -- шанс, что контролёр фальшивый
		BlackoutFreeze: boolean?, -- в блэкауте нельзя двигаться
		StopRequests: boolean?, -- пассажиры просят остановить между остановками
	},
}

local BASE_RULES = { "rule.eject_anomalies", "rule.check_tickets" }

local function rules(extra: { string }): { string }
	local list = table.clone(BASE_RULES)
	for _, key in extra do
		table.insert(list, key)
	end
	return list
end

local Nights: { Night } = {
	{
		Index = 1,
		NameKey = "night.1.name", -- «Первый рейс»
		AnomalyChance = 0.4,
		FirstAnomalyByStop = 1,
		Anomalies = { NoReflection = 3, WrongTicket = 3, GlowingEyes = 2 },
		Rules = rules({}),
		Events = {},
	},
	{
		Index = 2,
		NameKey = "night.2.name", -- «Туман»
		AnomalyChance = 0.33,
		Anomalies = { NoReflection = 3, WrongTicket = 3, GlowingEyes = 2, NoShadow = 2, Twin = 2 },
		Rules = rules({ "rule.controller" }),
		Events = { ControllerAtStop = 5 },
	},
	{
		Index = 3,
		NameKey = "night.3.name", -- «Бабушка»
		AnomalyChance = 0.36,
		Anomalies = { NoReflection = 2, WrongTicket = 2, GlowingEyes = 2, NoShadow = 2, Twin = 2, StrangeCoin = 3, Grandma = 2 },
		Rules = rules({ "rule.controller", "rule.grandma", "rule.coins" }),
		Events = { ControllerAtStop = 4 },
	},
	{
		Index = 4,
		NameKey = "night.4.name", -- «Не свети»
		AnomalyChance = 0.38,
		Anomalies = { NoReflection = 2, WrongTicket = 2, GlowingEyes = 2, NoShadow = 2, Twin = 2, StrangeCoin = 2, Grandma = 2, Standing = 2, WrongHead = 2 },
		Rules = rules({ "rule.controller", "rule.grandma", "rule.coins", "rule.standing", "rule.blackout_freeze" }),
		Events = { ControllerAtStop = 5, BlackoutFreeze = true },
	},
	{
		Index = 5,
		NameKey = "night.5.name", -- «Конечная»
		AnomalyChance = 0.4,
		Anomalies = { NoReflection = 2, WrongTicket = 2, GlowingEyes = 2, NoShadow = 2, Twin = 2, StrangeCoin = 2, Grandma = 2, Standing = 2, WrongHead = 2, StopRequest = 3 },
		Rules = rules({ "rule.controller", "rule.grandma", "rule.coins", "rule.standing", "rule.blackout_freeze", "rule.no_unscheduled_stops", "rule.real_controller" }),
		Events = { ControllerAtStop = 4, FakeControllerChance = 0.5, BlackoutFreeze = true, StopRequests = true },
	},
}

return Nights
