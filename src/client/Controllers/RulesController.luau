--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Nights = require(Shared:WaitForChild("Nights"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local RulesController = {}

local CARD_TIME = 3
local PAPER = Color3.fromRGB(229, 212, 171)
local INK = Color3.fromRGB(46, 35, 28)
local TAPE = Color3.fromRGB(180, 150, 95)
local AMBER = Color3.fromRGB(246, 198, 110)
type ChimePlayer = { PlayStopChime: ((any) -> ())? }
local atmosphere: ChimePlayer? = nil
local modal: Frame? = nil

local function frame(parent: Instance, color: Color3, position: UDim2, size: UDim2): Frame
	local result = Instance.new("Frame")
	result.BackgroundColor3 = color
	result.BorderSizePixel = 0
	result.Position = position
	result.Size = size
	result.Parent = parent
	return result
end

local function label(parent: Instance, text: string, position: UDim2, size: UDim2): TextLabel
	local result = Instance.new("TextLabel")
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.GothamBold
	result.Position = position
	result.Size = size
	result.Text = text
	result.TextColor3 = INK
	result.TextScaled = true
	result.TextWrapped = true
	result.Parent = parent
	return result
end

local function makePaper(parent: Instance, position: UDim2, size: UDim2): Frame
	local paper = frame(parent, PAPER, position, size)
	label(paper, Strings.get("rules.title"), UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.13))
	for _, x in { 0.05, 0.81 } do
		local tape = frame(paper, TAPE, UDim2.fromScale(x, -0.025), UDim2.fromScale(0.14, 0.075))
		tape.Rotation = if x < 0.5 then -14 else 12
		tape.BackgroundTransparency = 0.18
	end
	return paper
end

local function makeList(parent: Instance, canScroll: boolean): GuiObject
	local list: GuiObject
	if canScroll then
		local scroll = Instance.new("ScrollingFrame")
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.fromScale(0, 0)
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 6
		list = scroll
	else
		list = Instance.new("Frame")
	end
	list.Size = UDim2.fromScale(0.9, if canScroll then 0.57 else 0.77)
	list.Position = UDim2.fromScale(0.05, 0.19)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, if canScroll then 8 else 3)
	layout.Parent = list
	return list
end

local function renderRules(list: GuiObject, keys: { string })
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	local scroll = list:IsA("ScrollingFrame")
	if scroll then
		(list :: ScrollingFrame).CanvasPosition = Vector2.zero
	end
	for index, key in keys do
		local height = if scroll then UDim2.new(0.96, 0, 0, 45) else UDim2.fromScale(1, 0.85 / #keys)
		local line = label(list, Strings.get(key), UDim2.fromScale(0, 0), height)
		line.LayoutOrder = index
		line.TextXAlignment = Enum.TextXAlignment.Left
	end
end

function RulesController:Init(controllers: { [string]: any })
	atmosphere = controllers.AtmosphereController
end

function RulesController:Open()
	local overlay = modal
	if overlay and (overlay.Parent :: ScreenGui).Enabled then
		overlay.Visible = true
	end
end

function RulesController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "NightRules"
	screen.DisplayOrder = 4
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ResetOnSpawn = false
	screen.AutoLocalize = false
	screen.Enabled = false
	screen.Parent = playerGui

	local card = label(screen, "", UDim2.fromScale(0.5, 0.28), UDim2.fromScale(0.9, 0.15))
	card.Name = "NightCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = AMBER
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.Visible = false
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(0, 52)
	limit.MaxSize = Vector2.new(480, 90)
	limit.Parent = card

	local shade = frame(screen, Color3.new(), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	shade.Name = "RulesOverlay"
	shade.BackgroundTransparency = 0.38
	shade.Active = true
	shade.Visible = false
	modal = shade
	local paper = makePaper(shade, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.92, 0.88))
	paper.AnchorPoint = Vector2.new(0.5, 0.5)
	local paperLimit = Instance.new("UISizeConstraint")
	paperLimit.MaxSize = Vector2.new(450, 530)
	paperLimit.Parent = paper
	local list = makeList(paper, true)

	local close = Instance.new("TextButton")
	close.Text = Strings.get("ui.close")
	close.BackgroundColor3 = INK
	close.TextColor3 = PAPER
	close.Font = Enum.Font.GothamBold
	close.TextScaled = true
	close.BorderSizePixel = 0
	close.AnchorPoint = Vector2.new(0, 1)
	close.Position = UDim2.fromScale(0.05, 0.97)
	close.Size = UDim2.fromScale(0.9, 0.16)
	local closeLimit = Instance.new("UISizeConstraint")
	closeLimit.MinSize = Vector2.new(0, 48)
	closeLimit.Parent = close
	close.Parent = paper
	close.Activated:Connect(function()
		shade.Visible = false
	end)

	local sheet = Instance.new("SurfaceGui")
	sheet.Name = "CabinRulesSheet"
	sheet.Face = Enum.NormalId.Front
	sheet.CanvasSize = Vector2.new(660, 540)
	sheet.LightInfluence = 0.15
	sheet.MaxDistance = 48
	sheet.AutoLocalize = false
	sheet.Enabled = false
	sheet.Parent = playerGui
	local wallPaper = makePaper(sheet, UDim2.fromScale(0.25, 0.16), UDim2.fromScale(0.5, 0.66))
	local wallList = makeList(wallPaper, false)

	local sound: Sound? = nil
	local chimeId = Config.SOUNDS.StopChime
	if (not atmosphere or not atmosphere.PlayStopChime) and chimeId ~= "rbxassetid://0" and chimeId ~= "0" and chimeId ~= "" then
		local chime = Instance.new("Sound")
		chime.SoundId = chimeId
		chime.Volume = 0.5
		chime.Parent = SoundService
		sound = chime
	end

	local currentNight = Nights[1]
	local keys = currentNight.Rules
	local cardVersion = 0
	local announced = false
	local receivedNight = false

	local function updateWall()
		local map = Workspace:FindFirstChild("Map")
		local bus = if map then map:FindFirstChild("Bus") else nil
		local wall = if bus then bus:FindFirstChild("RulesBoard", true) or bus:FindFirstChild("BackWall", true) else nil
		local adornee = if wall and wall:IsA("BasePart") then wall else nil
		sheet.Adornee = adornee
		sheet.Enabled = screen.Enabled and adornee ~= nil
	end

	local function refresh()
		renderRules(list, keys)
		renderRules(wallList, keys)
		updateWall()
	end

	local function showCard()
		announced = true
		cardVersion += 1
		local version = cardVersion
		card.Text = Strings.get("night.card", { number = currentNight.Index, name = Strings.get(currentNight.NameKey) })
		card.Visible = true
		local controller = atmosphere
		local playChime = if controller then controller.PlayStopChime else nil
		if playChime then
			playChime(controller)
		elseif sound then
			sound:Play()
		end
		task.delay(CARD_TIME, function()
			if version == cardVersion then card.Visible = false end
		end)
	end

	local function applyNight(index: number, ruleKeys: { string }?)
		local night = Nights[index]
		if not night then return end
		currentNight = night
		keys = if type(ruleKeys) == "table" and #ruleKeys > 0 then ruleKeys else night.Rules
		receivedNight = true
		refresh()
		if screen.Enabled and not announced then showCard() end
	end

	local function applyRound(state: string)
		screen.Enabled = state == "Running"
		if screen.Enabled then
			refresh()
			if receivedNight and not announced then showCard() end
		else
			shade.Visible = false
			sheet.Enabled = false
			card.Visible = false
			cardVersion += 1
			announced, receivedNight = false, false
			currentNight, keys = Nights[1], Nights[1].Rules
		end
	end

	Workspace.DescendantAdded:Connect(function(instance: Instance)
		if screen.Enabled and (instance.Name == "BackWall" or instance.Name == "RulesBoard") then updateWall() end
	end)
	Remotes.Event("NightInfo").OnClientEvent:Connect(applyNight)
	Remotes.Event("RoundState").OnClientEvent:Connect(applyRound)
	if RunService:IsStudio() and Workspace:GetAttribute("StudioHudLobbyPreview") == true then
		local previewNight = Workspace:GetAttribute("StudioRulesNight")
		local preview = playerGui:WaitForChild("StudioRoundPreview") :: BindableEvent
		preview.Event:Connect(function(state: string)
			if state == "Running" then
				applyNight(if type(previewNight) == "number" and Nights[previewNight] then previewNight else 1)
			end
			applyRound(state)
		end)
	end
end

return RulesController
