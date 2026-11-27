--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnomalyTypes = require(Shared:WaitForChild("AnomalyTypes"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local HudController = {}

local PANEL_COLOR = Color3.fromRGB(21, 28, 39)
local TEXT_COLOR = Color3.fromRGB(250, 244, 231)
local MUTED_COLOR = Color3.fromRGB(193, 207, 225)
local AMBER_COLOR = Color3.fromRGB(246, 198, 110)
local STOP_COUNT = #Config.STOP_NAMES

local function localizeStopSign(instance: Instance)
	if not instance:IsA("TextLabel") then
		return
	end
	local sign = instance.Parent
	if not sign or not sign:IsA("BillboardGui") then
		return
	end
	local spawn = sign.Parent
	local zone = if spawn and spawn.Name == "Spawn" then spawn.Parent else nil
	local map = Workspace:FindFirstChild("Map")
	local stops = if map then map:FindFirstChild("Stops") else nil
	if not zone or not stops or zone.Parent ~= stops then
		return
	end
	local index = zone:GetAttribute("StopIndex")
	if type(index) ~= "number" then
		return
	end
	local name = zone:GetAttribute("StopName")
	instance.AutoLocalize = false
	instance.Text = Strings.get("stop.sign", {
		index = index,
		name = Strings.stopName(index, if type(name) == "string" then name else nil),
	})
end

local function roundCorners(gui: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = gui
end

local function makeLabel(parent: Instance, name: string, position: UDim2, size: UDim2, maxTextSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextScaled = true

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 15
	limit.MaxTextSize = maxTextSize
	limit.Parent = label
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Text = text
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Color3.fromRGB(52, 66, 84)
	button.TextColor3 = TEXT_COLOR
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 16
	limit.MaxTextSize = 19
	limit.Parent = button
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(0, 48)
	sizeLimit.Parent = button
	roundCorners(button, 9)
	button.Parent = parent
	return button
end

local function makeGuide(screen: ScreenGui): Frame
	local backdrop = Instance.new("Frame")
	backdrop.Name = "ConductorGuide"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new()
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.Visible = false
	backdrop.ZIndex = 2
	backdrop.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.93, 0.92)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	roundCorners(panel, 14)
	panel.Parent = backdrop

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.26
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = panel
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(570, 450)
	sizeLimit.Parent = panel

	local title = makeLabel(panel, "Title", UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.18), 24)
	title.Text = Strings.get("hud.guide")
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = AMBER_COLOR

	local list = Instance.new("ScrollingFrame")
	list.Name = "AnomalyHints"
	list.Position = UDim2.fromScale(0.05, 0.23)
	list.Size = UDim2.fromScale(0.9, 0.5)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = MUTED_COLOR
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = list

	for index, anomaly in AnomalyTypes do
		local hint = Instance.new("TextLabel")
		hint.Name = anomaly.Id
		hint.LayoutOrder = index
		hint.Size = UDim2.fromScale(0.95, 0)
		hint.AutomaticSize = Enum.AutomaticSize.Y
		hint.BackgroundTransparency = 1
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextWrapped = true
		hint.TextSize = 17
		hint.Font = Enum.Font.GothamMedium
		hint.TextColor3 = TEXT_COLOR
		hint.RichText = true
		local name = Strings.get(`anomaly.{anomaly.Id}.name`)
		local description = Strings.get(`anomaly.{anomaly.Id}.hint`)
		hint.Text = `<b>{name}</b>\n{description}`
		hint.Parent = list
	end

	local close = makeButton(panel, Strings.get("ui.close"))
	close.Name = "CloseGuide"
	close.AnchorPoint = Vector2.new(0, 1)
	close.Position = UDim2.fromScale(0.05, 0.96)
	close.Size = UDim2.fromScale(0.9, 0.19)
	close.Activated:Connect(function()
		backdrop.Visible = false
	end)
	return backdrop
end

function HudController:Init(_controllers: { [string]: any }) end

function HudController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "TripHud"
	screen.AutoLocalize = false
	screen.DisplayOrder = 2
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.035)
	panel.Size = UDim2.fromScale(0.94, 0.09)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	roundCorners(panel, 12)
	panel.Parent = screen

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(0, 44)
	sizeLimit.MaxSize = Vector2.new(620, 50)
	sizeLimit.Parent = panel

	local stop = makeLabel(panel, "Stop", UDim2.fromScale(0.035, 0.04), UDim2.fromScale(0.47, 0.92), 17)
	stop.Font = Enum.Font.GothamBold
	stop.TextTruncate = Enum.TextTruncate.None
	stop.TextWrapped = true
	local currency = makeLabel(panel, "Currency", UDim2.fromScale(0.72, 0), UDim2.fromScale(0.24, 1), 17)
	currency.TextColor3 = AMBER_COLOR
	currency.TextXAlignment = Enum.TextXAlignment.Right
	currency.Text = "— ₸"

	local health = makeLabel(panel, "Health", UDim2.fromScale(0.52, 0.1), UDim2.fromScale(0.19, 0.65), 17)
	health.TextColor3 = MUTED_COLOR
	health.TextXAlignment = Enum.TextXAlignment.Center
	local track = Instance.new("Frame")
	track.Position = UDim2.fromScale(0.53, 0.79)
	track.Size = UDim2.fromScale(0.17, 0.085)
	track.BackgroundColor3 = Color3.fromRGB(54, 69, 87)
	track.BorderSizePixel = 0
	roundCorners(track, 5)
	track.Parent = panel

	local fill = Instance.new("Frame")
	fill.Name = "HealthFill"
	fill.BackgroundColor3 = AMBER_COLOR
	fill.BorderSizePixel = 0
	roundCorners(fill, 5)
	fill.Parent = track

	local guideButton = makeButton(panel, "?")
	guideButton.Name = "OpenGuide"
	guideButton.AnchorPoint = Vector2.new(1, 0)
	guideButton.Position = UDim2.fromScale(1, 1.12)
	guideButton.Size = UDim2.fromScale(0.14, 1)
	local guideSize = guideButton:FindFirstChildOfClass("UISizeConstraint")
	if guideSize then
		guideSize.MinSize = Vector2.new(48, 48)
		guideSize.MaxSize = Vector2.new(48, 48)
	end
	guideButton.Visible = false
	local guide = makeGuide(screen)
	guideButton.Activated:Connect(function()
		if screen.Enabled and guideButton.Visible then
			guide.Visible = true
		end
	end)

	local roundState = "Lobby"
	local function applyRole(assignedRole: string?)
		guideButton.Visible = assignedRole == "Conductor"
		if not guideButton.Visible then
			guide.Visible = false
		end
	end

	local function applyStop(index: number, name: string)
		stop.Text = `{index}/{STOP_COUNT} · {Strings.stopName(index, name)}`
	end

	local function applyHealth(value: number)
		local clampedHealth = math.clamp(value, 0, Config.BUS_MAX_HEALTH)
		health.Text = `{math.round(clampedHealth)}/{Config.BUS_MAX_HEALTH}`
		fill.Size = UDim2.fromScale(clampedHealth / Config.BUS_MAX_HEALTH, 1)
		fill.Visible = clampedHealth > 0
	end

	local function applyCurrency(tenge: number)
		currency.Text = `{tenge} ₸`
	end

	local function resetTrip()
		stop.Text = `—/{STOP_COUNT}`
		health.Text = "—"
		fill.Visible = false
		applyRole(nil)
	end

	local function applyRoundState(state: string)
		if state ~= roundState and (state == "Lobby" or state == "Results") then
			resetTrip()
		end
		roundState = state
		screen.Enabled = state == "Running"
		if not screen.Enabled then
			guide.Visible = false
		end
	end

	resetTrip()

	Workspace.DescendantAdded:Connect(localizeStopSign)
	local map = Workspace:FindFirstChild("Map")
	local stops = if map then map:FindFirstChild("Stops") else nil
	if stops then
		for _, descendant in stops:GetDescendants() do
			localizeStopSign(descendant)
		end
	end

	if RunService:IsStudio() and Workspace:GetAttribute("StudioHudLobbyPreview") == true then
		local preview = playerGui:WaitForChild("StudioRoundPreview") :: BindableEvent
		preview.Event:Connect(function(state: string)
			applyRoundState(state)
			if state == "Running" then
				applyRole("Conductor")
				applyStop(1, Config.STOP_NAMES[1])
				applyHealth(Config.BUS_MAX_HEALTH)
				applyCurrency(0)
				task.delay(Config.STOP_DOOR_TIME, function()
					if roundState == "Running" then
						applyStop(2, Config.STOP_NAMES[2])
						applyHealth(Config.BUS_MAX_HEALTH - Config.ANOMALY_DAMAGE)
						applyCurrency(Config.FARE_PER_PASSENGER)
					end
				end)
			end
		end)
		return
	end

	Remotes.Event("RoundState").OnClientEvent:Connect(applyRoundState)
	Remotes.Event("RoleAssigned").OnClientEvent:Connect(applyRole)
	Remotes.Event("StopChanged").OnClientEvent:Connect(applyStop)
	Remotes.Event("BusState").OnClientEvent:Connect(function(_speed: number, busHealth: number)
		applyHealth(busHealth)
	end)
	Remotes.Event("CurrencyChanged").OnClientEvent:Connect(applyCurrency)
end

return HudController
