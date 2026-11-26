--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local DriverController = {}

local ACTION_NAME = "MarshrutkaDriverInput"
local CAMERA_NAME = "MarshrutkaDriverCamera"
local GAS_COLOR = Color3.fromRGB(67, 53, 28)
local BRAKE_COLOR = Color3.fromRGB(68, 38, 42)
local GAS_PRESSED = Color3.fromRGB(142, 100, 35)
local BRAKE_PRESSED = Color3.fromRGB(142, 58, 65)
local BUTTON_COLOR = Color3.fromRGB(32, 43, 58)

type Requests = {
	throttle: (number) -> (),
	doors: (boolean) -> (),
	horn: () -> (),
}

local function makeButton(parent: Instance, name: string, x: number, y: number, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromScale(x, y)
	button.Size = UDim2.fromScale(0.48, 0.46)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(250, 244, 231)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Selectable = false

	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize = 14
	textLimit.MaxTextSize = 24
	textLimit.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = button

	button.Parent = parent
	return button
end

local function getDriverSeat(): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	local seat = if bus then bus:FindFirstChild("DriverSeat") else nil
	if seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
		return seat
	end
	return nil
end

function DriverController:Init(_controllers: { [string]: any }) end

function DriverController:Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "DriverControls"
	screen.ResetOnSpawn = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.Enabled = false
	screen.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.fromScale(0.97, if UserInputService.TouchEnabled then 0.76 else 0.95)
	panel.Size = UDim2.fromScale(0.4, 0.28)
	panel.BackgroundTransparency = 1
	panel.Parent = screen

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(196, 116)
	sizeLimit.MaxSize = Vector2.new(350, 180)
	sizeLimit.Parent = panel

	local gas = makeButton(panel, "Throttle", 0.52, 0, GAS_COLOR)
	local brake = makeButton(panel, "Brake", 0.52, 0.54, BRAKE_COLOR)
	local doors = makeButton(panel, "Doors", 0, 0, BUTTON_COLOR)
	local horn = makeButton(panel, "Horn", 0, 0.54, BUTTON_COLOR)

	local keyboardLabels = UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
	gas.Text = if keyboardLabels then "Газ · W" else "Газ"
	brake.Text = if keyboardLabels then "Тормоз · S" else "Тормоз"
	horn.Text = if keyboardLabels then "Сигнал · H" else "Сигнал"

	local role: string? = nil
	local roundState: string? = nil
	local doorsOpen = false
	local throttle = 0
	local keyboardThrottle: { [Enum.KeyCode]: number } = {}
	local pointerThrottle: { [InputObject]: number } = {}
	local pointerConnections: { [InputObject]: RBXScriptConnection } = {}
	local requests: Requests
	local seat: BasePart? = nil
	local drivenCamera: Camera? = nil
	local previousCameraType: Enum.CameraType? = nil
	local jumping = Enum.HumanoidStateType.Jumping
	local lockedHumanoid: Humanoid? = nil
	local jumpingWasEnabled = true
	local humanoidAdded: RBXScriptConnection? = nil

	local function restoreJump()
		if humanoidAdded then
			humanoidAdded:Disconnect()
			humanoidAdded = nil
		end
		if lockedHumanoid then
			lockedHumanoid:SetStateEnabled(jumping, jumpingWasEnabled)
			lockedHumanoid = nil
		end
	end

	local function refreshJumpLock(character: Model?)
		restoreJump()
		if not screen.Enabled or not character then
			return
		end

		local function lockJump(humanoid: Humanoid)
			jumpingWasEnabled = humanoid:GetStateEnabled(jumping)
			lockedHumanoid = humanoid
			humanoid.Jump = false
			humanoid:SetStateEnabled(jumping, false)
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			lockJump(humanoid)
		else
			humanoidAdded = character.ChildAdded:Connect(function(child)
				if child:IsA("Humanoid") and screen.Enabled and player.Character == character and not lockedHumanoid then
					lockJump(child)
				end
			end)
		end
	end

	local function updateDoors(open: boolean)
		doorsOpen = open
		local label = if open then "Закрыть" else "Двери"
		doors.Text = if keyboardLabels then label .. " · E" else label
		doors.BackgroundColor3 = if open then GAS_COLOR else BUTTON_COLOR
	end

	local function updateThrottle()
		-- Тормоз имеет приоритет, если обе педали удерживаются одновременно.
		local nextThrottle = 0
		for _, value in keyboardThrottle do
			if nextThrottle == 0 or value == -1 then
				nextThrottle = value
			end
		end
		for _, value in pointerThrottle do
			if nextThrottle == 0 or value == -1 then
				nextThrottle = value
			end
		end
		if nextThrottle ~= throttle then
			throttle = nextThrottle
			gas.BackgroundColor3 = if throttle == 1 then GAS_PRESSED else GAS_COLOR
			brake.BackgroundColor3 = if throttle == -1 then BRAKE_PRESSED else BRAKE_COLOR
			requests.throttle(throttle)
		end
	end

	local function clearInput()
		for _, connection in pointerConnections do
			connection:Disconnect()
		end
		table.clear(pointerConnections)
		table.clear(pointerThrottle)
		table.clear(keyboardThrottle)
		updateThrottle()
	end

	local function bindPedal(button: TextButton, value: number)
		button.AutoButtonColor = false
		button.InputBegan:Connect(function(input)
			local inputType = input.UserInputType
			if not screen.Enabled or (inputType ~= Enum.UserInputType.Touch and inputType ~= Enum.UserInputType.MouseButton1) then
				return
			end
			if pointerConnections[input] then
				return
			end
			pointerThrottle[input] = value
			pointerConnections[input] = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					pointerConnections[input]:Disconnect()
					pointerConnections[input] = nil
					pointerThrottle[input] = nil
					updateThrottle()
				end
			end)
			updateThrottle()
		end)
	end

	local function handleKey(_action: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		local key = input.KeyCode
		if state == Enum.UserInputState.Cancel then
			clearInput()
		elseif state == Enum.UserInputState.End then
			keyboardThrottle[key] = nil
			updateThrottle()
		elseif state == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			if key == Enum.KeyCode.W or key == Enum.KeyCode.S then
				keyboardThrottle[key] = if key == Enum.KeyCode.W then 1 else -1
				updateThrottle()
			elseif key == Enum.KeyCode.E then
				requests.doors(not doorsOpen)
			elseif key == Enum.KeyCode.H then
				requests.horn()
			end
		end
		return if UserInputService:GetFocusedTextBox() then Enum.ContextActionResult.Pass else Enum.ContextActionResult.Sink
	end

	local function restoreCamera()
		local camera, cameraType = drivenCamera, previousCameraType
		if camera and cameraType and camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = cameraType
		end
		drivenCamera = nil
		previousCameraType = nil
	end

	local function updateCamera()
		local driverSeat = seat
		if not driverSeat or not driverSeat:IsDescendantOf(Workspace) then
			driverSeat = getDriverSeat()
			seat = driverSeat
		end
		local camera = Workspace.CurrentCamera
		if camera ~= drivenCamera or not driverSeat then
			restoreCamera()
		end
		if not camera or not driverSeat then
			return
		end
		if camera ~= drivenCamera then
			drivenCamera = camera
			previousCameraType = camera.CameraType
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local view = driverSeat.CFrame * CFrame.new(0, 2.5, -1)
		camera.CFrame = view
		camera.Focus = view * CFrame.new(0, 0, -18)
	end

	local function updateControls()
		local enabled = role == "Driver" and (roundState == nil or roundState == "Running")
		if screen.Enabled == enabled then
			return
		end
		screen.Enabled = enabled
		refreshJumpLock(player.Character)
		if enabled then
			ContextActionService:BindActionAtPriority(
				ACTION_NAME,
				handleKey,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.W,
				Enum.KeyCode.S,
				Enum.KeyCode.E,
				Enum.KeyCode.H
			)
			RunService:BindToRenderStep(CAMERA_NAME, Enum.RenderPriority.Camera.Value + 1, updateCamera)
		else
			clearInput()
			ContextActionService:UnbindAction(ACTION_NAME)
			RunService:UnbindFromRenderStep(CAMERA_NAME)
			seat = nil
			restoreCamera()
		end
	end

	bindPedal(gas, 1)
	bindPedal(brake, -1)
	doors.Activated:Connect(function()
		if screen.Enabled then
			requests.doors(not doorsOpen)
		end
	end)
	horn.Activated:Connect(function()
		if screen.Enabled then
			requests.horn()
		end
	end)
	UserInputService.WindowFocusReleased:Connect(clearInput)
	UserInputService.TextBoxFocused:Connect(clearInput)
	GuiService.MenuOpened:Connect(clearInput)
	player.CharacterAdded:Connect(refreshJumpLock)
	player.CharacterRemoving:Connect(function()
		clearInput()
		restoreJump()
	end)
	updateDoors(false)

	-- Позволяет проверить кнопки в Studio до подключения серверных сервисов.
	if RunService:IsStudio() and Workspace:GetAttribute("StudioDriverPreview") == true then
		requests = {
			throttle = function(value)
				print("[DriverPreview] DriverInput", value)
			end,
			doors = function(open)
				updateDoors(open)
				print("[DriverPreview] DoorsRequest", open)
			end,
			horn = function()
				print("[DriverPreview] HornRequest")
			end,
		}
		role = "Driver"
		updateControls()
		return
	end

	local driverInput = Remotes.Event("DriverInput")
	local doorsRequest = Remotes.Event("DoorsRequest")
	local hornRequest = Remotes.Event("HornRequest")
	requests = {
		throttle = function(value)
			driverInput:FireServer(value)
		end,
		doors = function(open)
			doorsRequest:FireServer(open)
		end,
		horn = function()
			hornRequest:FireServer()
		end,
	}

	Remotes.Event("RoleAssigned").OnClientEvent:Connect(function(assignedRole: string)
		role = assignedRole
		updateControls()
	end)
	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		if state ~= roundState and (state == "Lobby" or state == "Results") then
			role = nil
			updateDoors(false)
		end
		roundState = state
		updateControls()
	end)
	Remotes.Event("BusState").OnClientEvent:Connect(function(_speed: number, _health: number, open: boolean)
		updateDoors(open)
	end)
end

return DriverController
