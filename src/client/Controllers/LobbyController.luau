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

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.92)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Active = true
	roundCorners(panel, 14)
	panel.Parent = screen

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.15
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = panel
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(500, 435)
	sizeLimit.Parent = panel

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

	local readyButton = Instance.new("TextButton")
	readyButton.Name = "ReadyButton"
	readyButton.AnchorPoint = Vector2.new(0, 1)
	readyButton.Position = UDim2.fromScale(0.06, 0.94)
	readyButton.Size = UDim2.fromScale(0.88, 0.18)
	limitText(readyButton, 23)
	readyButton.BackgroundTransparency = 0
	readyButton.Font = Enum.Font.GothamBold
	readyButton.TextScaled = true
	readyButton.TextTruncate = Enum.TextTruncate.AtEnd
	readyButton.BorderSizePixel = 0
	roundCorners(readyButton, 10)
	local buttonSize = Instance.new("UISizeConstraint")
	buttonSize.MinSize = Vector2.new(0, 48)
	buttonSize.Parent = readyButton
	readyButton.Parent = panel

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

	if RunService:IsStudio() and Workspace:GetAttribute("StudioHudLobbyPreview") == true then
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
