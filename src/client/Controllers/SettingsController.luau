--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))
local PlayerSettings = require(Shared:WaitForChild("PlayerSettings"))
local ClientSettings = require(script.Parent.Parent.ClientSettings)

local SettingsController = {}
local PANEL = Color3.fromRGB(21, 28, 39)
local ROW = Color3.fromRGB(52, 66, 84)
local TEXT = Color3.fromRGB(250, 244, 231)
local AMBER = Color3.fromRGB(246, 198, 110)

type NumericKey = "MusicVolume" | "EffectsVolume" | "DriverSensitivity"

local function limitText(gui: GuiObject, maxSize: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize, limit.MaxTextSize = 13, maxSize
	limit.Parent = gui
end

local function textStyle(gui: TextLabel, maxSize: number)
	gui.TextColor3 = TEXT
	gui.TextScaled = true
	gui.TextWrapped = true
	gui.Font = Enum.Font.GothamBold
	limitText(gui, maxSize)
end

local function button(parent: Instance, name: string, caption: string, position: UDim2, size: UDim2): TextButton
	local control = Instance.new("TextButton")
	control.Name, control.Text = name, caption
	control.Position, control.Size = position, size
	control.BackgroundColor3 = ROW
	control.BorderSizePixel = 0
	control.TextColor3 = TEXT
	control.TextScaled = true
	control.TextWrapped = true
	control.Font = Enum.Font.GothamBold
	limitText(control, 21)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = control
	control.Parent = parent
	return control
end

function SettingsController:Start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "GameSettings"
	gui.DisplayOrder = 12
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local open = button(gui, "OpenSettings", "⚙", UDim2.new(0.025, 0, 0.035, 56), UDim2.fromScale(0.12, 0.09))
	local openSize = Instance.new("UISizeConstraint")
	openSize.MinSize, openSize.MaxSize = Vector2.new(44, 44), Vector2.new(50, 50)
	openSize.Parent = open

	local shade = Instance.new("Frame")
	shade.BackgroundColor3 = Color3.new()
	shade.BackgroundTransparency = 0.35
	shade.Size = UDim2.fromScale(1, 1)
	shade.Active, shade.Visible = true, false
	shade.Parent = gui
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position, panel.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.94, 0.94)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	panel.Parent = shade
	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MaxSize = Vector2.new(450, 415)
	panelSize.Parent = panel
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.92, 0.12)
	title.Position = UDim2.fromScale(0.04, 0.02)
	title.BackgroundTransparency = 1
	title.Text = Strings.get("settings.title")
	textStyle(title, 26)
	title.Parent = panel
	local rows = Instance.new("ScrollingFrame")
	rows.Size, rows.Position = UDim2.fromScale(0.92, 0.63), UDim2.fromScale(0.04, 0.15)
	rows.BackgroundTransparency, rows.BorderSizePixel = 1, 0
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.CanvasSize = UDim2.fromScale(0, 0)
	rows.ScrollBarThickness = 5
	rows.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = rows
	local status = Instance.new("TextLabel")
	status.Size, status.Position = UDim2.fromScale(0.53, 0.15), UDim2.fromScale(0.04, 0.82)
	status.BackgroundTransparency = 1
	status.Text = ""
	textStyle(status, 15)
	status.Parent = panel
	local close = button(panel, "CloseSettings", Strings.get("ui.close"), UDim2.fromScale(0.59, 0.97), UDim2.fromScale(0.37, 0.15))
	close.AnchorPoint = Vector2.new(0, 1)
	local closeSize = Instance.new("UISizeConstraint")
	closeSize.MinSize = Vector2.new(0, 44)
	closeSize.Parent = close

	local canSave, remote = pcall(Remotes.Function, "UpdateSettings")
	local version, savedVersion = 0, 0
	local saving, queued = false, false

	local function save()
		if not canSave or version == savedVersion or saving then return end
		saving = true
		task.spawn(function()
			while savedVersion ~= version do
				local target = version
				local ok, accepted = pcall(function() return remote:InvokeServer(ClientSettings.get()) end)
				if not ok or accepted ~= true then
					status.Text = Strings.get("settings.save_failed")
					break
				end
				savedVersion = target
				status.Text = ""
				if savedVersion ~= version then task.wait(0.5) end
			end
			saving = false
		end)
	end

	local function change(settings: PlayerSettings.Values)
		ClientSettings.set(settings)
		version += 1
		if not canSave then
			status.Text = Strings.get("settings.session_only")
		elseif not queued then
			queued = true
			task.delay(0.5, function()
				queued = false
				save()
			end)
		end
	end

	local function numericRow(index: number, key: NumericKey, caption: string, minimum: number, maximum: number, step: number)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(0.97, 0, 0, 49)
		row.LayoutOrder = index
		row.Parent = rows
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, -146, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = Strings.get(caption)
		textStyle(name, 18)
		name.Parent = row
		local minus = button(row, key .. "Down", "−", UDim2.new(1, -140, 0, 0), UDim2.new(0, 44, 1, 0))
		local plus = button(row, key .. "Up", "+", UDim2.new(1, -44, 0, 0), UDim2.new(0, 44, 1, 0))
		for _, control in { minus, plus } do
			local size = Instance.new("UISizeConstraint")
			size.MinSize = Vector2.new(44, 44)
			size.Parent = control
		end
		local value = Instance.new("TextLabel")
		value.BackgroundTransparency = 1
		value.Size, value.Position = UDim2.new(0, 52, 1, 0), UDim2.new(1, -96, 0, 0)
		textStyle(value, 17)
		value.TextColor3 = AMBER
		value.Parent = row
		local function render()
			local current = ClientSettings.get()[key]
			value.Text = if key == "DriverSensitivity" then string.format("%.2f×", current) else tostring(math.round(current * 100)) .. "%"
			minus.Interactable, plus.Interactable = current > minimum, current < maximum
		end
		local function adjust(delta: number)
			local next = table.clone(ClientSettings.get())
			next[key] = math.clamp(math.round((next[key] + delta) * 100) / 100, minimum, maximum)
			change(next)
		end
		minus.Activated:Connect(function() adjust(-step) end)
		plus.Activated:Connect(function() adjust(step) end)
		ClientSettings.Changed:Connect(render)
		render()
	end
	numericRow(1, "MusicVolume", "settings.music", 0, 1, 0.1)
	numericRow(2, "EffectsVolume", "settings.effects", 0, 1, 0.1)
	numericRow(3, "DriverSensitivity", "settings.sensitivity", PlayerSettings.MinSensitivity, PlayerSettings.MaxSensitivity, 0.25)
	local reduced = button(rows, "ReducedEffects", "", UDim2.fromScale(0, 0), UDim2.new(0.97, 0, 0, 49))
	reduced.LayoutOrder = 4
	local function renderReduced()
		reduced.Text = Strings.get("settings.reduced") .. " · " .. Strings.get(if ClientSettings.get().ReducedEffects then "settings.on" else "settings.off")
	end
	ClientSettings.Changed:Connect(renderReduced)
	renderReduced()
	reduced.Activated:Connect(function()
		local next = table.clone(ClientSettings.get())
		next.ReducedEffects = not next.ReducedEffects
		change(next)
	end)

	local function load()
		if version ~= 0 then save(); return end
		local ok, profile = pcall(function() return Remotes.Function("GetProfile"):InvokeServer() end)
		if ok and version == 0 and type(profile) == "table" then
			local settings = PlayerSettings.normalize(profile.Settings)
			if settings then ClientSettings.set(settings) end
		end
	end
	open.Activated:Connect(function()
		shade.Visible, open.Visible = true, false
		task.spawn(load)
	end)
	close.Activated:Connect(function()
		shade.Visible, open.Visible = false, true
	end)
	player:GetAttributeChangedSignal("UnlockedNight"):Connect(load)
	task.spawn(load)
end

return SettingsController
