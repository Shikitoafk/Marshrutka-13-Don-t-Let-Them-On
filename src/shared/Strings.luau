--!strict

local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Translation = { en: string, ru: string }
export type Parameters = { [string]: any }

local catalog: { [string]: Translation } = {
	["ui.close"] = { en = "Close", ru = "Закрыть" },
	["ui.cancel"] = { en = "Cancel", ru = "Отмена" },
	["settings.title"] = { en = "Settings", ru = "Настройки" },
	["settings.music"] = { en = "Music volume", ru = "Громкость музыки" },
	["settings.effects"] = { en = "Effects volume", ru = "Громкость эффектов" },
	["settings.sensitivity"] = { en = "Driver camera sensitivity", ru = "Чувствительность камеры водителя" },
	["settings.reduced"] = { en = "Reduced effects", ru = "Меньше эффектов" },
	["settings.on"] = { en = "On", ru = "Вкл." },
	["settings.off"] = { en = "Off", ru = "Выкл." },
	["settings.session_only"] = { en = "Applied for this session.", ru = "Применено на эту сессию." },
	["settings.save_failed"] = { en = "Couldn't save. Reopen settings to retry.", ru = "Не удалось сохранить. Открой настройки ещё раз." },
	["ui.you"] = { en = "{name} · you", ru = "{name} · вы" },
	["intro.title"] = { en = "MARSHRUTKA 13", ru = "МАРШРУТКА 13" },
	["intro.skip"] = { en = "Skip", ru = "Пропустить" },
	["ending.good.title"] = { en = "Shift complete", ru = "Смена окончена" },
	["ending.good.sub"] = { en = "Dawn over the depot.", ru = "Рассвет над депо." },
	["ending.bad.title"] = { en = "Route 13 never ends", ru = "Маршрут 13 не заканчивается" },
	["ending.bad.sub"] = { en = "The minibus keeps going.", ru = "Маршрутка не останавливается." },
	["lobby.title"] = { en = "Depot", ru = "Депо" },
	["lobby.ready"] = { en = "Ready", ru = "Готов" },
	["lobby.waiting"] = { en = "Waiting", ru = "Ждёт" },
	["lobby.waiting_players"] = { en = "Waiting for players", ru = "Ожидание игроков" },
	["lobby.countdown"] = { en = "Starts in {seconds}s", ru = "Старт через {seconds} с" },
	["lobby.departing"] = { en = "Departing…", ru = "Отправляемся…" },
	["lobby.countdown_started"] = { en = "Countdown started", ru = "Отсчёт начался" },
	["lobby.unready"] = { en = "Cancel readiness", ru = "Отменить готовность" },
	["tutorial.open"] = { en = "How to play", ru = "Как играть" },
	["tutorial.roles"] = { en = "You are the conductor or the driver.", ru = "Ты кондуктор или водитель." },
	["tutorial.tools"] = { en = "Spot anomalies with the mirror, flashlight and tickets.", ru = "Ищи аномалии: зеркало, фонарь, билет." },
	["tutorial.eject"] = { en = "Eject them before the next stop.", ru = "Высади их до следующей остановки." },
	["tutorial.next"] = { en = "Next", ru = "Далее" },
	["tutorial.done"] = { en = "Done", ru = "Готово" },
	["driver.throttle"] = { en = "Gas", ru = "Газ" },
	["driver.brake"] = { en = "Brake", ru = "Тормоз" },
	["driver.horn"] = { en = "Horn", ru = "Сигнал" },
	["driver.doors"] = { en = "Doors", ru = "Двери" },
	["hud.guide"] = { en = "Conductor's Guide", ru = "Памятка кондуктора" },
	["rules.title"] = { en = "Minibus Rules", ru = "Правила маршрутки" },
	["night.card"] = { en = "NIGHT {number} · {name}", ru = "НОЧЬ {number} · {name}" },
	["night.choose"] = { en = "Choose night", ru = "Выбрать ночь" },
	["night.leader"] = { en = "Leader · {name}", ru = "Лидер · {name}" },
	["night.no_leader"] = { en = "The first ready player leads", ru = "Лидер — первый готовый игрок" },
	["night.locked"] = { en = "Locked", ru = "Закрыта" },
	["night.selected"] = { en = "Selected", ru = "Выбрана" },
	["night.unlocked"] = { en = "Night {number} unlocked!", ru = "Ночь {number} открыта!" },
	["ghost.title"] = { en = "You are a ghost", ru = "Ты призрак" },
	["ghost.knock"] = { en = "Knock", ru = "Постучать" },
	["ghost.flicker"] = { en = "Flicker lights", ru = "Мигнуть светом" },
	["ghost.return"] = { en = "Return", ru = "Вернуться" },
	["ghost.buy_return"] = { en = "Buy a return", ru = "Купить возвращение" },
	["ghost.return_unavailable"] = { en = "Return unavailable", ru = "Возвращение недоступно" },
	["ghost.no_target"] = { en = "Look at a passenger", ru = "Посмотри на пассажира" },
	["night.1.name"] = { en = "First Trip", ru = "Первый рейс" },
	["night.2.name"] = { en = "Fog", ru = "Туман" },
	["night.3.name"] = { en = "Grandma", ru = "Бабушка" },
	["night.4.name"] = { en = "Keep the Light Off", ru = "Не свети" },
	["night.5.name"] = { en = "Terminus", ru = "Конечная" },
	["rule.eject_anomalies"] = { en = "Eject dangerous passengers before the next stop.", ru = "Высаживай опасных пассажиров до следующей остановки." },
	["rule.check_tickets"] = { en = "Check for route No. 13 and the current year.", ru = "Проверь маршрут №13 и текущий год в билете." },
	["rule.controller"] = { en = "Clear the bus of anomalies before the inspector checks it.", ru = "Очисти салон от аномалий до проверки контролёра." },
	["rule.grandma"] = { en = "Leave the grandma with a bundle alone.", ru = "Бабушку с котомкой не трогай." },
	["rule.coins"] = { en = "Check the fare for strange coins.", ru = "Проверяй сдачу на странные монеты." },
	["rule.standing"] = { en = "Keep your light off anyone standing with their back to you.", ru = "Не свети на того, кто стоит к тебе спиной." },
	["rule.blackout_freeze"] = { en = "Freeze when the lights go out.", ru = "Замри, когда погаснет свет." },
	["rule.no_unscheduled_stops"] = { en = "Never stop between stops, even if someone asks.", ru = "Не тормози между остановками, даже если просят." },
	["rule.real_controller"] = { en = "The real inspector wears blue and carries a badge.", ru = "Настоящий контролёр — в синей форме с жетоном." },
	["hud.driver"] = { en = "Driver", ru = "Водитель" },
	["hud.conductor"] = { en = "Conductor", ru = "Кондуктор" },
	["hud.role_pending"] = { en = "Role —", ru = "Роль —" },
	["hud.stop"] = { en = "Stop {index}/{total} · {name}", ru = "Остановка {index}/{total} · {name}" },
	["hud.stop_pending"] = { en = "Stop —/{total}", ru = "Остановка —/{total}" },
	["hud.stop_announcement"] = { en = "Next stop: {name}", ru = "Следующая остановка: {name}" },
	["hud.stop_distance"] = { en = "To the stop: {meters} m", ru = "До остановки: {meters} м" },
	["hud.open_doors"] = { en = "Open the doors", ru = "Открывай двери" },
	["hud.health"] = { en = "Health {value}/{max}", ru = "Прочность {value}/{max}" },
	["hud.health_pending"] = { en = "Health —", ru = "Прочность —" },
	["conductor.passenger"] = { en = "Passenger", ru = "Пассажир" },
	["conductor.mirror"] = { en = "Mirror", ru = "Зеркало" },
	["conductor.rearview"] = { en = "Rear-view mirror", ru = "Зеркало заднего вида" },
	["conductor.cabin_unavailable"] = { en = "Cabin view unavailable", ru = "Салон пока недоступен" },
	["conductor.eject"] = { en = "Eject", ru = "Высадить" },
	["conductor.flashlight"] = { en = "Flashlight · {seconds}s", ru = "Фонарь · {seconds} с" },
	["conductor.ticket"] = { en = "TICKET", ru = "БИЛЕТ" },
	["conductor.ticket_details"] = { en = "Route {route}\nDate {date}", ru = "Маршрут {route}\nДата {date}" },
	["fare.pass"] = { en = "Pass the fare, please", ru = "Передайте за проезд" },
	["coin.tenge_100"] = { en = "100 tenge", ru = "100 тенге" },
	["coin.kopeck_1961"] = { en = "Kopeck · 1961", ru = "Копейка · 1961" },
	["coin.blank"] = { en = "Unmarked coin", ru = "Монета без надписей" },
	["conductor.eject_title"] = { en = "Eject passenger", ru = "Высадка пассажира" },
	["conductor.eject_confirm"] = { en = "Eject this passenger?", ru = "Точно высадить?" },
	["conductor.inspect"] = { en = "Check ticket", ru = "Проверить билет" },
	["shop.title"] = { en = "Shop", ru = "Магазин" },
	["cosmetics.tab"] = { en = "Cosmetics", ru = "Косметика" },
	["cosmetics.flashlights"] = { en = "Flashlight skins", ru = "Скины фонаря" },
	["cosmetics.effects"] = { en = "Taken effects", ru = "Эффекты «забрали»" },
	["cosmetics.equip"] = { en = "Equip", ru = "Надеть" },
	["cosmetics.equipped"] = { en = "Equipped", ru = "Выбрано" },
	["cosmetics.profile_unavailable"] = { en = "Profile is loading.", ru = "Профиль загружается." },
	["cosmetics.insufficient"] = { en = "Not enough tenge.", ru = "Не хватает тенге." },
	["cosmetics.price"] = { en = "Buy · {price} ₸", ru = "Купить · {price} ₸" },
	["cosmetics.robux"] = { en = "Buy with Robux", ru = "Купить за Robux" },
	["cosmetics.Classic"] = { en = "Classic", ru = "Классика" },
	["cosmetics.Warm"] = { en = "Warm", ru = "Тёплый свет" },
	["cosmetics.Neon"] = { en = "Neon", ru = "Неон" },
	["cosmetics.Alarm"] = { en = "Alarm", ru = "Тревога" },
	["cosmetics.Rainbow"] = { en = "Rainbow", ru = "Радуга" },
	["cosmetics.Fade"] = { en = "Fade", ru = "Растворение" },
	["cosmetics.Hands"] = { en = "Hands Below", ru = "Руки из-под пола" },
	["cosmetics.Ash"] = { en = "Ash", ru = "Пепел" },
	["cosmetics.Ceiling"] = { en = "Ceiling", ru = "Потолок" },
	["shop.vip"] = { en = "VIP Minibus", ru = "VIP-маршрутка" },
	["shop.vip_benefit"] = { en = "Skin and 2× tenge", ru = "Скин и ×2 тенге" },
	["shop.radio"] = { en = "Radio", ru = "Радио" },
	["shop.radio_benefit"] = { en = "Music in the cabin", ru = "Музыка в салоне" },
	["shop.amulet"] = { en = "Amulet", ru = "Оберег" },
	["shop.amulet_benefit"] = { en = "Saves the bus, +{health} health", ru = "Спасает автобус, +{health} прочности" },
	["shop.unavailable"] = { en = "Unavailable", ru = "Недоступно" },
	["shop.turn_off"] = { en = "Turn off", ru = "Выключить" },
	["shop.turn_on"] = { en = "Turn on", ru = "Включить" },
	["shop.owned"] = { en = "Owned", ru = "Куплено" },
	["shop.purchasing"] = { en = "Purchasing…", ru = "Покупка…" },
	["shop.buy"] = { en = "Buy", ru = "Купить" },
	["shop.music_missing"] = { en = "Radio music is not configured yet.", ru = "Музыка для радио ещё не настроена." },
	["shop.radio_unavailable"] = { en = "Radio is currently unavailable.", ru = "Радио сейчас недоступно." },
	["shop.purchase_failed"] = { en = "Could not open the purchase prompt.", ru = "Не удалось открыть покупку." },
	["results.earnings"] = { en = "Trip earnings", ru = "За рейс" },
	["results.caught"] = { en = "Anomalies", ru = "Аномалии" },
	["results.mistakes"] = { en = "Mistakes", ru = "Ошибки" },
	["results.stops"] = { en = "Stops", ru = "Остановки" },
	["results.depot"] = { en = "Back to depot", ru = "В депо" },
	["results.win"] = { en = "Victory", ru = "Победа" },
	["results.loss"] = { en = "Defeat", ru = "Поражение" },
	["results.preview"] = { en = "Preview results", ru = "Пример итогов" },
	["results.preview_toast"] = { en = "Preview toast", ru = "Пример тоста" },
	["notify.next_stop"] = { en = "Next stop", ru = "Следующая остановка" },
	["notify.doors_open"] = { en = "The doors are still open.", ru = "Двери ещё открыты" },
	["notify.anomaly_ejected"] = { en = "Ejected: {anomaly} · +{reward} ₸", ru = "Высажена аномалия «{anomaly}» · +{reward} ₸" },
	["notify.human_ejected"] = { en = "That passenger was human · −{penalty} ₸", ru = "Пассажир был человеком · −{penalty} ₸" },
	["notify.amulet_saved"] = { en = "{player}'s amulet saved the bus!", ru = "Оберег игрока {player} спас автобус!" },
	["toast.anomaly_ejected"] = { en = "Anomaly ejected.", ru = "Аномалия высажена" },
	["toast.human_ejected"] = { en = "That passenger was human.", ru = "Пассажир был человеком" },
	["toast.amulet_saved"] = { en = "An amulet saved the bus!", ru = "Оберег спас автобус!" },
	["notify.trip_finished"] = { en = "Last stop! The trip is over.", ru = "Конечная! Рейс окончен" },
	["notify.returned_to_bus"] = { en = "You fell behind and were returned to the cabin.", ru = "Ты отстал от маршрутки — вернули в салон" },
	["notify.balance_unavailable"] = { en = "Your balance is temporarily unavailable.", ru = "Баланс временно недоступен." },
	["notify.balance_restored"] = { en = "Your balance is available again.", ru = "Баланс снова доступен." },
	["notify.amulet_added"] = { en = "Amulet added.", ru = "Оберег добавлен." },
	["notify.safe_ejected"] = { en = "They were on our side · −{penalty} ₸", ru = "Это был свой пассажир · −{penalty} ₸" },
	["notify.stop_request"] = { en = "“Stop here, please!”", ru = "«Остановите здесь, пожалуйста!»" },
	["notify.controller_boarded"] = { en = "The inspector is on board.", ru = "В салон вошёл контролёр." },
	["notify.controller_clean"] = { en = "Inspection passed · +{bonus} ₸", ru = "Проверка пройдена · +{bonus} ₸" },
	["notify.controller_found"] = { en = "The inspector found {count} anomalies.", ru = "Контролёр нашёл аномалии: {count}." },
	["notify.player_taken"] = { en = "{player} was taken.", ru = "Забрали игрока {player}." },
	["notify.player_revived"] = { en = "{player} returned to the bus.", ru = "Игрок {player} вернулся в салон." },
	["notify.freeze"] = { en = "The lights are out. Freeze!", ru = "Свет погас. Замри!" },
	["stop.sign"] = { en = "{index}. {name}", ru = "{index}. {name}" },
	["stop.1"] = { en = "Market", ru = "Рынок" },
	["stop.2"] = { en = "Hospital", ru = "Больница" },
	["stop.3"] = { en = "School No. 13", ru = "Школа №13" },
	["stop.4"] = { en = "Old Bridge", ru = "Старый мост" },
	["stop.5"] = { en = "Factory", ru = "Завод" },
	["stop.6"] = { en = "Cemetery", ru = "Кладбище" },
	["stop.7"] = { en = "Substation", ru = "Подстанция" },
	["stop.8"] = { en = "Terminus", ru = "Конечная" },
	["anomaly.NoReflection.name"] = { en = "No reflection", ru = "Без отражения" },
	["anomaly.NoReflection.hint"] = { en = "Look in the mirror. Is anyone missing?", ru = "Посмотри в зеркало: кого-то из пассажиров в нём нет?" },
	["anomaly.WrongTicket.name"] = { en = "A ticket from 1986", ru = "Билет из 1986-го" },
	["anomaly.WrongTicket.hint"] = { en = "Check the tickets for route No. 13 and the current year.", ru = "Проверь билеты: маршрут должен быть №13, а год — нынешний." },
	["anomaly.NoShadow.name"] = { en = "Ghost", ru = "Призрак" },
	["anomaly.NoShadow.hint"] = { en = "Shine your flashlight on them. Some passengers turn see-through.", ru = "Посвети фонариком: сквозь некоторых пассажиров просвечивает." },
	["anomaly.GlowingEyes.name"] = { en = "Glowing eyes", ru = "Светящиеся глаза" },
	["anomaly.GlowingEyes.hint"] = { en = "If their eyes glow in the flashlight beam, look closer.", ru = "В темноте фонарик отражается в глазах только у… них." },
	["anomaly.Twin.name"] = { en = "Double", ru = "Двойник" },
	["anomaly.Twin.hint"] = { en = "Two identical passengers? One of them doesn't belong.", ru = "Два одинаковых пассажира? Один из них лишний." },
	["anomaly.WrongHead.name"] = { en = "Head turned backwards", ru = "Голова задом наперёд" },
	["anomaly.WrongHead.hint"] = { en = "Look closely at which way each passenger is facing.", ru = "Присмотрись, куда смотрят пассажиры. Все ли смотрят вперёд?" },
	["anomaly.StrangeCoin.name"] = { en = "Strange Coin", ru = "Странная монета" },
	["anomaly.StrangeCoin.hint"] = { en = "Fares are paid in tenge. Watch for kopecks or blank coins.", ru = "Платят только тенге. Копейки и монеты без надписей — не наши." },
	["anomaly.Grandma.name"] = { en = "Grandma with a Bundle", ru = "Бабушка с котомкой" },
	["anomaly.Grandma.hint"] = { en = "Leave the grandma in a headscarf with a bundle alone. She's on our side.", ru = "Бабушку в платке с котомкой не трогай. Она странная, но своя." },
	["anomaly.Standing.name"] = { en = "Facing Away", ru = "Стоящий спиной" },
	["anomaly.Standing.hint"] = { en = "Never shine your flashlight at someone standing with their back to you.", ru = "Если пассажир стоит в проходе спиной к тебе, не свети на него фонарём." },
	["anomaly.StopRequest.name"] = { en = "“Stop Here!”", ru = "«Остановите здесь!»" },
	["anomaly.StopRequest.hint"] = { en = "Never stop between stops, no matter who asks.", ru = "Не останавливайся между остановками, кто бы ни просил." },
	["anomaly.FakeController.name"] = { en = "Fake Inspector", ru = "Фальшивый контролёр" },
	["anomaly.FakeController.hint"] = { en = "The real inspector wears blue and carries a badge. Eject impostors.", ru = "Настоящий контролёр в синей форме с жетоном. Самозванца высаживай." },
}

local locale = LocalizationService.RobloxLocaleId
if RunService:IsStudio() then
	local previewLocale = Workspace:GetAttribute("StudioLocale")
	if type(previewLocale) == "string" then
		locale = previewLocale
	end
end
local isRussian = string.match(string.lower(locale), "^([a-z]+)") == "ru"

local Strings = {}

function Strings.get(key: string, parameters: Parameters?): string
	local entry = catalog[key]
	if not entry then
		return key
	end
	local translated = if isRussian then entry.ru else entry.en
	if type(parameters) ~= "table" then
		return translated
	end
	local formatted = string.gsub(translated, "{([%w_]+)}", function(name)
		local value = parameters[name]
		local kind = type(value)
		return if kind == "string" or kind == "number" or kind == "boolean" then tostring(value) else "{" .. name .. "}"
	end)
	return formatted
end

function Strings.stopName(index: number, fallback: string?): string
	local entry = catalog[`stop.{index}`]
	if not entry then
		return fallback or tostring(index)
	end
	if fallback and fallback ~= "" and fallback ~= entry.ru and fallback ~= entry.en then
		return fallback
	end
	return if isRussian then entry.ru else entry.en
end

function Strings.notify(key: string, parameters: Parameters?): string
	if string.sub(key, 1, 7) ~= "notify." then
		return key
	end
	local params: Parameters = if type(parameters) == "table" then parameters else {}
	if key == "notify.anomaly_ejected" then
		local anomalyId, reward = params.anomalyId, params.reward
		if type(anomalyId) == "string" and type(reward) == "number" then
			local nameKey = `anomaly.{anomalyId}.name`
			if catalog[nameKey] then
				return Strings.get(key, { anomaly = Strings.get(nameKey), reward = reward })
			end
		end
		return Strings.get("toast.anomaly_ejected")
	elseif key == "notify.human_ejected" then
		local penalty = params.penalty
		return if type(penalty) == "number"
			then Strings.get(key, { penalty = math.abs(penalty) })
			else Strings.get("toast.human_ejected")
	elseif key == "notify.amulet_saved" then
		local player = params.player
		return if type(player) == "string" and player ~= ""
			then Strings.get(key, { player = player })
			else Strings.get("toast.amulet_saved")
	end
	return Strings.get(key, params)
end

return table.freeze(Strings)
