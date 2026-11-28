--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local findPassenger = require(script.Parent.Parent.FindPassenger)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local PassengerSpeechController = {}
local BUBBLE_TIME = 3.5
local REPLICATION_WAIT = 0.9
type Message = { bubble: BillboardGui? }

local function getHead(id: string): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	local passenger = findPassenger(if bus then bus:FindFirstChild("Passengers") else nil, id)
	local head = if passenger then passenger:FindFirstChild("Head") else nil
	return if head and head:IsA("BasePart") then head else nil
end

local function createBubble(head: BasePart, line: string): BillboardGui
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "PassengerSpeech"
	bubble.AutoLocalize = false
	bubble.AlwaysOnTop = true
	bubble.MaxDistance = 28
	bubble.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + 0.9, 0)
	bubble.Size = UDim2.fromScale(5.8, 1.35)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 239, 207)
	label.TextWrapped = true
	label.TextScaled = true
	label.Font = Enum.Font.GothamMedium
	label.Text = line
	label.Parent = bubble

	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = 22
	size.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0.06, 0), UDim.new(0.06, 0)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0.08, 0), UDim.new(0.08, 0)
	padding.Parent = label
	local corners = Instance.new("UICorner")
	corners.CornerRadius = UDim.new(0.2, 0)
	corners.Parent = label

	bubble.Parent = head
	return bubble
end

function PassengerSpeechController:Start()
	local running = false
	local messages: { [string]: Message } = {}

	local function clear(id: string)
		local old = messages[id]
		messages[id] = nil
		if old and old.bubble then old.bubble:Destroy() end
	end

	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		running = state == "Running"
		if not running then
			for id in messages do clear(id) end
		end
	end)
	Remotes.Event("PassengerLeft").OnClientEvent:Connect(clear)
	Remotes.Event("PassengerSpeak").OnClientEvent:Connect(function(id: unknown, key: unknown)
		if not running or type(id) ~= "string" or type(key) ~= "string" or not string.match(key, "^line%.") then return end
		local line = Strings.get(key)
		if line == key then return end

		clear(id)
		local message: Message = {}
		messages[id] = message
		local deadline = os.clock() + REPLICATION_WAIT
		-- Реплика при посадке может прийти раньше модели или головы пассажира.
		while messages[id] == message do
			local head = getHead(id)
			if head then
				message.bubble = createBubble(head, line)
				task.delay(BUBBLE_TIME, function()
					if messages[id] == message then clear(id) end
				end)
				return
			end
			if os.clock() >= deadline then
				clear(id)
				return
			end
			task.wait(0.1)
		end
	end)
end

return PassengerSpeechController
