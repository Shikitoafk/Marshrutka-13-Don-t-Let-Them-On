--!strict
-- СПИСОК АНОМАЛИЙ. Данные, а не логика: AnomalyService (сервер) и
-- ConductorController (клиент) читают отсюда. Новую аномалию добавляем записью сюда.
--
-- Detect — чем кондуктор может её распознать:
--   "Mirror"     — пассажира НЕТ в зеркале заднего вида
--   "Flashlight" — под фонариком видна подсказка (нет тени / светятся глаза)
--   "Ticket"     — билет неправильный (дата, номер маршрута)
--   "Observe"    — видно глазами, если присмотреться
--   "Rule"       — распознаётся не глазами, а по правилу ночи (Nights.luau)
--
-- Class (V2) — что с ней делать:
--   "Dangerous" — высадить (по умолчанию, если поля нет)
--   "Safe"      — НЕ трогать: выглядит странно, но своя; высадка = штраф SAFE_EJECT_PENALTY
--   "Special"   — особое правило из Nights.luau (не светить, не останавливаться и т.п.)
--
-- Weight — вес в старом выборе (до V2). В V2 веса и набор аномалий берутся из Nights.luau;
-- новые аномалии здесь с Weight = 0, чтобы старый код их не выдавал.
--
-- CueAttribute — атрибут, который сервер ставит на модель пассажира,
-- чтобы клиент показал подсказку. Флаг «это аномалия» на модель НЕ ставим никогда:
-- правда хранится только на сервере.

export type AnomalyType = {
	Id: string,
	Name: string, -- для экрана результатов
	Hint: string, -- подсказка в «Памятке кондуктора»
	Detect: "Mirror" | "Flashlight" | "Ticket" | "Observe" | "Rule",
	Class: ("Dangerous" | "Safe" | "Special")?,
	CueAttribute: string?,
	Weight: number, -- частота выпадения
}

local AnomalyTypes: { AnomalyType } = {
	{
		Id = "NoReflection",
		Name = "Без отражения",
		Hint = "Посмотри в зеркало: кого-то из пассажиров в нём нет?",
		Detect = "Mirror",
		CueAttribute = "HiddenInMirror",
		Weight = 3,
	},
	{
		Id = "WrongTicket",
		Name = "Билет из 1986-го",
		Hint = "Проверь билеты: маршрут должен быть №13, а год — нынешний.",
		Detect = "Ticket",
		CueAttribute = nil, -- сервер подменяет данные в InspectResult
		Weight = 3,
	},
	{
		Id = "NoShadow", -- Id и CueAttribute оставлены старыми, чтобы не ломать код; по смыслу это «Призрак»
		Name = "Призрак",
		Hint = "Посвети фонариком: сквозь некоторых пассажиров просвечивает.",
		Detect = "Flashlight",
		CueAttribute = "NoShadow",
		Weight = 2,
	},
	{
		Id = "GlowingEyes",
		Name = "Светящиеся глаза",
		Hint = "В темноте фонарик отражается в глазах только у… них.",
		Detect = "Flashlight",
		CueAttribute = "GlowEyes",
		Weight = 2,
	},
	{
		Id = "Twin",
		Name = "Двойник",
		Hint = "Два одинаковых пассажира? Один из них лишний.",
		Detect = "Observe",
		CueAttribute = "TwinOf", -- значение: PassengerId оригинала
		Weight = 2,
	},
	{
		Id = "WrongHead",
		Name = "Голова задом наперёд",
		Hint = "Присмотрись, куда смотрят пассажиры. Все ли смотрят вперёд?",
		Detect = "Observe",
		CueAttribute = "HeadBackwards",
		Weight = 1,
	},

	-- ===== V2 (включаются через Nights.luau) =====
	{
		Id = "StrangeCoin",
		Name = "Странная монета",
		Hint = "«Передайте за проезд»: платят только тенге. Копейки, монеты без надписей — не наши.",
		Detect = "Ticket", -- InspectResult билета содержит поле Coin
		Class = "Dangerous",
		CueAttribute = nil,
		Weight = 0,
	},
	{
		Id = "Grandma",
		Name = "Бабушка с котомкой",
		Hint = "Бабушку в платке с котомкой не трогай. Она странная, но своя.",
		Detect = "Observe",
		Class = "Safe",
		CueAttribute = "Babushka", -- сервер одевает: платок, котомка; иногда она тихо смеётся
		Weight = 0,
	},
	{
		Id = "Standing",
		Name = "Стоящий спиной",
		Hint = "Если пассажир стоит в проходе спиной к тебе — не свети на него фонарём.",
		Detect = "Observe",
		Class = "Special",
		CueAttribute = "StandsBackwards",
		Weight = 0,
	},
	{
		Id = "StopRequest",
		Name = "«Остановите здесь!»",
		Hint = "Не останавливайся между остановками, кто бы ни просил.",
		Detect = "Rule",
		Class = "Special",
		CueAttribute = "AsksToStop",
		Weight = 0,
	},
	{
		Id = "FakeController",
		Name = "Фальшивый контролёр",
		Hint = "Настоящий контролёр всегда в синей форме с жетоном. Остальных — высаживай.",
		Detect = "Observe",
		Class = "Dangerous",
		CueAttribute = "FakeUniform",
		Weight = 0,
	},
}

return AnomalyTypes
