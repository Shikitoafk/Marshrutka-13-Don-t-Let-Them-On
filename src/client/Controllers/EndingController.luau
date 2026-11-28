--!strict
-- Финал 5-й ночи (V10). На «Конечной» последней ночи сервер шлёт RunEnded с summary.Ending = "Good" | "Bad":
-- Good (≥ 2★): туман редеет, над остановкой рассвет, свет в салоне ровный, водитель снимает фуражку — «Смена окончена».
-- Bad (1★): маршрутка не останавливается и уезжает в туман, свет гаснет, силуэт водителя медленно поворачивает голову
-- назад — «Маршрут 13 не заканчивается»; дальше депо ночи 1 (выбор ночи сбросил сервер).
-- Через RESULTS_SCREEN_TIME сервер вернёт всех в депо и перенесёт автобус, поэтому снимаем на своей копии автобуса,
-- а настоящий автобус и персонажей на это время прячем. Экраны и камеру забираем и возвращаем, как в IntroController (T21).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local EndingController = {}

local AMBER = Color3.fromRGB(246, 198, 110)
local BLOOD = Color3.fromRGB(196, 38, 38)
local SILHOUETTE = Color3.fromRGB(8, 8, 10)
local CAP = Color3.fromRGB(26, 34, 58)
local EYES = Color3.fromRGB(255, 60, 40)
local DAWN_FOG = Color3.fromRGB(196, 168, 150)
local DAWN_AMBIENT = Color3.fromRGB(118, 108, 104)
local DAWN_OUTDOOR = Color3.fromRGB(172, 150, 134) -- тёплая земля на рассвете

local localPlayer = Players.LocalPlayer
local playing = false
local stopEnding: (() -> ())? = nil


local function play(ending: string)
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	if playing or not (bus and bus:IsA("Model") and bus.PrimaryPart) then
		return
	end
	local copy = bus:Clone()
	local root = if copy then copy.PrimaryPart else nil
	if not (copy and root) then
		return
	end
	playing = true
	local camera = Workspace.CurrentCamera
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local studio = RunService:IsStudio()

	-- Копия: без пассажиров, звуков и связей с чужими деталями (сиденье водителя приварено к персонажу), сквозная.
	local passengers = copy:FindFirstChild("Passengers")
	if passengers then
		passengers:Destroy()
	end
	for _, item in copy:GetDescendants() do
		local joint = item :: any
		if item:IsA("Sound") then
			item:Destroy()
		elseif (item:IsA("JointInstance") or item:IsA("WeldConstraint"))
			and ((joint.Part0 and not joint.Part0:IsDescendantOf(copy)) or (joint.Part1 and not joint.Part1:IsDescendantOf(copy)))
		then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
		end
	end
	root.Anchored = true
	local rootStart = root.CFrame -- места в салоне считаем от стартовой точки: копия потом уезжает
	copy.Name = "EndingBus"
	copy.Parent = Workspace

	-- Настоящий автобус и все персонажи на время катсцены невидимы (только у этого игрока).
	local hidden: { Instance } = {}
	local function hide(model: Instance)
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") or item:IsA("Decal") then
				(item :: any).LocalTransparencyModifier = 1
				table.insert(hidden, item)
			end
		end
	end
	hide(bus)
	for _, player in Players:GetPlayers() do
		if player.Character then
			hide(player.Character)
		end
	end

	-- Точки в координатах автобуса: x — вправо (двери), y — от низа автобуса, z — назад (вперёд = −z).
	local box, size = copy:GetBoundingBox()
	local function at(x: number, y: number, z: number): CFrame
		return box * CFrame.new(x, y - size.Y / 2, z)
	end

	-- Силуэт водителя на копии: тело приварено к автобусу, голова — на Weld (её поворачиваем).
	local function piece(name: string, partSize: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = partSize
		part.CFrame = cframe
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
		part.Massless = true
		part.Parent = copy
		return part
	end
	local function weld(part0: BasePart, part1: BasePart, c0: CFrame): Weld
		local w = Instance.new("Weld")
		w.Part0, w.Part1, w.C0 = part0, part1, c0
		w.Parent = part1
		return w
	end
	local seat = copy:FindFirstChild("DriverSeat", true)
	local seatFrame = if seat and seat:IsA("BasePart") then seat.CFrame else at(-size.X / 4, 2, -size.Z / 2 + 4)
	local body = piece("DriverBody", Vector3.new(2, 2.4, 1.1), seatFrame * CFrame.new(0, 1.8, 0.2), SILHOUETTE)
	local bodyWeld = Instance.new("WeldConstraint")
	bodyWeld.Part0, bodyWeld.Part1 = root, body
	bodyWeld.Parent = body
	local head = piece("DriverHead", Vector3.new(1.3, 1.3, 1.3), body.CFrame * CFrame.new(0, 1.95, 0), SILHOUETTE)
	head.Shape = Enum.PartType.Ball
	local neckRest = CFrame.new(0, 1.95, 0)
	local neck = weld(body, head, neckRest)
	local capWeld: Weld? = nil
	if ending == "Good" then
		local cap = piece("DriverCap", Vector3.new(0.4, 1.45, 1.45), head.CFrame, CAP)
		cap.Shape = Enum.PartType.Cylinder -- ось цилиндра — X, ставим стоя
		capWeld = weld(head, cap, CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2))
	else
		for _, side in { -1, 1 } do
			local eye = piece("DriverEye", Vector3.new(0.22, 0.12, 0.05), head.CFrame, EYES, Enum.Material.Neon)
			weld(head, eye, CFrame.new(side * 0.28, 0.1, -0.64)) -- смотрят вперёд, от камеры в салоне
		end
	end

	local lights: { Light } = {}
	for _, item in copy:GetDescendants() do
		if item:IsA("Light") then
			table.insert(lights, item)
		end
	end
	local function setLights(on: boolean)
		for _, light in lights do
			light.Enabled = on
		end
	end

	-- Экран: затемнение и надпись.
	local screen = Instance.new("ScreenGui")
	screen.Name = "Ending"
	screen.AutoLocalize = false
	screen.DisplayOrder = 20 -- выше всех экранов игры
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Parent = screen
	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.2) -- сверху: не закрывать водителя
	title.Size = UDim2.fromScale(0.9, 0.18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = if ending == "Good" then AMBER else BLOOD
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextTransparency = 1
	title.TextStrokeTransparency = 1
	local key = if ending == "Good" then "ending.good" else "ending.bad"
	title.Text = Strings.get(key .. ".title")
	title.ZIndex = 2
	title.Parent = screen
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 90
	titleLimit.Parent = title
	local subtitle = title:Clone()
	subtitle.Position = UDim2.fromScale(0.5, 0.32)
	subtitle.Size = UDim2.fromScale(0.8, 0.07)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextColor3 = Color3.fromRGB(235, 228, 214)
	subtitle.Text = Strings.get(key .. ".sub")
	subtitle.Parent = screen
	screen.Parent = playerGui

	-- Чужие экраны (итоги, лобби…) вынимаем, а не выключаем — владельцы сами меняют Enabled; потом возвращаем.
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
			controls:Disable()
		end
	end

	-- Свет и туман меняем только у себя и в конце возвращаем как было.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local savedLighting = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		FogColor = Lighting.FogColor,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local savedDensity = if atmosphere then atmosphere.Density else 0

	local tweens: { Tween } = {}
	local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
		local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut), goal)
		table.insert(tweens, t)
		t:Play()
	end
	local function showText()
		for _, label in { title, subtitle } do
			tween(label, 0.8, { TextTransparency = 0, TextStrokeTransparency = 0.4 })
		end
	end
	local follow: RBXScriptConnection? = nil
	-- Камера каждый кадр: смотрит с места на автобус или едет вместе с ним.
	local function track(frame: () -> CFrame)
		if follow then
			follow:Disconnect()
		end
		camera.CameraType = Enum.CameraType.Scriptable
		follow = RunService.RenderStepped:Connect(function()
			camera.CFrame = frame()
		end)
	end
	-- В Studio можно задержать кадр для скриншота: Workspace.StudioEndingHold = имя кадра.
	local function hold(seconds: number, shot: string)
		task.wait(seconds)
		while studio and Workspace:GetAttribute("StudioEndingHold") == shot do
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
		TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
		task.wait(0.4)
		if follow then
			follow:Disconnect()
		end
		title.Visible, subtitle.Visible = false, false
		copy:Destroy()
		for _, item in hidden do
			(item :: any).LocalTransparencyModifier = 0 -- после рейса прятать нечего
		end
		for key, value in savedLighting do
			(Lighting :: any)[key] = value
		end
		if atmosphere then
			atmosphere.Density = savedDensity
		end
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
		TweenService:Create(fade, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		task.wait(0.8)
		screen:Destroy()
		stopEnding = nil
		playing = false
	end
	stopEnding = finish

	local function good()
		-- 1. Рассвет: туман редеет, небо светлеет, свет в салоне ровный.
		local from, to = at(22, 9, -46), at(13, 6, -30)
		local started = os.clock()
		track(function()
			local alpha = math.min((os.clock() - started) / 5, 1)
			return CFrame.lookAt(from.Position:Lerp(to.Position, alpha), at(0, 5, -size.Z / 4).Position)
		end)
		tween(fade, 1.2, { BackgroundTransparency = 1 })
		setLights(true)
		tween(Lighting, 5, {
			ClockTime = 6.2,
			Brightness = 2.2,
			FogStart = 120,
			FogEnd = 900,
			FogColor = DAWN_FOG,
			Ambient = DAWN_AMBIENT,
			OutdoorAmbient = DAWN_OUTDOOR,
		})
		if atmosphere then
			tween(atmosphere, 5, { Density = 0.12 })
		end
		hold(5, "dawn")
		-- 2. Водитель снимает фуражку.
		local face = seatFrame * CFrame.new(0, 3.7, -6)
		track(function()
			return CFrame.lookAt(face.Position, (seatFrame * CFrame.new(0, 3.6, 0)).Position)
		end)
		task.wait(0.7)
		if capWeld then
			tween(capWeld, 1.2, { C0 = CFrame.new(1.1, 0.3, -0.5) * CFrame.Angles(0.4, 0, math.pi / 2 + 0.7) })
		end
		hold(2.2, "cap")
		-- 3. «Смена окончена».
		showText()
		hold(3, "title")
	end

	local function bad()
		-- 1. Маршрутка не останавливается — проезжает «Конечную» и уходит в туман; свет мигает.
		local spot = at(16, 5, -38)
		track(function()
			return CFrame.lookAt(spot.Position, root.Position + Vector3.new(0, 4, 0))
		end)
		tween(fade, 1, { BackgroundTransparency = 1 })
		tween(root, 3.5, { CFrame = root.CFrame * CFrame.new(0, 0, -70) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(1.6)
		for _ = 1, 2 do
			setLights(false)
			task.wait(0.15)
			setLights(true)
			task.wait(0.2)
		end
		hold(1.2, "pass")
		-- 2. В салоне: свет гаснет, силуэт водителя медленно поворачивает голову назад.
		local offset = rootStart:ToObjectSpace(seatFrame * CFrame.new(2.2, 4.3, 7))
		local target = rootStart:ToObjectSpace(seatFrame * CFrame.new(0, 3.7, 0))
		track(function()
			return CFrame.lookAt((root.CFrame * offset).Position, (root.CFrame * target).Position)
		end)
		tween(root, 8, { CFrame = root.CFrame * CFrame.new(0, 0, -60) }, Enum.EasingStyle.Linear)
		setLights(false)
		task.wait(0.8)
		tween(neck, 3, { C0 = neckRest * CFrame.Angles(0, math.pi, 0) })
		hold(3.4, "dark")
		-- 3. «Маршрут 13 не заканчивается».
		showText()
		hold(3, "title")
	end

	thread = task.spawn(function()
		local ok, err = pcall((if ending == "Good" then good else bad) :: any)
		if not ok then
			warn(`[Ending] катсцена прервалась: {err}`)
		end
		finish()
	end)
end

function EndingController:Init(_controllers: { [string]: any })
	Remotes.Event("RunEnded").OnClientEvent:Connect(function(summary: unknown)
		local ending = if type(summary) == "table" then (summary :: any).Ending else nil
		if ending == "Good" or ending == "Bad" then
			task.spawn(play, ending)
		end
	end)
	-- Новый рейс уже начался (дольше экрана итогов и отсчёта катсцена не идёт, но на всякий случай) — обрываем.
	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		if state == "Running" and stopEnding then
			task.spawn(stopEnding)
		end
	end)
end

function EndingController:Start()
	if RunService:IsStudio() then
		-- Studio: Workspace.StudioEndingPreview = "Good" | "Bad" — показать концовку (снова — сменить на "" и обратно).
		Workspace:GetAttributeChangedSignal("StudioEndingPreview"):Connect(function()
			local ending = Workspace:GetAttribute("StudioEndingPreview")
			if ending == "Good" or ending == "Bad" then
				play(ending)
			end
		end)
	end
end

return EndingController
