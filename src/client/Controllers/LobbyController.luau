--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local LobbyController = {}

local PANEL_COLOR = Color3.fromRGB(21, 28, 39)
local ROW_COLOR = Color3.fromRGB(32, 43, 58)
local TEXT_COLOR = Color3.fromRGB(250, 244, 231)
local MUTED_COLOR = Color3.fromRGB(193, 207, 225)
local AMBER_COLOR = Color3.fromRGB(246, 198, 110)
local READY_COLOR = Color3.fromRGB(147, 223, 177)
local TUTORIAL_CARDS = { "tutorial.roles", "tutorial.tools", "tutorial.eject" }

type ReadyByUserId = { [string]: boolean }
type LobbyData = {
	Ready: ReadyByUserId?,
	CountdownEndsAt: number?,
}

local function roundCorners(gui: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = gui
end

local function limitText(gui: GuiObject, maxTextSize: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 15
	limit.MaxTextSize = maxTextSize
	limit.Parent = gui
end

local function styleText(gui: TextLabel, maxTextSize: number)
	gui.BackgroundTransparency = 1
	gui.TextColor3 = TEXT_COLOR
	gui.Font = Enum.Font.GothamMedium
	gui.TextScaled = true
	gui.TextTruncate = Enum.TextTruncate.AtEnd

	limitText(gui, maxTextSize)
end

local function makePanel(screen: ScreenGui): Frame
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.92)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Active = true
	roundCorners(panel, 14)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.15
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = panel
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(500, 435)
	sizeLimit.Parent = panel
	panel.Parent = screen
	return panel
end

local function makeButton(panel: Frame, name: string, x: number, width: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.fromScale(x, 0.94)
	button.Size = UDim2.fromScale(width, 0.18)
	button.BackgroundColor3 = ROW_COLOR
	button.TextColor3 = TEXT_COLOR
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextWrapped = true
	button.BorderSizePixel = 0
	limitText(button, 23)
	roundCorners(button, 10)
	local buttonSize = Instance.new("UISizeConstraint")
	buttonSize.MinSize = Vector2.new(0, 48)
	buttonSize.Parent = button
	button.Parent = panel
	return button
end

local function makeTutorial(screen: ScreenGui, lobby: Frame): (() -> (), () -> ())
	local panel = makePanel(screen)
	panel.Name = "Tutorial"
	panel.Visible = false

	local progress = Instance.new("TextLabel")
	progress.Name = "CardProgress"
	progress.Position = UDim2.fromScale(0.06, 0.08)
	progress.Size = UDim2.fromScale(0.88, 0.12)
	styleText(progress, 19)
	progress.TextColor3 = AMBER_COLOR
	progress.Parent = panel

	local body = Instance.new("TextLabel")
	body.Name = "CardText"
	body.Position = UDim2.fromScale(0.09, 0.23)
	body.Size = UDim2.fromScale(0.82, 0.44)
	styleText(body, 34)
	body.Font = Enum.Font.GothamBold
	body.TextTruncate = Enum.TextTruncate.None
	body.TextWrapped = true
	body.Parent = panel

	local close = makeButton(panel, "CloseTutorial", 0.06, 0.42)
	close.Text = Strings.get("ui.close")
	local nextButton = makeButton(panel, "NextCard", 0.52, 0.42)
	nextButton.BackgroundColor3 = AMBER_COLOR
	nextButton.TextColor3 = PANEL_COLOR

	local card = 1
	local function renderCard()
		progress.Text = `{card}/{#TUTORIAL_CARDS}`
		body.Text = Strings.get(TUTORIAL_CARDS[card])
		nextButton.Text = Strings.get(if card == #TUTORIAL_CARDS then "tutorial.done" else "tutorial.next")
	end

	local function openTutorial()
		card = 1
		renderCard()
		lobby.Visible = false
		panel.Visible = true
	end

	local function closeTutorial()
		panel.Visible = false
		lobby.Visible = true
	end

	close.Activated:Connect(closeTutorial)
	nextButton.Activated:Connect(function()
		if card == #TUTORIAL_CARDS then
			closeTutorial()
		else
			card += 1
			renderCard()
		end
	end)
	return openTutorial, closeTutorial
end

local function makeRow(parent: ScrollingFrame, player: Player, order: number, ready: boolean): Frame
	local row = Instance.new("Frame")
	row.Name = tostring(player.UserId)
	row.LayoutOrder = order
	row.Size = UDim2.new(0.97, 0, 0, 42)
	row.BackgroundColor3 = ROW_COLOR
	row.BorderSizePixel = 0
	roundCorners(row, 8)

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.Position = UDim2.fromScale(0.04, 0)
	name.Size = UDim2.fromScale(0.65, 1)
	styleText(name, 18)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = if player == Players.LocalPlayer then Strings.get("ui.you", { name = player.DisplayName }) else player.DisplayName
	name.Parent = row

	local status = Instance.new("TextLabel")
	status.Name = "ReadyStatus"
	status.Position = UDim2.fromScale(0.71, 0)
	status.Size = UDim2.fromScale(0.25, 1)
	styleText(status, 17)
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.TextColor3 = if ready then READY_COLOR else MUTED_COLOR
	status.Text = Strings.get(if ready then "lobby.ready" else "lobby.waiting")
	status.Parent = row
	row.Parent = parent
	return row
end

function LobbyController:Init(_controllers: { [string]: any }) end

function LobbyController:Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.AutoLocalize = false
	screen.Name = "DepotLobby"
	screen.DisplayOrder = 1
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ResetOnSpawn = false
	screen.Parent = playerGui

	local panel = makePanel(screen)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromScale(0.06, 0.05)
	title.Size = UDim2.fromScale(0.88, 0.14)
	styleText(title, 30)
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = Strings.get("lobby.title")
	title.Parent = panel

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.Position = UDim2.fromScale(0.06, 0.2)
	countdown.Size = UDim2.fromScale(0.88, 0.105)
	styleText(countdown, 21)
	countdown.TextXAlignment = Enum.TextXAlignment.Left
	countdown.TextColor3 = AMBER_COLOR
	countdown.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "Players"
	list.Position = UDim2.fromScale(0.06, 0.34)
	list.Size = UDim2.fromScale(0.88, 0.37)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = MUTED_COLOR
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 5)
	listLayout.Parent = list

	local readyButton = makeButton(panel, "ReadyButton", 0.06, 0.49)
	local howToPlay = makeButton(panel, "HowToPlay", 0.59, 0.35)
	howToPlay.Text = Strings.get("tutorial.open")
	local openTutorial, closeTutorial = makeTutorial(screen, panel)
	local studio = RunService:IsStudio()
	local previewTutorial = studio and Workspace:GetAttribute("StudioTutorialPreview") == true
	local tutorialOpened = false

	local function openOnce()
		tutorialOpened = true
		openTutorial()
	end

	local function maybeOpenTutorial()
		if screen.Enabled and not tutorialOpened and (previewTutorial or localPlayer:GetAttribute("ShowTutorial") == true) then
			openOnce()
		end
	end

	howToPlay.Activated:Connect(openOnce)
	localPlayer:GetAttributeChangedSignal("ShowTutorial"):Connect(maybeOpenTutorial)

	local state = "Lobby"
	local readyByUserId: ReadyByUserId = {}
	local countdownEndsAt: number? = nil
	local tickConnection: RBXScriptConnection? = nil
	local rows: { Frame } = {}
	local localUserId = tostring(localPlayer.UserId)

	local function updateCountdown()
		local text = Strings.get("lobby.waiting_players")
		if state == "Countdown" then
			if countdownEndsAt then
				local seconds = math.ceil(countdownEndsAt - Workspace:GetServerTimeNow())
				text = if seconds > 0 then Strings.get("lobby.countdown", { seconds = seconds }) else Strings.get("lobby.departing")
			else
				text = Strings.get("lobby.countdown_started")
			end
		end
		if countdown.Text ~= text then
			countdown.Text = text
		end
	end

	local function updateRoster(leavingPlayer: Player?)
		for _, row in rows do
			row:Destroy()
		end
		table.clear(rows)

		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			if a == localPlayer or b == localPlayer then
				return a == localPlayer and b ~= localPlayer
			end
			return a.Name < b.Name
		end)
		for index, player in players do
			if player ~= leavingPlayer then
				table.insert(rows, makeRow(list, player, index, readyByUserId[tostring(player.UserId)] == true))
			end
		end

		local isReady = readyByUserId[localUserId] == true
		readyButton.Text = Strings.get(if isReady then "lobby.unready" else "lobby.ready")
		readyButton.BackgroundColor3 = if isReady then ROW_COLOR else AMBER_COLOR
		readyButton.TextColor3 = if isReady then TEXT_COLOR else PANEL_COLOR
	end

	local function applyRoundState(nextState: string, data: LobbyData?)
		state = nextState
		screen.Enabled = state == "Lobby" or state == "Countdown"
		readyByUserId = if screen.Enabled and data and type(data.Ready) == "table" then data.Ready else {}
		local deadline = if state == "Countdown" and data then data.CountdownEndsAt else nil
		countdownEndsAt = if type(deadline) == "number" and deadline == deadline and math.abs(deadline) < math.huge
			then deadline
			else nil
		if countdownEndsAt and not tickConnection then
			tickConnection = RunService.Heartbeat:Connect(updateCountdown)
		elseif not countdownEndsAt and tickConnection then
			tickConnection:Disconnect()
			tickConnection = nil
		end
		if screen.Enabled then
			updateRoster()
			updateCountdown()
			maybeOpenTutorial()
		else
			closeTutorial()
		end
	end

	Players.PlayerAdded:Connect(function()
		if screen.Enabled then
			updateRoster()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if screen.Enabled then
			updateRoster(player)
		end
	end)
	applyRoundState("Lobby", nil)

	if studio and Workspace:GetAttribute("StudioHudLobbyPreview") == true then
		local preview = Instance.new("BindableEvent")
		preview.Name = "StudioRoundPreview"
		preview.Parent = playerGui
		readyButton.Activated:Connect(function()
			if not screen.Enabled then
				return
			end
			if readyByUserId[localUserId] then
				applyRoundState("Lobby", nil)
				preview:Fire("Lobby")
				return
			end
			local deadline = Workspace:GetServerTimeNow() + Config.LOBBY_COUNTDOWN
			applyRoundState("Countdown", {
				Ready = { [localUserId] = true },
				CountdownEndsAt = deadline,
			})
			preview:Fire("Countdown")
			task.delay(Config.LOBBY_COUNTDOWN, function()
				if state == "Countdown" and countdownEndsAt == deadline then
					applyRoundState("Running", nil)
					preview:Fire("Running")
				end
			end)
		end)
		return
	end

	local lobbyReady = Remotes.Event("LobbyReady")
	Remotes.Event("RoundState").OnClientEvent:Connect(applyRoundState)
	readyButton.Activated:Connect(function()
		if screen.Enabled then
			lobbyReady:FireServer(readyByUserId[localUserId] ~= true)
		end
	end)
end

return LobbyController
