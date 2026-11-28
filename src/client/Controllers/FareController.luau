--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local findPassenger = require(script.Parent.Parent.FindPassenger)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local FareController = {}
local HANDOFF_TIME = 0.32
local MAX_HANDOFFS = 4
local ORDER = "MarshrutkaFare"

local function getBus(): Model?
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	return if bus and bus:IsA("Model") then bus else nil
end

local function hand(model: Model): BasePart?
	local part = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	return if part and part:IsA("BasePart") then part else model.PrimaryPart
end

function FareController:Start()
	local running = false
	local version = 0
	local active: BasePart? = nil
	local function clear()
		RunService:UnbindFromRenderStep(ORDER)
		if active then active:Destroy() end
		active = nil
	end

	local function showFare(passengerId: string)
		version += 1
		local request = version
		local bus = getBus()
		local root = if bus then bus.PrimaryPart else nil
		local folder = if bus then bus:FindFirstChild("Passengers") else nil
		if not root or not folder then return end

		-- Посадка и репликация модели не обязаны приходить в одном кадре.
		local passenger = findPassenger(folder, passengerId)
		if not passenger then
			task.wait(0.15)
			passenger = findPassenger(folder, passengerId)
		end
		if request ~= version or not running then return end
		local first = if passenger then hand(passenger) else nil
		if not first then return end
		local firstZ = root.CFrame:PointToObjectSpace(first.Position).Z
		local chain: { BasePart } = {}
		for _, model in folder:GetChildren() do
			if model:IsA("Model") and model ~= passenger then
				local nextHand = hand(model)
				if nextHand and root.CFrame:PointToObjectSpace(nextHand.Position).Z < firstZ then
					table.insert(chain, nextHand)
				end
			end
		end
		table.sort(chain, function(a, b)
			return root.CFrame:PointToObjectSpace(a.Position).Z > root.CFrame:PointToObjectSpace(b.Position).Z
		end)
		local points: { BasePart } = { first }
		for index = 1, math.min(#chain, MAX_HANDOFFS - 1) do
			table.insert(points, chain[index])
		end
		table.insert(points, root)

		clear()
		local coin = Instance.new("Part")
		coin.Name = "FareCoin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.07, 0.46, 0.46)
		coin.Color = Color3.fromRGB(243, 186, 76)
		coin.Material = Enum.Material.Metal
		coin.Anchored = true
		coin.CanCollide, coin.CanTouch, coin.CanQuery, coin.CastShadow = false, false, false, false
		coin.CFrame = first.CFrame
		coin.Parent = Workspace
		active = coin

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromScale(5.2, 0.75)
		billboard.StudsOffset = Vector3.new(0, 1, 0)
		billboard.MaxDistance = 25
		billboard.AutoLocalize = false
		billboard.Parent = coin
		local caption = Instance.new("TextLabel")
		caption.Size = UDim2.fromScale(1, 1)
		caption.BackgroundTransparency = 1
		caption.TextColor3 = Color3.fromRGB(255, 239, 188)
		caption.TextStrokeTransparency = 0.3
		caption.Font = Enum.Font.GothamBold
		caption.Text = Strings.get("fare.pass")
		caption.TextScaled = true
		caption.Parent = billboard

		local function positionOf(part: BasePart): Vector3
			if part == root then
				local driverSeat = if bus then bus:FindFirstChild("DriverSeat") else nil
				if driverSeat and driverSeat:IsA("BasePart") then
					return driverSeat.CFrame:PointToWorldSpace(Vector3.new(1.05, 1.25, 0))
				end
			end
			return part.Position
		end

		local elapsed = 0
		RunService:BindToRenderStep(ORDER, Enum.RenderPriority.Camera.Value + 3, function(dt: number)
			elapsed += dt
			local segment = math.floor(elapsed / HANDOFF_TIME) + 1
			local from, target = points[segment], points[segment + 1]
			if not from or not target or not from:IsDescendantOf(Workspace) or not target:IsDescendantOf(Workspace) then
				clear()
				return
			end
			local progress = (elapsed % HANDOFF_TIME) / HANDOFF_TIME
			local arc = Vector3.new(0, math.sin(progress * math.pi) * 0.55, 0)
			coin.CFrame = CFrame.new(positionOf(from):Lerp(positionOf(target), progress) + arc) * CFrame.Angles(0, elapsed * 8, math.pi / 2)
		end)
	end

	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		running = state == "Running"
		if not running then
			version += 1
			clear()
		end
	end)
	Remotes.Event("PassengerBoarded").OnClientEvent:Connect(function(id: string)
		if running then showFare(id) end
	end)
end

return FareController
