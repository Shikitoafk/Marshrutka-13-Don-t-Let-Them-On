--!strict
-- Вступительная заставка (T21). При первом входе (флаг профиля ShowTutorial от DataService) ~18 с: камера летит над
-- ночным городом к маршрутке в депо, та выплывает из тумана, моргают фары, в кабине появляется тёмный силуэт водителя,
-- с шипением открываются двери, крупно «MARSHRUTKA 13», камера заходит в салон и отдаёт управление.
-- Всё локально и без ремоутов: автобус серверный — его не двигаем, двигается камера; фары и силуэт — свои детали,
-- двери — свой C0 на время заставки. Чужие экраны на это время вынимаем из PlayerGui и возвращаем как были —
-- поэтому лобби и карточки обучения T16 (они откроются сами по ShowTutorial) видны сразу после заставки.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local IntroController = {}

local FLAG_WAIT = 10 -- сек ждём флаг профиля; не пришёл (DataStore недоступен) — без заставки
local AMBER = Color3.fromRGB(246, 198, 110) -- как номер маршрута на табличке
local HEADLIGHT = Color3.fromRGB(255, 236, 190)
local SILHOUETTE = Color3.fromRGB(8, 8, 10)
local PANEL = Color3.fromRGB(21, 28, 39)
local DOOR_SLIDE_OUT = 0.4 -- как в RouteService: открытая дверь отъезжает наружу

local localPlayer = Players.LocalPlayer
local roundState: string? = nil
local playing = false
local stopIntro: (() -> ())? = nil

-- shortcut: ключей intro.* в Strings пока нет (файл CX) — до них показываем запасной текст.
local function text(key: string, fallback: string): string
	local value = Strings.get(key)
	return if value == key then fallback else value
end

local function play()
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	if playing or not (bus and bus:IsA("Model")) or (roundState ~= nil and roundState ~= "Lobby" and roundState ~= "Countdown") then
		return
	end
	playing = true
	if not localPlayer.Character then
		localPlayer.CharacterAdded:Wait() -- иначе появление персонажа сбросит камеру посреди заставки
	end

	local camera = Workspace.CurrentCamera
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local studio = RunService:IsStudio()

	-- Точки в координатах автобуса: x — вправо (двери), y — от низа автобуса, z — назад (вперёд = −z).
	local box, size = bus:GetBoundingBox()
	local function at(x: number, y: number, z: number): CFrame
		return box * CFrame.new(x, y - size.Y / 2, z)
	end
	local function look(from: CFrame, to: CFrame): CFrame
		return CFrame.lookAt(from.Position, to.Position)
	end

	local frontDoor = bus:FindFirstChild("DoorFront")
	local doorPosition = if frontDoor and frontDoor:IsA("Model")
		then frontDoor:GetPivot().Position
		elseif frontDoor and frontDoor:IsA("BasePart") then frontDoor.Position
		else at(size.X / 2, 4, -size.Z / 4).Position
	local door = box:PointToObjectSpace(doorPosition) + Vector3.new(0, size.Y / 2, 0)

	local doors: { { weld: Weld, closed: CFrame } } = {}
	for _, name in { "DoorFront", "DoorBack" } do
		local found = bus:FindFirstChild(name)
		local weld = if found then found:FindFirstChildWhichIsA("Weld", true) else nil
		if weld and weld.Part1 then
			table.insert(doors, { weld = weld, closed = weld.C0 })
		end
	end

	-- Свои детали: фары (у автобуса их нет) и силуэт водителя. Только у этого игрока, удаляем в конце.
	local props = Instance.new("Folder")
	props.Name = "IntroProps"
	props.Parent = Workspace
	local function prop(name: string, partSize: Vector3, cframe: CFrame, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = partSize
		part.CFrame = cframe
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = false, false, false, false
		part.Parent = props
		return part
	end
	local lamps: { Part } = {}
	for _, side in { -1, 1 } do
		local lamp = prop("Headlight", Vector3.new(1.6, 0.8, 0.2), at(side * (size.X / 2 - 1.6), size.Y * 0.3, -size.Z / 2 - 0.1), HEADLIGHT)
		lamp.Material = Enum.Material.Neon
		lamp.Transparency = 1
		table.insert(lamps, lamp)
	end
	local beamHolder = prop("HeadlightBeam", Vector3.one, at(0, size.Y * 0.3, -size.Z / 2 - 0.6), HEADLIGHT)
	beamHolder.Transparency = 1
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front -- вперёд по ходу автобуса
	beam.Range = 60
	beam.Angle = 70
	beam.Brightness = 4
	beam.Color = HEADLIGHT
	beam.Shadows = false
	beam.Enabled = false
	beam.Parent = beamHolder

	local function setLights(on: boolean)
		for _, lamp in lamps do
			lamp.Transparency = if on then 0 else 1
		end
		beam.Enabled = on
	end

	local function showDriver()
		local seat = bus:FindFirstChild("DriverSeat", true)
		if seat and seat:IsA("BasePart") then
			prop("DriverBody", Vector3.new(2, 2.4, 1.1), seat.CFrame * CFrame.new(0, 1.8, 0.2), SILHOUETTE)
			local head = prop("DriverHead", Vector3.new(1.3, 1.3, 1.3), seat.CFrame * CFrame.new(0, 3.75, 0.2), SILHOUETTE)
			head.Shape = Enum.PartType.Ball
		end
	end

	-- Экран заставки: затемнение, название, «Пропустить» (крупная кнопка для телефона).
	local screen = Instance.new("ScreenGui")
	screen.Name = "Intro"
	screen.AutoLocalize = false
	screen.DisplayOrder = 20 -- выше всех экранов игры (самый высокий — HorrorController, 10)
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false

	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Parent = screen

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.4)
	title.Size = UDim2.fromScale(0.9, 0.2)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = AMBER
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextTransparency = 1
	title.TextStrokeTransparency = 1
	title.Text = text("intro.title", "MARSHRUTKA 13")
	title.ZIndex = 2
	title.Parent = screen
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 110
	titleLimit.Parent = title

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.fromScale(0.97, 0.95)
	skip.Size = UDim2.fromScale(0.2, 0.09)
	skip.BackgroundColor3 = PANEL
	skip.BackgroundTransparency = 0.25
	skip.BorderSizePixel = 0
	skip.Font = Enum.Font.GothamBold
	skip.TextScaled = true
	skip.TextColor3 = Color3.fromRGB(250, 244, 231)
	skip.Text = text("intro.skip", "Skip")
	skip.ZIndex = 3
	skip.Parent = screen
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 12)
	skipCorner.Parent = skip
	local skipMin = Instance.new("UISizeConstraint")
	skipMin.MinSize = Vector2.new(130, 48)
	skipMin.Parent = skip
	local skipText = Instance.new("UITextSizeConstraint")
	skipText.MaxTextSize = 28
	skipText.Parent = skip
	screen.Parent = playerGui

	-- Чужие экраны (лобби, HUD…) вынимаем, а не выключаем: их владельцы сами меняют Enabled по RoundState,
	-- и после заставки всё окажется в том состоянии, которое они выставили. Экраны со своими скриптами не трогаем.
	local parked: { ScreenGui } = {}
	local hiding = true
	local function park(gui: Instance)
		if hiding and gui ~= screen and gui:IsA("ScreenGui") and gui.Parent == playerGui and gui.Name ~= "TouchGui"
			and not gui:FindFirstChildWhichIsA("LocalScript", true)
		then
			table.insert(parked, gui)
			gui.Parent = nil
		end
	end
	for _, gui in playerGui:GetChildren() do
		park(gui)
	end
	local added = playerGui.ChildAdded:Connect(function(gui)
		task.defer(park, gui) -- менять Parent прямо в ChildAdded нельзя
	end)

	local controls: any = nil
	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
	local playerModule = if playerScripts then playerScripts:FindFirstChild("PlayerModule") else nil
	if playerModule then
		local ok, module = pcall(require, playerModule :: any)
		if ok then
			controls = module:GetControls()
			controls:Disable() -- персонаж в депо не бегает, пока камера в заставке
		end
	end

	local tweens: { Tween } = {}
	local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
		local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
		table.insert(tweens, t)
		t:Play()
	end
	local function move(to: CFrame, seconds: number, style: Enum.EasingStyle?)
		camera.CameraType = Enum.CameraType.Scriptable
		tween(camera, seconds, { CFrame = to }, style)
	end
	-- В Studio можно задержать кадр для скриншота: Workspace.StudioIntroHold = имя кадра.
	local function hold(seconds: number, shot: string)
		task.wait(seconds)
		while studio and Workspace:GetAttribute("StudioIntroHold") == shot do
			task.wait(0.2)
		end
	end

	local thread: thread? = nil
	local finishing = false
	local function finish()
		if finishing then
			return
		end
		finishing = true
		if thread and thread ~= coroutine.running() then
			task.cancel(thread)
		end
		for _, t in tweens do
			t:Cancel()
		end
		TweenService:Create(fade, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
		task.wait(0.3)
		title.Visible, skip.Visible = false, false
		for _, d in doors do
			d.weld.C0 = d.closed
		end
		props:Destroy()
		hiding = false
		added:Disconnect()
		for _, gui in parked do
			pcall(function()
				gui.Parent = playerGui -- уже удалённый владельцем экран вернуть нельзя — пропускаем
			end)
		end
		if controls then
			pcall(controls.Enable, controls)
		end
		camera.CameraType = Enum.CameraType.Custom
		local character = localPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			camera.CameraSubject = humanoid
		end
		TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.wait(0.6)
		screen:Destroy()
		stopIntro = nil
		playing = false
	end
	stopIntro = finish
	skip.Activated:Connect(finish)

	local function sequence()
		-- 1. Пролёт над ночным городом к депо: маршрутка выплывает из тумана.
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = look(at(70, 75, -300), at(0, 0, -230))
		tween(fade, 1.2, { BackgroundTransparency = 1 })
		move(look(at(30, 30, -120), at(0, 4, 0)), 5.5)
		hold(5.5, "flight")
		-- 2. Низко к морде автобуса.
		local front = at(0, size.Y * 0.4, -size.Z / 2)
		move(look(at(9, 5, -size.Z / 2 - 22), front), 3)
		hold(3, "approach")
		-- 3. Фары моргают — и в кабине уже кто-то сидит.
		for _ = 1, 2 do
			setLights(true)
			task.wait(0.18)
			setLights(false)
			task.wait(0.18)
		end
		setLights(true)
		showDriver()
		hold(0.8, "lights")
		-- 4. К передней двери; двери с шипением открываются.
		local doorPoint = at(door.X, door.Y, door.Z)
		move(look(at(door.X + 9, door.Y + 1.5, door.Z - 7), doorPoint), 2)
		task.wait(0.8)
		for _, d in doors do
			tween(d.weld, 0.9, { C0 = CFrame.new(DOOR_SLIDE_OUT, 0, (d.weld.Part1 :: BasePart).Size.Z) * d.closed })
		end
		if Config.SOUNDS.DoorOpen ~= "rbxassetid://0" then -- пока ID не вписан — без звука и без ошибки загрузки
			local hiss = Instance.new("Sound")
			hiss.SoundId = Config.SOUNDS.DoorOpen
			hiss.Volume = 0.8
			hiss.Parent = props
			hiss:Play()
		end
		hold(1.4, "doors")
		-- 5. Крупно название, камера медленно подходит к двери.
		tween(title, 0.8, { TextTransparency = 0, TextStrokeTransparency = 0.4 })
		move(look(at(door.X + 4.5, door.Y + 1.5, door.Z - 2), at(door.X, door.Y + 1, door.Z)), 3, Enum.EasingStyle.Linear)
		hold(3, "title")
		-- 6. Название гаснет, камера заходит в салон — дальше управление у игрока.
		tween(title, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
		move(look(at(0, door.Y + 1.5, door.Z), at(0, door.Y + 1.5, size.Z / 2)), 2)
		hold(2.2, "cabin")
	end

	thread = task.spawn(function()
		local ok, err = pcall(sequence :: any)
		if not ok then
			warn(`[Intro] заставка прервалась: {err}`)
		end
		finish()
	end)
end

function IntroController:Init(_controllers: { [string]: any })
	-- В Init, чтобы не пропустить снимок RoundState при входе: опоздавшего посадят в рейс — заставку обрываем.
	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		roundState = state
		if state ~= "Lobby" and state ~= "Countdown" and stopIntro then
			task.spawn(stopIntro)
		end
	end)
end

function IntroController:Start()
	if RunService:IsStudio() then
		-- Studio: Workspace.StudioIntroPreview = true — показать заставку (снова — выключить и включить).
		Workspace:GetAttributeChangedSignal("StudioIntroPreview"):Connect(function()
			if Workspace:GetAttribute("StudioIntroPreview") == true then
				play()
			end
		end)
		if Workspace:GetAttribute("StudioIntroPreview") == true then
			play()
			return
		end
	end
	local deadline = os.clock() + FLAG_WAIT
	while localPlayer:GetAttribute("ShowTutorial") == nil and os.clock() < deadline do
		task.wait(0.25)
	end
	if localPlayer:GetAttribute("ShowTutorial") == true then
		play()
	end
end

return IntroController
