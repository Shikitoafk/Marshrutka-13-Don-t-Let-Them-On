--!strict
-- СПИСОК АНОМАЛИЙ. Данные, а не логика: AnomalyService (сервер) и
-- ConductorController (клиент) читают отсюда. Новую аномалию добавляем записью сюда.
--
-- Detect — чем кондуктор может её распознать:
--   "Mirror"     — пассажира НЕТ в зеркале заднего вида
--   "Flashlight" — под фонариком видна подсказка (нет тени / светятся глаза)
--   "Ticket"     — билет неправильный (дата, номер маршрута)
--   "Observe"    — видно глазами, если присмотреться
--
-- CueAttribute — атрибут, который сервер ставит на модель пассажира,
-- чтобы клиент показал подсказку. Флаг «это аномалия» на модель НЕ ставим никогда:
-- правда хранится только на сервере.

export type AnomalyType = {
	Id: string,
	Name: string, -- для экрана результатов
	Hint: string, -- подсказка в «Памятке кондуктора»
	Detect: "Mirror" | "Flashlight" | "Ticket" | "Observe",
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
		Id = "NoShadow",
		Name = "Без тени",
		Hint = "Посвети фонариком: у людей есть тень.",
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
}

return AnomalyTypes
