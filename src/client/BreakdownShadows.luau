--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Flashlight = require(script.Parent.Controllers.ConductorController.Flashlight)

local FAR = 7
local NEAR = 1.15
local BEAM_SAMPLE_INTERVAL = 0.1

type Shadow = { model: Model, window: Vector3, side: number, distance: number, lit: boolean }

local function piece(model: Model, name: string, size: Vector3, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = Color3.fromRGB(14, 18, 24)
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = false, false, false, false
	part.Parent = model
	return part
end

local function new(bus: Model, root: BasePart)
	local stage = Instance.new("Folder")
	stage.Name = "BreakdownShadows"
	local windows: { [number]: Vector3 } = {}
	local panes: { Instance } = {}
	for _, child in bus:GetDescendants() do
		if child:IsA("BasePart") and child.Transparency >= 0.25 and string.find(string.lower(child.Name), "window", 1, true) then
			local position = root.CFrame:PointToObjectSpace(child.Position)
			local side = if position.X < 0 then -1 else 1
			local before = windows[side]
			if not before or math.abs(position.Z) < math.abs(before.Z) then windows[side] = position end
			table.insert(panes, child)
		end
	end
	local box, size = bus:GetBoundingBox()
	local center = root.CFrame:PointToObjectSpace(box.Position)
	local shadows: { Shadow } = {}
	for _, side in { -1, 1 } do
		local model = Instance.new("Model")
		model.Name = if side == -1 then "LeftShadow" else "RightShadow"
		local head = piece(model, "Head", Vector3.new(0.85, 1.1, 0.8), Vector3.zero)
		head.Shape = Enum.PartType.Ball
		piece(model, "Shoulders", Vector3.new(1.8, 2.8, 0.7), Vector3.new(0, -1.65, 0))
		model.WorldPivot = CFrame.identity
		local window = windows[side] or Vector3.new(center.X + side * size.X / 2, center.Y + 1, center.Z)
		local position = root.CFrame:PointToWorldSpace(window + Vector3.xAxis * side * FAR)
		model:PivotTo(CFrame.lookAlong(position, root.CFrame.RightVector * -side))
		model.Parent = stage
		table.insert(shadows, { model = model, window = window, side = side, distance = FAR, lit = false })
	end
	stage.Parent = Workspace

	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	local elapsed = BEAM_SAMPLE_INTERVAL
	return {
		update = function(dt: number)
			elapsed += dt
			if elapsed >= BEAM_SAMPLE_INTERVAL then
				elapsed = 0
				for _, shadow in shadows do shadow.lit = false end
				for _, player in Players:GetPlayers() do
					local character = player.Character
					local aim, lamp = Flashlight.getLamp(Flashlight.find(character))
					if not character or not aim or not lamp or not lamp.Enabled then continue end
					local ignores = table.clone(panes)
					table.insert(ignores, character)
					rays.FilterDescendantsInstances = ignores
					local pose = aim.WorldCFrame
					local cone = math.cos(math.rad(lamp.Angle / 2))
					for _, shadow in shadows do
						if shadow.lit then continue end
						-- Смотрим на место у стекла, чтобы силуэт не дрожал на границе луча, пока отходит.
						local target = root.CFrame:PointToWorldSpace(shadow.window + Vector3.xAxis * shadow.side * NEAR)
						local offset = target - pose.Position
						if offset.Magnitude > 0 and offset.Magnitude <= lamp.Range and pose.LookVector:Dot(offset.Unit) >= cone
							and not Workspace:Raycast(pose.Position, offset, rays)
						then
							shadow.lit = true
						end
					end
				end
			end

			for _, shadow in shadows do
				local target = if shadow.lit then FAR else NEAR
				local rate = if shadow.lit then 4.5 else 0.85
				shadow.distance += (target - shadow.distance) * (1 - math.exp(-rate * dt))
				local offset = shadow.window + Vector3.xAxis * shadow.side * shadow.distance
				local position = root.CFrame:PointToWorldSpace(offset)
				shadow.model:PivotTo(CFrame.lookAlong(position, root.CFrame.RightVector * -shadow.side))
			end
		end,
		destroy = function() stage:Destroy() end,
	}
end

return new
