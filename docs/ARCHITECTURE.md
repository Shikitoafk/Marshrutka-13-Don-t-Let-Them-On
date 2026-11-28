# Архитектура

## Как устроен проект

Код живёт в git и синхронизируется в Roblox Studio через **Rojo**.
Карта, модели и всё 3D живут в плейсе Studio (не в git).

| Папка в репо | Куда попадает в Studio | Что там |
|---|---|---|
| `src/server` | `ServerScriptService.Server` | Серверная логика: `Main.server.luau` + `Services/` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | Клиентская логика: `Main.client.luau` + `Controllers/` |
| `src/shared` | `ReplicatedStorage.Shared` | Общие контракты и данные: `Remotes`, `Config`, `AnomalyTypes` |

### Паттерн сервисов и контроллеров

- Каждый сервис — ModuleScript в `src/server/Services/`, каждый контроллер — в `src/client/Controllers/`.
- Модуль возвращает таблицу с методами `:Init(registry)` и `:Start()`.
- `Main` сам находит и запускает все модули. Регистрировать ничего не нужно.
- Другой сервис берём из `registry` в `Init`, а вызываем только начиная со `Start`.
- Шаблоны: `_ServiceTemplate.luau`, `_ControllerTemplate.luau`. Файлы на `_` загрузчик пропускает.

## Модули и владельцы

Чтобы два AI не правили один файл, у каждого модуля есть **один владелец**.
Чужие файлы не трогаем. Если нужно изменение — пишем в PR.

### Сервер (владелец: Claude Code)

| Модуль | Отвечает за |
|---|---|
| `GreyboxService` | Создаёт тестовый маршрут, остановки и автобус, если `Workspace.Map` нет |
| `RouteService` | Движение маршрутки по точкам, скорость, зоны остановок, двери, автопилот |
| `RoundService` | Состояния раунда: Lobby → Countdown → Running → Results |
| `RoleService` | Назначение ролей Водитель/Кондуктор, переназначение при выходе игрока |
| `PassengerService` | Спавн NPC на остановках, посадка на места, выход, плата за проезд |
| `AnomalyService` | Какие пассажиры аномалии, подсказки (атрибуты), проверки, высадка, эскалация, прочность |

### Сервер V2 (владелец: Claude Code)

| Модуль | Отвечает за |
|---|---|
| `NightService` | Текущая ночь (выбор лидером в лобби), рассылка `NightInfo`, пул аномалий из `Nights.luau`, звёзды и разблокировка через DataService, контролёр, блэкаут-«замри», просьбы остановиться |
| `GhostService` | API: `IsGhost`, `CountTaken`, `Take`, `Revive(player): boolean`, `GetRevivesLeft(): number`. «Забрали» → призрак (`PlayerTaken`, `GhostState`), действия призраков (`GhostAction`), возрождение (`ReviveRequest`/продукт), проигрыш, если призраки все |

### Сервер (владелец: Codex)

| Модуль | Отвечает за |
|---|---|
| `DataService` | Сохранение тенге, статистики, покупок (DataStore), leaderstats |
| `MonetizationService` | Gamepass'ы, Developer Products (`ProcessReceipt`), x2 тенге для VIP |

### Клиент (владелец: Codex)

| Модуль | Отвечает за |
|---|---|
| `DriverController` | Кнопки и клавиши водителя (Газ/Тормоз/Двери/Сигнал), камера водителя |
| `ConductorController` | Инструменты: зеркало (ViewportFrame), фонарик, проверка билета, высадка |
| `HudController` | Остановка N/8 и название, прочность, тенге, роль, «Памятка кондуктора» |
| `LobbyController` | UI депо: кнопка «Готов», отсчёт, список игроков |
| `ResultsController` | Экран результатов рейса |
| `AtmosphereController` | Свет, туман, звуки, эффекты эскалации (мигание, шипение, блэкаут) |
| `ShopController` | Окно покупки VIP/Радио/Оберега |
| `HorrorController` | Пугалки `ScareEvent`, постобработка, сердцебиение, скример (T19) |
| `RulesController` | Листок «Правила маршрутки» на стене салона (SurfaceGui) и по кнопке; карточка «НОЧЬ 2 · Туман» в начале рейса (V2) |
| `GhostController` | Вид призрака, кнопки «Постучать»/«Мигнуть светом», кнопка возвращения (V2) |

### Клиент (владелец: Claude Code)

| Модуль | Отвечает за |
|---|---|
| `IntroController` | Вступительная заставка при первом входе (T21) |
| `EndingController` | Финал 5-й ночи: катсцена концовки (V10) |

### Общее (владелец: оркестратор)

`src/shared/Remotes.luau`, `src/shared/Config.luau`, `src/shared/AnomalyTypes.luau`, `src/shared/Nights.luau`, `docs/*`, `.github/*`.

Серверный `FlashlightService` (фонарь-Tool, батарея, B10) — владелец CX.

Общие модули CX: `src/shared/Strings.luau`, `src/shared/Cosmetics.luau`, `src/shared/PlayerSettings.luau`; клиентские `src/client/ClientSettings.luau`, `src/client/SettingsAudio.luau`.

## Что код ожидает в Workspace (договорённость с теми, кто строит карту)

```
Workspace
└── Map
    ├── Route                 Folder: Part'ы с именами "001", "002", … — точки дороги по порядку
    ├── Stops                 Folder: Part'ы-зоны остановок, атрибуты: StopIndex (number 1..8), StopName (string)
    │                         + внутри каждой: Part "Spawn" — где стоят ждущие пассажиры
    └── Bus                   Model с PrimaryPart
        ├── DriverSeat        VehicleSeat или Seat — место водителя
        ├── Seats             Folder: Seat'ы для пассажиров
        ├── DoorFront, DoorBack  Model/Part — двери (анимация через TweenService)
        ├── Mirror            Part — зеркало заднего вида; смотрит НАЗАД в салон: камера зеркала = Mirror.CFrame
        └── InteriorLights    Folder: Part'ы-плафоны, PointLight ВНУТРИ каждого
                              (искать: InteriorLights:GetDescendants() + IsA("Light"))
ServerStorage
└── PassengerRigs             Folder: R15-модели пассажиров (разная одежда); если пусто — генерим простые
```

Пока карты нет, `GreyboxService` строит всё это из простых блоков с теми же именами,
поэтому код можно писать и тестировать сразу.

### Геометрия (договорились по PR #3, обязательно и для настоящей карты)

- `Bus.PrimaryPart` (в greybox — невидимый `Root`) стоит внизу по центру автобуса на уровне дороги,
  его `LookVector` = вперёд. В редакторе заякорен только он, остальное приварено к нему.
- **Во время игры автобус НЕ заякорен**: `RouteService` снимает якорь с `PrimaryPart` и двигает автобус физикой
  (`LinearVelocity` + `AlignOrientation`), поэтому персонажей в салоне везёт сам Roblox (решение по PR #7).
  Не якорить детали автобуса и не двигать его через CFrame/PivotTo во время рейса.
- Двери — на **правом** борту (со стороны тротуара и `Spawn`). Двери держатся на `Weld` (анимируем `C0`).
- Зона остановки лежит на дороге и повёрнута вдоль движения (`LookVector` — куда едем), её `Spawn` — справа.
- Точки `Route` стоят на поверхности дороги.
- Сиденья: чтобы игроки не садились случайно, задев сиденье, `PassengerService` ставит пассажирским
  `Seat` `CanTouch = false`, а NPC сажает через `Seat:Sit(humanoid)`.

## Ремоуты (контракт сети)

Все объявлены в `src/shared/Remotes.luau`. Добавлять новые — только через оркестратора.

### Клиент → Сервер (сервер ВСЕГДА проверяет: роль, дистанцию, кулдаун, тип аргументов)

| Событие | Аргументы | Кто может |
|---|---|---|
| `DriverInput` | `throttle: number` от −1 до 1 | Только Водитель |
| `DoorsRequest` | `open: boolean` | Водитель; если водителя нет (автопилот) — любой живой Кондуктор в салоне (V12). Только при скорости ≈0 |
| `HornRequest` | — | Только Водитель, кулдаун 1 сек |
| `InspectPassenger` | `passengerId: string, tool: "Ticket" \| "Flashlight"` | Кондуктор, дистанция ≤ `INSPECT_RANGE`, кулдаун |
| `EjectPassenger` | `passengerId: string` | Кондуктор, дистанция ≤ `INSPECT_RANGE`, кулдаун. **Можно в любой момент рейса**, в том числе на ходу (решение по PR #4: вычислил аномалию на перегоне — сразу выкинул) |
| `LobbyReady` | `ready: boolean` | Игрок в лобби |

### Сервер → Клиент

| Событие | Аргументы |
|---|---|
| `RoundState` | `state: "Lobby" \| "Countdown" \| "Running" \| "Results", data: table` |
| `RoleAssigned` | `role: "Driver" \| "Conductor"` |
| `StopChanged` | `index: number, name: string, phase: "Approaching" \| "AtStop" \| "Departed"` |
| `BusState` | `speed: number, health: number, doorsOpen: boolean` (не чаще 5 раз/сек) |
| `PassengerBoarded` | `passengerId: string` |
| `PassengerLeft` | `passengerId: string, reason: "Exited" \| "Ejected" \| "Vanished"` |
| `InspectResult` | `passengerId, tool, data` — для билета: `{Route: string, Date: string}`, для фонарика: `{}` (подсказка видна через атрибуты) |
| `AnomalyEscalated` | `level: number, effect: string` (эффекты из `Config.ESCALATION_EFFECTS`) |
| `RunEnded` | `summary: {Won: boolean, Tenge: number, Caught: number, Mistakes: number, StopsReached: number}` |
| `CurrencyChanged` | `tenge: number` — **общий баланс** игрока (не заработок за рейс). Сервер шлёт при входе игрока и при каждом изменении |
| `ScareEvent` | `name: string, data: table` — пугалка; список событий ниже, раздел «Пугалки» |
| `Notify` | `key: string, kind: "Info" \| "Warn" \| "Good" \| "Bad", params: {[string]: string\|number\|boolean}?` — **ключ** строки из `Strings.luau`, клиент переводит (см. ниже) |

### Поля `RoundState.data` (договорились по PR #2)

| Состояние | Поля `data` |
|---|---|
| `Lobby` | `Ready: {[tostring(UserId)]: true}` — кто сейчас готов |
| `Countdown` | `Ready` (как выше) + `CountdownEndsAt: number` = `workspace:GetServerTimeNow() + Config.LOBBY_COUNTDOWN` |
| `Running` | `{}` |
| `Results` | `{}` (итоги приходят отдельно в `RunEnded`) |

Правила для `RoundService`:
- Новому игроку при входе сразу отправить текущий `RoundState` (снимок), а если рейс идёт — и его `RoleAssigned`.
- При каждом изменении готовности слать `RoundState` всем, даже если само состояние не сменилось.
- Порядок при старте рейса: `RoleAssigned` каждому → затем `RoundState("Running")`.

### Водитель и кнопка прыжка

На телефоне кнопка прыжка выкидывает игрока с сиденья. Пока игрок — водитель в рейсе,
`RoleService`/`RouteService` на сервере держит его на `DriverSeat` (`Seat.Disabled = false`,
у Humanoid `JumpPower = 0` / `JumpHeight = 0`, вернуть после рейса).

### RemoteFunction

| Функция | Возвращает |
|---|---|
| `GetProfile` | `{Tenge, Stats = {Runs, Wins, Caught}, OwnedSkins}` |

## API серверных сервисов (для вызова из других сервисов через registry)

| Сервис | Метод | Примечание |
|---|---|---|
| `DataService` | `AddTenge(player, amount): boolean` | Целое число, может быть отрицательным. **Может подождать** загрузки профиля — вызывать из `task.spawn`, если нельзя ждать. `false` — профиль недоступен. **VIP x2 применяется внутри** (только к положительным суммам) — сами не умножайте. Для итогов `RunEnded.Tenge` учитывайте x2 через `MonetizationService:HasVIP` |
| `DataService` | `IncrementStat(player, "Runs" \| "Wins" \| "Caught"): boolean` | То же |
| `DataService` | `GetProfile(player): Profile?` | Копия; `nil`, пока не загружен |
| `RoleService` | `GetDriver(): Player?`, `AssignRoles(players)`, `AddConductor(player)`, `ClearRoles()` | `nil` = автопилот |
| `RouteService` | `StartRun()`, `ResetRun()`, `StopRun()`, `IsFinished(): boolean` | `ResetRun` — только когда в салоне никого; `StopRun` — поражение, плавное торможение |
| `RouteService` | сигналы `StopChanged(index, name, phase)`, `DoorsChanged(open)` | для серверных сервисов (клиентам уходят ремоуты) |
| `RoundService` | `GetRiders(): {Player}`, `EndRun(won)` | копия списка игроков рейса |
| `ScareEventService` | `OnEscalation(effect)`, `Jumpscare()` | T18 |
| модуль `src/server/RateLimit.luau` | `RateLimit.new(perSecond)` → `allow(player): boolean` | общий для серверных ремоутов (T13) |
| `PassengerService` | `Clear()`, `Eject(id): boolean`, `GetModel(id)`, `GetOnboard()`, `KeepAboard(id)` | `GetOnboard` — копия `[id] = Model` |
| `AnomalyService` | `OnBoarded(id, model): boolean`, `FinishRun(won)`, `GetHealth()`, `CountAboard(): number` | `OnBoarded` → `true`, если аномалия (сама не выйдет) |
| `AnomalyService` | `GetHealth(): number` | Прочность автобуса |
| `MonetizationService` | `HasVIP(player): boolean`, `ConsumeAmulet(player): boolean` | `ConsumeAmulet` ходит в DataStore — **ждёт**; вызывать один раз при прочности 0 |

## Сообщения `Notify` и локализация (решение по PR #14)

Сервер шлёт **ключ**, а не текст: `Notify:FireClient(player, "notify.returned_to_bus", "Warn")`.
Клиент переводит через `Strings.notify(key, params)`. Текст без префикса `notify.` клиент показывает как есть
(временная совместимость — новые сообщения только ключами). Все ключи и их параметры:

| Ключ | Кто шлёт | Параметры |
|---|---|---|
| `notify.trip_finished` | RoundService | — |
| `notify.returned_to_bus` | RoundService | — |
| `notify.anomaly_ejected` | AnomalyService | `anomalyId` (клиент сам подставит переведённое имя в `{anomaly}`), `reward` |
| `notify.human_ejected` | AnomalyService | `penalty` |
| `notify.amulet_saved` | AnomalyService | `player` (DisplayName) |
| `notify.balance_unavailable`, `notify.balance_restored`, `notify.amulet_added` | DataService / MonetizationService | — |

Новый ключ = строка в `Strings.luau` (CX) + строка в этой таблице (оркестратор).
Аномалия `NoShadow` по смыслу теперь «Призрак» (под фонарём просвечивает) — обновить `anomaly.NoShadow.*` в Strings.

## Правила аномалий (решения по PR #13)

- **Урон только после полного перегона.** Аномалия, севшая на остановке N, бьёт по автобусу на `Departed`
  остановки **N+1** и дальше (а не на отъезде от своей же остановки) — иначе у кондукторов нет времени её найти.
- **Двойник:** высадка **любого** из пары засчитывается как поимка; оставшийся становится обычным пассажиром
  (снять `TwinOf`, убрать из `truth`, вернуть обычный `exitStop`).
- **Билет:** правило для игрока — «маршрут №13 и текущий год». Дата сервера может отличаться от даты игрока на день, поэтому день и месяц не важны.

## Пугалки `ScareEvent` (решение после плейтеста 1)

Сервер решает **когда** (T18, `ScareEventService`), клиент решает **как выглядит** (T19, `HorrorController`).
Ни одна пугалка не выдаёт, кто аномалия — это атмосфера, а не подсказка.

| `name` | `data` | Что видит/слышит игрок |
|---|---|---|
| `Breakdown` | `{Active: boolean, EndsAt: number}` | V12: мотор заглох — свет мигает/гаснет, стук; `Active=false` — завели или время вышло. Силуэты у окон и «отступают под фонарём» — клиентский эффект (CX) |
| `Shadow` | `{Active: boolean, EndsAt: number}` | V13: блэкаут с Тенью (свет гаснет, аварийная красная подсветка у щитка); `Active=false` — свет вернули. Саму Тень видят все: это серверная модель |
| `AnomalyAttack` | `{PassengerId: string, UserId: number}` | V11: пропущенная опасная аномалия в конце перегона — темнота 1.5 с, пассажир вплотную к игроку, Jumpscare, затем урон |
| `WindowKnock` | `{Side: "Left" \| "Right", Z: number}` | стук + отпечатки ладоней на стекле в точке Z (координата вдоль автобуса), исчезают через 10 сек |
| `RoofBang` | `{}` | тяжёлый удар по крыше, тряска камеры, лампы качнулись |
| `FigureOnRoad` | `{Distance: number}` | тёмный силуэт стоит на дороге в тумане впереди, исчезает, когда автобус близко |
| `BackSeatFigure` | `{Duration: number}` | силуэт на заднем сиденье, пока выключен свет (вместе с `Blackout`) |
| `PhoneRing` | `{Seat: string}` | под сиденьем звонит телефон 4 сек |
| `Stare` | `{Duration: number}` | все пассажиры одновременно поворачивают головы к камере игрока (у каждого клиента — к своей) |
| `Jumpscare` | `{}` | при поражении: экран-скример на 1.5 сек + крик |

## Звуки: кто что играет (решение по PR #9/#10)

- **Сигнал** играет только сервер (`RouteService`, звук в автобусе — слышат все). Клиент сигнал сам не проигрывает.
- Всё остальное (двигатель, двери, радио, шёпот, скример, эмбиент) — клиент, `AtmosphereController`.

## V2: контракты ночей

- `src/shared/Nights.luau` — данные ночей (владелец оркестратор). `NightService` берёт отсюда аномалии/шанс/события.
- **Выбор ночи:** первый нажавший «Готов» — лидер рейса, его `NightSelect(n)` принимается, если `n ≤ UnlockedNight` лидера.
  `RoundState.data.Night` — выбранная ночь, `RoundState.data.Leader` — UserId лидера (в Lobby/Countdown; принято по PR #28).
- **Профиль (DataService, CX):** новые поля `UnlockedNight: number` (по умолчанию 1), `BestStars: {[string]: number}`
  (ключ — номер ночи строкой). API: `GetUnlockedNight(player)`, `RecordNight(player, night, stars)` (сам разблокирует
  следующую и выдаёт бейджи из `Config.BADGES`; 0 — не выдавать).
- **`RunEnded.summary`** дополняется: `Night: number, Stars: number, Taken: number`.
- **`InspectResult` билета** дополняется полем `Coin: string` (ключ Strings: `coin.tenge_100`, `coin.kopeck_1961`, `coin.blank`).
- **Призраки:** персонаж призрака остаётся в салоне, но полупрозрачный и без коллизий (сервер), инструменты кондуктора
  ему недоступны (сервер проверяет). `GhostAction("Knock", passengerId)` — стук в окно рядом с пассажиром (видят живые,
  через `ScareEvent WindowKnock` по месту), `GhostAction("Flicker")` — мигание света; кулдауны в Config.
- **Возвращение (принято по #31/#33):** `GhostState.data = {RevivesLeft, ProductId, Reason}`. `ReviveRequest` слушают двое:
  `GhostService` тратит бесплатное, пока `RevivesLeft > 0`; `MonetizationService` тратит купленный заряд, только когда
  `GhostService:GetRevivesLeft() == 0`. Чек `PRODUCT_REVIVE` → заряд в профиле → `GhostService:Revive(player)`.
- **Безопасные (Safe):** `EjectPassenger` на Safe → штраф `SAFE_EJECT_PENALTY`, `Notify notify.safe_ejected`, эффект `LightsFlicker`.
- **Особые (Special):** `Standing` — если сервер получил `InspectPassenger(id, "Flashlight")` от игрока по стоящему →
  `PlayerTaken(reason="flashlight_standing")`. `StopRequest` — пассажир с `AsksToStop` просит остановить (Notify
  `notify.stop_request`); если водитель остановился вне зоны остановки, пока просьба активна → урон `STOP_REQUEST_DAMAGE`
  (на автопилоте не бывает).
- V13 «Тень»: в блэкауте сервер ставит модель Тени в хвосте; пока темно, она идёт к ближайшему живому со скоростью
  `SHADOW_SPEED`, но стоит, если на неё светит включённый фонарь (CC зовёт `FlashlightService:IsLit(position): boolean` —
  метод добавляет CX). Дошла — `GhostService:Take(player, "shadow")`. Свет: `ProximityPrompt` «Рубильник» у щитка рядом
  с водителем (HoldDuration `SHADOW_FUSE_HOLD`). Не совмещать с поломкой. Notify: `notify.shadow`, `notify.lights_restored`.
- V13 «Фальшивая остановка»: на случайном перегоне — табличка без названия и силуэты (без B13-штрафа за проезд).
  Автопилот стоит `FAKE_STOP_WAIT` с, двери не открывает. Открыли двери — входят `FAKE_STOP_ANOMALIES` опасных аномалий,
  ошибка ночи, `notify.fake_stop_opened`. Новые правила (Strings, CX): `rule.keep_lights`, `rule.fake_stop`.
- B13, ключ Notify: `notify.stop_skipped` {stop} — водитель проехал остановку, не открыв двери.
- V12, ключи Notify: `notify.late_runner_missed` {penalty}, `notify.breakdown`, `notify.breakdown_fixed`, `notify.breakdown_taken` {player}.
  Опоздавший — обычная серверная модель пассажира (те же признаки, правда только на сервере). Пока он бежит, автопилот
  держит двери открытыми до `LATE_RUNNER_RUN_TIME + 1` с или до закрытия кондуктором. Поломка: `ProximityPrompt` «Завести»
  у двигателя в хвосте (HoldDuration = `BREAKDOWN_FIX_HOLD`, только живые Кондукторы/Водитель), таймаут → `GhostService:Take(..., "breakdown")`.
- Новые ключи Notify: `notify.safe_ejected` {penalty}, `notify.stop_request`, `notify.controller_boarded`,
  `notify.controller_clean` {bonus}, `notify.controller_found` {count}, `notify.player_taken` {player},
  `notify.player_revived` {player}, `notify.freeze` (свет погас — замри!).

## Пассажиры

- Каждая модель пассажира лежит в `Workspace.Map.Bus.Passengers` (или в зоне остановки, пока ждёт).
  Папку `Passengers` создаёт `PassengerService`, если её нет (greybox её не делает). Клиент (зеркало, подсказки) ищет пассажиров именно там.
- У каждой модели атрибут **`PassengerId`** (строка, `HttpService:GenerateGUID(false)`).
- Атрибуты-подсказки из `AnomalyTypes.CueAttribute` ставит только `AnomalyService`.
- **Правда «аномалия или нет» хранится только на сервере**, в таблице внутри `AnomalyService`.
  Никогда не ставьте атрибут вроде `IsAnomaly` на модель: читеры его увидят.

## Правила безопасности (обязательно)

1. Клиенту не доверяем: сервер проверяет каждый аргумент каждого ремоута (тип, диапазон, роль, дистанцию).
2. Деньги начисляет только сервер.
3. `ProcessReceipt` возвращает `PurchaseGranted` только после того, как покупка выдана и сохранена.
4. Ремоуты с частыми вызовами ограничиваем кулдауном на сервере.

## Стиль кода

- Luau, `--!strict` в начале каждого файла.
- Имена модулей — PascalCase, переменные — camelCase, константы — в `Config`.
- Комментарии по-русски, коротко: зачем, а не что.
- Никаких `wait()`, только `task.wait()`, `task.spawn()`, `task.delay()`.
- Никаких бесконечных `while true` без `task.wait()`; лучше `RunService.Heartbeat`.
