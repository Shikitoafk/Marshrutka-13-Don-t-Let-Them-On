--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))
local Flashlight = require(script.Flashlight)
local Mirror = require(script.Mirror)
local StudioPreview = require(script.StudioPreview)

local ConductorController = {}

local PANEL = Color3.fromRGB(21, 28, 39)
local BUTTON = Color3.fromRGB(52, 66, 84)
local TEXT = Color3.fromRGB(250, 244, 231)
local AMBER = Color3.fromRGB(246, 198, 110)
local PAPER = Color3.fromRGB(240, 221, 175)
local CABIN_REFRESH = 0.1 -- Частота обновления модели салона и подсказок фонаря.

type Target = { model: Model, part: BasePart, id: string, ticket: ProximityPrompt, eject: ProximityPrompt }
type Tool = "Ticket" | "Flashlight"
type TicketData = { Route: string, Date: string }

local function constrain(gui: GuiObject, minSize: Vector2, maxSize: Vector2)
	local size = Instance.new("UISizeConstraint")
	size.MinSize = minSize
	size.MaxSize = maxSize
	size.Parent = gui
end

local function corners(gui: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = gui
end

local function limitText(gui: GuiObject, maxSize: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 15
	limit.MaxTextSize = maxSize
	limit.Parent = gui
end

local function button(parent: Instance, name: string, caption: string, position: UDim2, size: UDim2): TextButton
	local gui = Instance.new("TextButton")
	gui.Name = name
	gui.Text = caption
	gui.Position = position
	gui.Size = size
	gui.BorderSizePixel = 0
	gui.BackgroundColor3 = BUTTON
	gui.Font = Enum.Font.GothamBold
	gui.TextColor3 = TEXT
	gui.TextScaled = true
	limitText(gui, 21)
	corners(gui)
	gui.Parent = parent
	return gui
end

local function label(parent: Instance, caption: string, position: UDim2, size: UDim2): TextLabel
	local gui = Instance.new("TextLabel")
	gui.Text = caption
	gui.Position = position
	gui.Size = size
	gui.BackgroundTransparency = 1
	gui.Font = Enum.Font.GothamBold
	gui.TextColor3 = TEXT
	gui.TextScaled = true
	limitText(gui, 23)
	gui.Parent = parent
	return gui
end

local function overlay(screen: ScreenGui, name: string, depth: number, ratio: number, maxSize: Vector2): (Frame, Frame)
	local shade = Instance.new("Frame")
	shade.Name = name
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new()
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.Active = true
	shade.Visible = false
	shade.ZIndex = depth
	shade.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.9)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	constrain(panel, Vector2.zero, maxSize)
	corners(panel)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ratio
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = panel
	panel.Parent = shade
	return shade, panel
end

local function makePrompt(parent: BasePart, caption: string, key: Enum.KeyCode, gamepadKey: Enum.KeyCode, y: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.AutoLocalize = false
	prompt.ActionText = caption
	prompt.ObjectText = Strings.get("conductor.passenger")
	prompt.MaxActivationDistance = Config.INSPECT_RANGE
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = gamepadKey
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.UIOffset = Vector2.new(0, y)
	prompt.ClickablePrompt = true
	prompt.Enabled = false
	prompt.Parent = parent
	return prompt
end

local function getBus(): Model?
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	return if bus and bus:IsA("Model") then bus else nil
end

local function getRoot(model: Model?): BasePart?
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else model.PrimaryPart
end

function ConductorController:Init(_controllers: { [string]: any }) end

function ConductorController:Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.AutoLocalize = false
	screen.Name = "ConductorTools"
	screen.DisplayOrder = 3
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.ResetOnSpawn = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.Enabled = false
	screen.Parent = playerGui

	local toolbar = Instance.new("Frame")
	toolbar.AnchorPoint = Vector2.new(1, 1)
	toolbar.Position = UDim2.fromScale(0.97, 0.76)
	toolbar.Size = UDim2.fromScale(0.50, 0.16)
	toolbar.BackgroundTransparency = 1
	constrain(toolbar, Vector2.new(236, 52), Vector2.new(365, 74))
	toolbar.Parent = screen
	local mirrorButton = button(toolbar, "OpenMirror", Strings.get("conductor.mirror"), UDim2.fromScale(0, 0), UDim2.fromScale(0.43, 1))
	local lightButton = button(toolbar, "Flashlight", "", UDim2.fromScale(0.46, 0), UDim2.fromScale(0.54, 1))

	local mirrorShade, mirrorPanel = overlay(screen, "CabinMirror", 2, 1.65, Vector2.new(610, 370))
	label(mirrorPanel, Strings.get("conductor.rearview"), UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.13))
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Cabin"
	viewport.Position = UDim2.fromScale(0.045, 0.18)
	viewport.Size = UDim2.fromScale(0.91, 0.52)
	viewport.BackgroundColor3 = Color3.fromRGB(9, 15, 24)
	viewport.Ambient = Color3.fromRGB(163, 165, 165)
	viewport.BorderSizePixel = 0
	corners(viewport)
	viewport.Parent = mirrorPanel
	local missingCabin = label(mirrorPanel, Strings.get("conductor.cabin_unavailable"), viewport.Position, viewport.Size)
	missingCabin.ZIndex = 2
	local mirrorClose = button(mirrorPanel, "CloseMirror", Strings.get("ui.close"), UDim2.fromScale(0.045, 0.96), UDim2.fromScale(0.91, 0.23))
	mirrorClose.AnchorPoint = Vector2.new(0, 1)
	constrain(mirrorClose, Vector2.new(0, 48), Vector2.new(math.huge, math.huge))

	local dialog, dialogPanel = overlay(screen, "PassengerDialog", 3, 1.4, Vector2.new(425, 302))
	local dialogTitle = label(dialogPanel, "", UDim2.fromScale(0.06, 0.075), UDim2.fromScale(0.88, 0.22))
	local dialogBody = label(dialogPanel, "", UDim2.fromScale(0.06, 0.31), UDim2.fromScale(0.88, 0.33))
	local dialogClose = button(dialogPanel, "CloseDialog", Strings.get("ui.close"), UDim2.fromScale(0.055, 0.94), UDim2.fromScale(0.89, 0.23))
	local confirm = button(dialogPanel, "ConfirmEject", Strings.get("conductor.eject"), UDim2.fromScale(0.52, 0.94), UDim2.fromScale(0.425, 0.23))
	confirm.BackgroundColor3 = Color3.fromRGB(116, 49, 47)
	for _, control in { dialogClose, confirm } do
		control.AnchorPoint = Vector2.new(0, 1)
		constrain(control, Vector2.new(0, 48), Vector2.new(math.huge, math.huge))
	end

	local mirror = Mirror.new(viewport)
	local flashlight = Flashlight.new()
	local previewMode = RunService:IsStudio() and Workspace:GetAttribute("StudioHudLobbyPreview") == true
	local previewBus: Model? = nil
	local roundState = "Lobby"
	local role: string? = nil
	local battery = Config.FLASHLIGHT_BATTERY
	local lightOn = false
	local tickConnection: RBXScriptConnection? = nil
	local targets: { [Model]: Target } = {}
	local seenByFlashlight: { [Model]: boolean } = {}
	local nextInspectAt = 0
	local queuedTicket: Target? = nil
	local pendingTicket: Target? = nil
	local selectedEject: Target? = nil
	local requestInspect: (string, Tool) -> ()
	local requestEject: (string) -> ()

	local function currentBus(): Model?
		if not previewMode then
			return getBus()
		end
		local root = getRoot(player.Character)
		if not previewBus and screen.Enabled and root then
			previewBus = StudioPreview.create(root.CFrame)
		end
		return previewBus
	end

	local function isCurrent(target: Target): boolean
		local bus = currentBus()
		local folder = if bus then bus:FindFirstChild("Passengers") else nil
		return screen.Enabled and folder ~= nil
			and target.model.Parent == folder
			and target.part:IsDescendantOf(target.model)
			and target.model:GetAttribute("PassengerId") == target.id
	end

	local function canReach(target: Target): boolean
		local root = getRoot(player.Character)
		return isCurrent(target) and root ~= nil and (target.part.Position - root.Position).Magnitude <= Config.INSPECT_RANGE
	end

	local function updatePromptVisibility()
		local visible = screen.Enabled and not mirrorShade.Visible and not dialog.Visible
		for _, target in targets do
			target.ticket.Enabled = visible
			target.eject.Enabled = visible
		end
	end

	local function updateLightButton()
		local text = Strings.get("conductor.flashlight", { seconds = math.ceil(battery) })
		if lightButton.Text ~= text then
			lightButton.Text = text
		end
	end

	local function setLight(enabled: boolean)
		lightOn = enabled and battery > 0
		flashlight.setEnabled(lightOn)
		table.clear(seenByFlashlight)
		lightButton.BackgroundColor3 = if lightOn then AMBER else BUTTON
		lightButton.TextColor3 = if lightOn then PANEL else TEXT
		updateLightButton()
	end

	local function setMirror(open: boolean)
		mirrorShade.Visible = open
		if open then
			missingCabin.Visible = not mirror.update(currentBus())
		else
			mirror.clear()
		end
		updatePromptVisibility()
	end

	local function closeDialog()
		selectedEject = nil
		dialog.Visible = false
		updatePromptVisibility()
	end

	local function showTicket(id: string, tool: string, data: TicketData)
		local target = pendingTicket
		if tool ~= "Ticket" or not target or target.id ~= id or not isCurrent(target) or dialog.Visible or mirrorShade.Visible then
			return
		end
		if type(data) ~= "table" or type(data.Route) ~= "string" or type(data.Date) ~= "string" then
			return
		end
		pendingTicket = nil
		dialogPanel.BackgroundColor3 = PAPER
		dialogTitle.TextColor3 = PANEL
		dialogTitle.Text = Strings.get("conductor.ticket")
		dialogBody.TextColor3 = PANEL
		dialogBody.Text = Strings.get("conductor.ticket_details", { route = data.Route, date = data.Date })
		dialogClose.Text = Strings.get("ui.close")
		dialogClose.Size = UDim2.fromScale(0.89, 0.23)
		confirm.Visible = false
		dialog.Visible = true
		updatePromptVisibility()
	end

	local function showEject(target: Target)
		queuedTicket = nil
		pendingTicket = nil
		selectedEject = target
		dialogPanel.BackgroundColor3 = PANEL
		dialogTitle.TextColor3 = TEXT
		dialogTitle.Text = Strings.get("conductor.eject_title")
		dialogBody.TextColor3 = TEXT
		dialogBody.Text = Strings.get("conductor.eject_confirm")
		dialogClose.Text = Strings.get("ui.cancel")
		dialogClose.Size = UDim2.fromScale(0.425, 0.23)
		confirm.Visible = true
		dialog.Visible = true
		updatePromptVisibility()
	end

	local function sendQueuedTicket(now: number)
		local target = queuedTicket
		if not target then
			return
		end
		if not canReach(target) then
			queuedTicket = nil
		elseif now >= nextInspectAt then
			queuedTicket = nil
			pendingTicket = target
			nextInspectAt = now + Config.INSPECT_COOLDOWN
			requestInspect(target.id, "Ticket")
		end
	end

	local function removeTarget(target: Target)
		target.ticket:Destroy()
		target.eject:Destroy()
		targets[target.model] = nil
		seenByFlashlight[target.model] = nil
		if target == selectedEject then
			closeDialog()
		end
		if target == queuedTicket then
			queuedTicket = nil
		end
		if target == pendingTicket then
			pendingTicket = nil
		end
	end

	local function refreshTargets(bus: Model?): { Model }
		local folder = if bus then bus:FindFirstChild("Passengers") else nil
		for model, target in targets do
			if not folder or model.Parent ~= folder or not target.part:IsDescendantOf(model) or model:GetAttribute("PassengerId") ~= target.id then
				removeTarget(target)
			end
		end

		local models: { Model } = {}
		if not folder then
			return models
		end
		for _, model in folder:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local id = model:GetAttribute("PassengerId")
			local part = getRoot(model) or model:FindFirstChildWhichIsA("BasePart", true)
			if type(id) ~= "string" or id == "" or not part then
				continue
			end
			table.insert(models, model)
			if not targets[model] then
				local ticketPrompt = makePrompt(part, Strings.get("conductor.inspect"), Enum.KeyCode.E, Enum.KeyCode.ButtonX, -37)
				local ejectPrompt = makePrompt(part, Strings.get("conductor.eject"), Enum.KeyCode.R, Enum.KeyCode.ButtonY, 37)
				local target = { model = model, id = id, part = part, ticket = ticketPrompt, eject = ejectPrompt }
				targets[model] = target
				ticketPrompt.Triggered:Connect(function(triggeringPlayer)
					if triggeringPlayer == player and ticketPrompt.Enabled and canReach(target) then
						pendingTicket = nil
						queuedTicket = target
						sendQueuedTicket(os.clock())
					end
				end)
				ejectPrompt.Triggered:Connect(function(triggeringPlayer)
					if triggeringPlayer == player and ejectPrompt.Enabled and canReach(target) then
						showEject(target)
					end
				end)
			end
		end
		updatePromptVisibility()
		return models
	end

	local function refreshCabin()
		local bus = currentBus()
		local models = refreshTargets(bus)
		if mirrorShade.Visible then
			missingCabin.Visible = not mirror.update(bus)
		end

		local now = os.clock()
		sendQueuedTicket(now)
		if lightOn then
			for _, model in flashlight.update(models, player.Character) do
				local target = targets[model]
				if not seenByFlashlight[model] and now >= nextInspectAt and canReach(target) then
					seenByFlashlight[model] = true
					nextInspectAt = now + Config.INSPECT_COOLDOWN
					requestInspect(target.id, "Flashlight")
					break
				end
			end
		end
	end

	local function updateTools()
		local enabled = role == "Conductor" and roundState == "Running"
		if screen.Enabled == enabled then
			return
		end
		screen.Enabled = enabled
		if enabled then
			refreshCabin()
			local elapsed = 0
			tickConnection = RunService.Heartbeat:Connect(function(dt)
				if lightOn then
					battery = math.max(0, battery - dt)
					if battery == 0 then
						setLight(false)
					else
						updateLightButton()
					end
				end
				elapsed += dt
				if elapsed >= CABIN_REFRESH then
					elapsed %= CABIN_REFRESH
					refreshCabin()
				end
			end)
		else
			if tickConnection then
				tickConnection:Disconnect()
				tickConnection = nil
			end
			queuedTicket = nil
			pendingTicket = nil
			closeDialog()
			setMirror(false)
			setLight(false)
			for _, target in targets do
				removeTarget(target)
			end
			if previewBus then
				previewBus:Destroy()
				previewBus = nil
			end
		end
	end

	local function applyRoundState(state: string)
		if state ~= roundState and (state == "Lobby" or state == "Results") then
			role = nil
			battery = Config.FLASHLIGHT_BATTERY
			nextInspectAt = 0
			updateLightButton()
		end
		roundState = state
		updateTools()
	end

	mirrorButton.Activated:Connect(function()
		if screen.Enabled and not dialog.Visible then
			queuedTicket = nil
			pendingTicket = nil
			setMirror(true)
		end
	end)
	mirrorClose.Activated:Connect(function()
		setMirror(false)
	end)
	lightButton.Activated:Connect(function()
		if screen.Enabled and not dialog.Visible and not mirrorShade.Visible then
			setLight(not lightOn)
		end
	end)
	dialogClose.Activated:Connect(closeDialog)
	confirm.Activated:Connect(function()
		local target = selectedEject
		closeDialog()
		if target and canReach(target) then
			requestEject(target.id)
		end
	end)
	player.CharacterRemoving:Connect(function()
		queuedTicket = nil
		pendingTicket = nil
		closeDialog()
		setMirror(false)
		setLight(false)
	end)
	updateLightButton()

	if previewMode then
		requestInspect = function(id, tool)
			if tool == "Ticket" then
				showTicket(id, tool, StudioPreview.ticket(id))
			end
		end
		requestEject = function(id)
			local bus = currentBus()
			local folder = if bus then bus:FindFirstChild("Passengers") else nil
			local model = if folder then folder:FindFirstChild(id) else nil
			if model then
				model:Destroy()
			end
		end
		local previewEvent = playerGui:WaitForChild("StudioRoundPreview") :: BindableEvent
		previewEvent.Event:Connect(function(state: string)
			if state == "Running" then
				role = "Conductor"
			end
			applyRoundState(state)
		end)
		return
	end

	local inspectRemote = Remotes.Event("InspectPassenger")
	local ejectRemote = Remotes.Event("EjectPassenger")
	requestInspect = function(id, tool)
		inspectRemote:FireServer(id, tool)
	end
	requestEject = function(id)
		ejectRemote:FireServer(id)
	end
	Remotes.Event("InspectResult").OnClientEvent:Connect(showTicket)
	Remotes.Event("RoleAssigned").OnClientEvent:Connect(function(assignedRole: string)
		role = assignedRole
		updateTools()
	end)
	Remotes.Event("RoundState").OnClientEvent:Connect(applyRoundState)
end

return ConductorController
