--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ResultsController = {}

local PANEL = Color3.fromRGB(21, 28, 39)
local TILE = Color3.fromRGB(32, 43, 58)
local TEXT = Color3.fromRGB(250, 244, 231)
local MUTED = Color3.fromRGB(196, 208, 223)
local AMBER = Color3.fromRGB(246, 198, 110)
local GOOD = Color3.fromRGB(147, 223, 177)
local BAD = Color3.fromRGB(255, 156, 149)
local TOAST_DURATION = 3

local TOAST_COLORS: { [string]: Color3 } = {
	Info = Color3.fromRGB(35, 65, 96),
	Warn = Color3.fromRGB(103, 72, 29),
	Good = Color3.fromRGB(28, 83, 60),
	Bad = Color3.fromRGB(118, 44, 50),
}

type Summary = { Won: boolean, Tenge: number, Caught: number, Mistakes: number, StopsReached: number }

local function roundCorners(gui: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = gui
end

local function constrain(gui: GuiObject, minSize: Vector2, maxSize: Vector2)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = minSize
	limit.MaxSize = maxSize
	limit.Parent = gui
end

local function styleText(gui: TextLabel | TextButton, maxSize: number)
	gui.TextColor3 = TEXT
	gui.Font = Enum.Font.GothamBold
	gui.TextScaled = true
	gui.TextTruncate = Enum.TextTruncate.AtEnd
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 15
	limit.MaxTextSize = maxSize
	limit.Parent = gui
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2, maxSize: number): TextLabel
	local gui = Instance.new("TextLabel")
	gui.Name = name
	gui.Position = position
	gui.Size = size
	gui.BackgroundTransparency = 1
	styleText(gui, maxSize)
	gui.Parent = parent
	return gui
end

local function button(parent: Instance, name: string, caption: string, position: UDim2, size: UDim2): TextButton
	local gui = Instance.new("TextButton")
	gui.Name = name
	gui.Text = caption
	gui.Position = position
	gui.Size = size
	gui.BorderSizePixel = 0
	gui.BackgroundColor3 = AMBER
	styleText(gui, 21)
	gui.TextColor3 = PANEL
	roundCorners(gui)
	gui.Parent = parent
	return gui
end

local function metric(parent: Frame, name: string, caption: string, x: number, y: number): TextLabel
	local tile = Instance.new("Frame")
	tile.Position = UDim2.fromScale(x, y)
	tile.Size = UDim2.fromScale(0.43, 0.20)
	tile.BackgroundColor3 = TILE
	tile.BorderSizePixel = 0
	roundCorners(tile)
	tile.Parent = parent
	local title = label(tile, "Label", UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.34), 17)
	title.Text = caption
	title.TextColor3 = MUTED
	return label(tile, name, UDim2.fromScale(0.04, 0.44), UDim2.fromScale(0.92, 0.48), 25)
end

local function screenGui(parent: Instance, name: string, order: number): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.DisplayOrder = order
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ResetOnSpawn = false
	screen.Parent = parent
	return screen
end

function ResultsController:Init(_controllers: { [string]: any }) end

function ResultsController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local results = screenGui(playerGui, "TripResults", 5)
	results.Enabled = false

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new()
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.Parent = results

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.92)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	roundCorners(panel)
	constrain(panel, Vector2.zero, Vector2.new(490, 378))
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.3
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = panel
	panel.Parent = backdrop

	local title = label(panel, "Outcome", UDim2.fromScale(0.06, 0.07), UDim2.fromScale(0.88, 0.15), 33)
	local earnings = metric(panel, "TripEarnings", "За рейс", 0.06, 0.26)
	local caught = metric(panel, "Caught", "Аномалии", 0.51, 0.26)
	local mistakes = metric(panel, "Mistakes", "Ошибки", 0.06, 0.48)
	local stops = metric(panel, "StopsReached", "Остановки", 0.51, 0.48)
	local depot = button(panel, "ReturnToDepot", "В депо", UDim2.fromScale(0.06, 0.94), UDim2.fromScale(0.88, 0.20))
	depot.AnchorPoint = Vector2.new(0, 1)
	constrain(depot, Vector2.new(0, 48), Vector2.new(math.huge, math.huge))

	local toastGui = screenGui(playerGui, "NotifyToast", 9)
	local toast = Instance.new("Frame")
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.fromScale(0.5, 0.96)
	toast.Size = UDim2.fromScale(0.88, 0.13)
	toast.BorderSizePixel = 0
	toast.Visible = false
	roundCorners(toast)
	constrain(toast, Vector2.new(0, 48), Vector2.new(490, 72))
	toast.Parent = toastGui
	local message = label(toast, "Message", UDim2.fromScale(0.05, 0.06), UDim2.fromScale(0.9, 0.88), 20)

	local toastNumber = 0
	local roundState: string? = nil

	local function notify(text: string, kind: string)
		if type(text) ~= "string" or text == "" then
			return
		end
		toastNumber += 1
		local currentNumber = toastNumber
		toast.BackgroundColor3 = TOAST_COLORS[kind] or TOAST_COLORS.Info
		message.Text = text
		toast.Visible = true
		task.delay(TOAST_DURATION, function()
			if currentNumber == toastNumber then
				toast.Visible = false
			end
		end)
	end

	local function applyRoundState(state: string)
		if state ~= "Results" and state ~= roundState then
			results.Enabled = false
		end
		roundState = state
	end

	local function showResults(summary: Summary)
		if roundState == "Lobby" or roundState == "Countdown" then
			return
		end
		title.Text = if summary.Won then "Победа" else "Поражение"
		title.TextColor3 = if summary.Won then GOOD else BAD
		local prefix = if summary.Tenge > 0 then "+" else ""
		earnings.Text = `{prefix}{summary.Tenge} ₸`
		caught.Text = tostring(summary.Caught)
		mistakes.Text = tostring(summary.Mistakes)
		stops.Text = `{summary.StopsReached}/{#Config.STOP_NAMES}`
		results.Enabled = true
	end

	-- Переход в депо и телепорт выполняет RoundService.
	depot.Activated:Connect(function()
		results.Enabled = false
	end)

	if RunService:IsStudio() and Workspace:GetAttribute("StudioResultsPreview") == true then
		local preview = screenGui(playerGui, "StudioResultsPreview", 4)
		local tools = Instance.new("Frame")
		tools.AnchorPoint = Vector2.new(0.5, 1)
		tools.Position = UDim2.fromScale(0.5, 0.79)
		tools.Size = UDim2.fromScale(0.93, 0.16)
		tools.BackgroundTransparency = 1
		constrain(tools, Vector2.new(0, 48), Vector2.new(450, 60))
		tools.Parent = preview
		local example = button(tools, "ShowResults", "Пример итогов", UDim2.fromScale(0, 0), UDim2.fromScale(0.48, 1))
		local exampleToast = button(tools, "ShowToast", "Пример тоста", UDim2.fromScale(0.52, 0), UDim2.fromScale(0.48, 1))
		local won = true
		example.Activated:Connect(function()
			showResults({
				Won = won,
				Tenge = if won then Config.FINISH_BONUS else -Config.WRONG_EJECT_PENALTY,
				Caught = if won then 2 else 0,
				Mistakes = if won then 0 else 1,
				StopsReached = if won then #Config.STOP_NAMES else 3,
			})
			won = not won
		end)
		local kinds = { "Info", "Warn", "Good", "Bad" }
		local examples = { "Следующая остановка", "Двери ещё открыты", "Аномалия высажена", "Пассажир был человеком" }
		local index = 1
		exampleToast.Activated:Connect(function()
			notify(examples[index], kinds[index])
			index = index % #kinds + 1
		end)
		return
	end

	Remotes.Event("RunEnded").OnClientEvent:Connect(showResults)
	Remotes.Event("RoundState").OnClientEvent:Connect(applyRoundState)
	Remotes.Event("Notify").OnClientEvent:Connect(notify)
end

return ResultsController
