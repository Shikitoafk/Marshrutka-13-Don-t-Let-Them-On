--!strict

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local newShadows = require(script.Parent.Parent.BreakdownShadows)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local BreakdownController = {}
local atmosphere: { SetBreakdown: (any, boolean) -> () }? = nil
local KNOCK_INTERVAL = 4
local AMBER = Color3.fromRGB(255, 195, 104)
local TEXT = Color3.fromRGB(255, 241, 220)

local function getBus(): Model?
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	return if bus and bus:IsA("Model") then bus else nil
end

local function row(parent: Instance, position: UDim2, size: UDim2, color: Color3, maxSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Position, label.Size = position, size
	label.BackgroundTransparency = 1
	label.AutoLocalize = false
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = color
	label.TextScaled, label.TextWrapped = true, true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	return label
end

local function makeHud(parent: PlayerGui): (ScreenGui, TextLabel, Frame)
	local screen = Instance.new("ScreenGui")
	screen.Name = "BreakdownHud"
	screen.ResetOnSpawn = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.DisplayOrder = 4
	screen.Enabled = false
	screen.Parent = parent

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.18)
	panel.Size = UDim2.fromScale(0.56, 0.22)
	panel.BackgroundColor3 = Color3.fromRGB(28, 24, 25)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = screen
	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(220, 77)
	limits.MaxSize = Vector2.new(410, 108)
	limits.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local title = row(panel, UDim2.fromScale(0.06, 0.07), UDim2.fromScale(0.68, 0.31), AMBER, 22)
	title.Text = Strings.get("breakdown.title")
	local timer = row(panel, UDim2.fromScale(0.76, 0.08), UDim2.fromScale(0.18, 0.28), AMBER, 19)
	timer.Name = "BreakdownTimer"
	timer.TextXAlignment = Enum.TextXAlignment.Right
	local hint = row(panel, UDim2.fromScale(0.06, 0.39), UDim2.fromScale(0.88, 0.38), TEXT, 17)
	hint.Text = Strings.get("breakdown.hint")

	local track = Instance.new("Frame")
	track.Position = UDim2.fromScale(0.06, 0.84)
	track.Size = UDim2.fromScale(0.88, 0.065)
	track.BackgroundColor3 = Color3.fromRGB(72, 52, 43)
	track.BorderSizePixel = 0
	track.Parent = panel
	local fill = Instance.new("Frame")
	fill.Name = "RestartProgress"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = AMBER
	fill.BorderSizePixel = 0
	fill.Parent = track
	return screen, timer, fill
end

local function makeKnock(root: BasePart): Sound?
	local id = Config.SOUNDS.Bang
	if id == "" or id == "rbxassetid://0" then return nil end
	local cue = Instance.new("Sound")
	cue.Name = "BreakdownKnock"
	cue.SoundId = id
	cue.Volume = 0.52
	cue.RollOffMinDistance = 6
	cue.RollOffMaxDistance = 38
	cue.Parent = root
	return cue
end

function BreakdownController:Init(controllers: { [string]: any })
	atmosphere = controllers.AtmosphereController
end

function BreakdownController:Start()
	local player = Players.LocalPlayer
	local screen, timer, fill = makeHud(player:WaitForChild("PlayerGui") :: PlayerGui)
	local running, ghost = false, false
	local endsAt = 0
	local nextKnock = 0
	local tick: RBXScriptConnection? = nil
	local sceneRoot: BasePart? = nil
	local shadows: { update: (number) -> (), destroy: () -> () }? = nil
	local knock: Sound? = nil
	local heldPrompt: ProximityPrompt? = nil
	local holdStart = 0
	local promptTexts: { [ProximityPrompt]: string } = {}

	local function clearScene()
		if shadows then shadows.destroy() end
		if knock then knock:Destroy() end
		shadows, knock, sceneRoot = nil, nil, nil
	end

	local function stop()
		if endsAt == 0 then return end
		endsAt = 0
		if tick then tick:Disconnect() end
		tick = nil
		clearScene()
		for prompt, text in promptTexts do
			if prompt.Parent then prompt.ActionText = text end
		end
		table.clear(promptTexts)
		heldPrompt = nil
		fill.Size = UDim2.fromScale(0, 1)
		screen.Enabled = false
		local cabin = atmosphere
		if cabin then cabin:SetBreakdown(false) end
	end

	local function isRestartPrompt(prompt: ProximityPrompt): boolean
		local bus = getBus()
		return endsAt > 0 and bus ~= nil and prompt:IsDescendantOf(bus)
			and prompt.HoldDuration == Config.BREAKDOWN_FIX_HOLD
	end

	local function localizePrompt(prompt: ProximityPrompt)
		if isRestartPrompt(prompt) and promptTexts[prompt] == nil then
			promptTexts[prompt] = prompt.ActionText
			prompt.ActionText = Strings.get("breakdown.restart")
		end
	end

	local function update(dt: number)
		local now = Workspace:GetServerTimeNow()
		if now >= endsAt then
			stop()
			return
		end
		local bus = getBus()
		local root = if bus then bus.PrimaryPart else nil
		if root ~= sceneRoot then
			clearScene()
			if bus and root then
				sceneRoot = root
				shadows = newShadows(bus, root)
				knock = makeKnock(root)
				for _, child in bus:GetDescendants() do
					if child:IsA("ProximityPrompt") then localizePrompt(child) end
				end
			end
		end
		if shadows then shadows.update(dt) end
		if knock and now >= nextKnock then
			knock:Play()
			nextKnock = now + KNOCK_INTERVAL
		end
		timer.Text = Strings.get("breakdown.time_left", { seconds = math.ceil(endsAt - now) })
		local prompt = heldPrompt
		if prompt and (not prompt.Enabled or not isRestartPrompt(prompt)) then
			heldPrompt = nil
			prompt = nil
		end
		local progress = if prompt then math.clamp((os.clock() - holdStart) / Config.BREAKDOWN_FIX_HOLD, 0, 1) else 0
		fill.Size = UDim2.fromScale(progress, 1)
	end

	ProximityPromptService.PromptShown:Connect(localizePrompt)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if heldPrompt == prompt then heldPrompt = nil end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, who)
		if who == player and not ghost and isRestartPrompt(prompt) then
			heldPrompt, holdStart = prompt, os.clock()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, who)
		if who == player and heldPrompt == prompt then heldPrompt = nil end
	end)
	Remotes.Event("GhostState").OnClientEvent:Connect(function(isGhost: boolean)
		ghost = isGhost == true
		if ghost then heldPrompt = nil end
		screen.Enabled = endsAt > 0 and not ghost
	end)
	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		running = state == "Running"
		if not running then
			ghost = false
			stop()
		end
	end)
	Remotes.Event("ScareEvent").OnClientEvent:Connect(function(name: string, data: { [string]: unknown })
		if name ~= "Breakdown" or type(data) ~= "table" then return end
		if data.Active == false then
			stop()
			return
		end
		if not running or data.Active ~= true or type(data.EndsAt) ~= "number" then return end
		local now = Workspace:GetServerTimeNow()
		if not (data.EndsAt > now and data.EndsAt < math.huge) then return end
		local wasActive = endsAt > 0
		local deadline = math.min(data.EndsAt, now + Config.BREAKDOWN_TIMEOUT)
		endsAt = deadline
		if not wasActive then
			nextKnock = now
			screen.Enabled = not ghost
			local cabin = atmosphere
			if cabin then cabin:SetBreakdown(true) end
			update(0)
			if endsAt > 0 then tick = RunService.Heartbeat:Connect(update) end
		end
		task.delay(deadline - now, function()
			if endsAt == deadline then stop() end
		end)
	end)
end

return BreakdownController
