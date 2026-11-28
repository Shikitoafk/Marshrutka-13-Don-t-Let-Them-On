--!strict

local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local SettingsAudio = require(script.Parent.Parent.SettingsAudio)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local GhostController = {}
type GhostData = { RevivesLeft: number? }
local BG = Color3.fromRGB(32, 43, 58)
local FG = Color3.fromRGB(250, 244, 231)

local function passengerInView(): string?
	local camera = Workspace.CurrentCamera
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	local folder = if bus then bus:FindFirstChild("Passengers") else nil
	if not camera or not folder then return nil end
	local best, bestAngle = nil, 0.87
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			local head = model:FindFirstChild("Head")
			local id = model:GetAttribute("PassengerId")
			if head and head:IsA("BasePart") and type(id) == "string" then
				local offset = head.Position - camera.CFrame.Position
				if offset.Magnitude > 0 and offset.Magnitude <= Config.INSPECT_RANGE * 2 then
					local angle = camera.CFrame.LookVector:Dot(offset.Unit)
					if angle > bestAngle then best, bestAngle = id, angle end
				end
			end
		end
	end
	return best
end

local function action(parent: Frame, text: string, x: number, y: number, width: number): TextButton
	local result = Instance.new("TextButton")
	result.BackgroundColor3 = Color3.fromRGB(69, 86, 106)
	result.BorderSizePixel = 0
	result.Position = UDim2.fromScale(x, y)
	result.Size = UDim2.fromScale(width, 0.33)
	result.Text = text
	result.TextColor3 = FG
	result.Font = Enum.Font.GothamBold
	result.TextScaled = true
	result.TextWrapped = true
	result.Parent = parent
	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(0, 48)
	limits.Parent = result
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MaxTextSize = 18
	textLimit.Parent = result
	return result
end

function GhostController:Start()
	local player = Players.LocalPlayer
	local gui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "GhostControls"
	screen.AutoLocalize = false
	screen.Enabled = false
	screen.DisplayOrder = 4
	screen.ResetOnSpawn = false
	screen.Parent = gui
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.fromScale(0.5, 0.86)
	panel.Size = UDim2.fromScale(0.9, 0.28)
	panel.BackgroundColor3 = BG
	panel.BorderSizePixel = 0
	panel.Parent = screen
	local constraints = Instance.new("UISizeConstraint")
	constraints.MinSize = Vector2.new(0, 145)
	constraints.MaxSize = Vector2.new(370, 175)
	constraints.Parent = panel
	local title = Instance.new("TextLabel")
	title.Text = Strings.get("ghost.title")
	title.Size = UDim2.fromScale(1, 0.23)
	title.Font = Enum.Font.GothamBold
	title.BackgroundTransparency = 1
	title.TextColor3 = FG
	title.TextScaled = true
	title.Parent = panel
	local knock = action(panel, Strings.get("ghost.knock"), 0.03, 0.24, 0.45)
	local flicker = action(panel, Strings.get("ghost.flicker"), 0.52, 0.24, 0.45)
	local revive = action(panel, Strings.get("ghost.return"), 0.03, 0.63, 0.94)

	local filter = Instance.new("ColorCorrectionEffect")
	filter.Name = "GhostSight"
	filter.Enabled = false
	filter.Saturation = -1
	filter.TintColor = Color3.fromRGB(196, 210, 225)
	filter.Parent = Lighting
	local running = false
	local ghost = false
	local freeRevives: number? = nil
	local pending = false
	local nextReturnAt = 0
	local reviveRequest = Remotes.Event("ReviveRequest")
	local ghostAction = Remotes.Event("GhostAction")

	local function hasCredit(): boolean
		local count = player:GetAttribute("ReviveCredits")
		return type(count) == "number" and count > 0
	end
	local function updateButton()
		local canRequest = freeRevives == nil or freeRevives > 0 or hasCredit()
		local available = canRequest or Config.PRODUCT_REVIVE > 0
		revive.Text = Strings.get(if canRequest then "ghost.return" elseif available then "ghost.buy_return" else "ghost.return_unavailable")
		revive.Active = available and not pending
		revive.AutoButtonColor = revive.Active
	end

	local function update()
		local enabled = running and ghost
		if enabled == screen.Enabled then
			updateButton()
			return
		end
		screen.Enabled, filter.Enabled = enabled, enabled
		SettingsAudio.setGhost(enabled)
		updateButton()
	end

	player:GetAttributeChangedSignal("ReviveCredits"):Connect(updateButton)

	knock.Activated:Connect(function()
		if not screen.Enabled then return end
		local target = passengerInView()
		if target then
			ghostAction:FireServer("Knock", target)
		else
			title.Text = Strings.get("ghost.no_target")
			task.delay(1.5, function() title.Text = Strings.get("ghost.title") end)
		end
	end)
	flicker.Activated:Connect(function()
		if screen.Enabled then ghostAction:FireServer("Flicker") end
	end)
	revive.Activated:Connect(function()
		if not screen.Enabled or not revive.Active then return end
		local now = os.clock()
		if now < nextReturnAt then return end
		nextReturnAt = now + 0.8
		if freeRevives == nil or freeRevives > 0 or hasCredit() then
			reviveRequest:FireServer()
		else
			pending = true
			updateButton()
			local ok = pcall(function()
				MarketplaceService:PromptProductPurchase(player, Config.PRODUCT_REVIVE)
			end)
			if not ok then pending = false; updateButton() end
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id)
		if userId == player.UserId and id == Config.PRODUCT_REVIVE then
			pending = false
			updateButton()
		end
	end)

	local function applyGhost(isGhost: boolean, data: GhostData?)
		ghost = isGhost == true
		local count = if type(data) == "table" then data.RevivesLeft else nil
		freeRevives = if type(count) == "number" then math.max(0, count) else nil
		update()
	end

	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		running = state == "Running"
		if not running then
			ghost, pending, freeRevives = false, false, nil
			nextReturnAt = 0
		end
		update()
	end)
	Remotes.Event("GhostState").OnClientEvent:Connect(applyGhost)
	if RunService:IsStudio() and Workspace:GetAttribute("StudioGhostPreview") == true then
		local preview = Instance.new("BindableEvent")
		preview.Name = "StudioGhostPreview"
		preview.Parent = gui
		preview.Event:Connect(function(enabled: boolean, count: number?)
			running = true
			applyGhost(enabled, { RevivesLeft = count })
		end)
	end
end

return GhostController
