--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local StudioPreview = {}

local function part(parent: Instance, name: string, pose: CFrame, size: Vector3, color: Color3): Part
	local block = Instance.new("Part")
	block.Name = name
	block.Size = size
	block.CFrame = pose
	block.Color = color
	block.Anchored = true
	block.CanCollide = false
	block.CanTouch = false
	block.Parent = parent
	return block
end

function StudioPreview.create(origin: CFrame): Model
	local bus = Instance.new("Model")
	bus.Name = "ConductorPreviewBus"
	local passengers = Instance.new("Folder")
	passengers.Name = "Passengers"
	passengers.Parent = bus

	local floorColor = Color3.fromRGB(95, 99, 105)
	part(bus, "Floor", origin * CFrame.new(0, -2.95, -6), Vector3.new(9, 0.2, 10), floorColor)
	local marker = part(bus, "Mirror", origin * CFrame.new(0, 1, -1.5), Vector3.one * 0.1, floorColor)
	marker.Transparency = 1
	marker.CanQuery = false

	local function addPassenger(id: string, x: number, z: number, shirt: Color3): Model
		local passenger = Instance.new("Model")
		passenger.Name = id
		passenger:SetAttribute("PassengerId", id)
		local pose = origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0)
		part(passenger, "Head", pose * CFrame.new(0, 0.85, 0), Vector3.new(1.1, 1.1, 1.1), Color3.fromRGB(215, 176, 140))
		passenger.PrimaryPart =
			part(passenger, "Torso", pose * CFrame.new(0, -0.65, 0), Vector3.new(1.45, 1.8, 0.9), shirt)
		part(passenger, "Legs", pose * CFrame.new(0, -2.1, 0), Vector3.new(1.4, 1.1, 0.85), Color3.fromRGB(38, 47, 65))
		passenger.Parent = passengers
		return passenger
	end

	addPassenger("preview-blue", -2.4, -6, Color3.fromRGB(54, 107, 180))
	local hidden = addPassenger("preview-red", 2.4, -6, Color3.fromRGB(174, 55, 61))
	hidden:SetAttribute("HiddenInMirror", true)
	local ghost = addPassenger("preview-green", 0, -8.3, Color3.fromRGB(54, 133, 83))
	ghost:SetAttribute("NoShadow", true)
	local glowing = addPassenger("preview-yellow", 2.4, -9, Color3.fromRGB(180, 131, 61))
	glowing:SetAttribute("GlowEyes", true)

	bus.Parent = Workspace
	return bus
end

function StudioPreview.ticket(passengerId: string): { Route: string, Date: string }
	return {
		Route = Config.ROUTE_NUMBER,
		Date = if passengerId == "preview-red" then "13.11.1986" else os.date("!%d.%m.%Y"),
	}
end

return StudioPreview
