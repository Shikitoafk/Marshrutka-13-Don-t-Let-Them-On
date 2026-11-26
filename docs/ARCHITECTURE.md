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

### Общее (владелец: оркестратор)

`src/shared/Remotes.luau`, `src/shared/Config.luau`, `src/shared/AnomalyTypes.luau`, `docs/*`.

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
  его `LookVector` = вперёд. Только он заякорен, остальное приварено к нему.
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
| `DoorsRequest` | `open: boolean` | Только Водитель, только при скорости ≈0 |
| `HornRequest` | — | Только Водитель, кулдаун 1 сек |
| `InspectPassenger` | `passengerId: string, tool: "Ticket" \| "Flashlight"` | Кондуктор, дистанция ≤ `INSPECT_RANGE`, кулдаун |
| `EjectPassenger` | `passengerId: string` | Кондуктор, дистанция ≤ `INSPECT_RANGE`, двери открыты ИЛИ скорость ≈0 |
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
| `Notify` | `text: string, kind: "Info" \| "Warn" \| "Good" \| "Bad"` |

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

## Пассажиры

- Каждая модель пассажира лежит в `Workspace.Map.Bus.Passengers` (или в зоне остановки, пока ждёт).
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
