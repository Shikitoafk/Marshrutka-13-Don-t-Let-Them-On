--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ClientSettings = require(script.Parent.Parent.Parent.ClientSettings)

local Flashlight = {}

local RENDER_STEP = "MarshrutkaFlashlight"
local BEAM_RANGE = 45
local BEAM_ANGLE = 50
local AIM_INTERVAL = 0.1
type Fadeable = BasePart | Decal

local function setTransparency(part: Fadeable, value: number)
	if part:IsA("BasePart") then
		part.LocalTransparencyModifier = value
	elseif part:IsA("Decal") then
		part.LocalTransparencyModifier = value
	end
end

local function effectPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function makeEye(): Part
	local eye = effectPart("FlashlightEye")
	eye.Shape = Enum.PartType.Ball
	eye.Material = Enum.Material.Neon
	eye.Color = Color3.fromRGB(255, 22, 32)
	return eye
end

function Flashlight.find(container: Instance?): Tool?
	if container then
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("ConductorFlashlight") == true then
				return child
			end
		end
	end
	return nil
end

local function getLamp(tool: Tool?): (Attachment?, SpotLight?)
	local lens = if tool then tool:FindFirstChild("Lens") else nil
	local pivot = if lens then lens:FindFirstChild("Aim") else nil
	local lamp = if pivot then pivot:FindFirstChild("Lamp") else nil
	if pivot and pivot:IsA("Attachment") and lamp and lamp:IsA("SpotLight") then
		return pivot, lamp
	end
	return nil, nil
end

function Flashlight.isOn(tool: Tool?): boolean
	local _, light = getLamp(tool)
	return light ~= nil and light.Enabled
end

function Flashlight.new(previewMode: boolean)
	local emitter = effectPart("MarshrutkaFlashlight")
	emitter.Size = Vector3.one * 0.15
	emitter.Transparency = 1

	local startAttachment = Instance.new("Attachment")
	startAttachment.Parent = emitter
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = emitter
	local beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.FaceCamera = true
	beam.Width0 = 0.18
	beam.Segments = 12
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 239, 189))
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.83),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = emitter

	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = BEAM_ANGLE
	light.Range = BEAM_RANGE
	light.Brightness = 5
	light.Color = Color3.fromRGB(255, 244, 215)
	light.Shadows = true
	light.Enabled = false
	if previewMode then light.Parent = emitter end

	local originalTransparency: { [Fadeable]: number } = {}
	local ghostParts: { [Fadeable]: boolean } = {}
	local litEyes: { [BasePart]: boolean } = {}
	local glowingEyes: { [BasePart]: { Part } } = {}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local isOn = false
	local view: CFrame? = nil
	local beamRange = BEAM_RANGE
	local coneEdge = math.cos(math.rad(BEAM_ANGLE / 2))
	local nextAimAt = 0
	local remotes = if previewMode then nil else ReplicatedStorage:WaitForChild("Remotes")

	local function clearUnused()
		for part, original in originalTransparency do
			if not ghostParts[part] then
				setTransparency(part, original)
				originalTransparency[part] = nil
			end
		end
		for head, pair in glowingEyes do
			if not litEyes[head] then
				for _, eye in pair do
					eye:Destroy()
				end
				glowingEyes[head] = nil
			end
		end
	end

	local function updateBeam(character: Model?)
		local camera = Workspace.CurrentCamera
		local pivot, lamp = getLamp(Flashlight.find(character))
		local head = if previewMode and character then character:FindFirstChild("Head") else nil
		local origin = if pivot and lamp and lamp.Enabled then pivot.WorldPosition
			elseif head and head:IsA("BasePart") then head.Position else nil
		if not camera or not origin then
			view = nil
			light.Enabled = false
			beam.Enabled = false
			return
		end

		rayParams.FilterDescendantsInstances = if character then { character } else {}
		local direction = camera.CFrame.LookVector
		local pose = CFrame.lookAlong(origin, direction)
		local style = lamp or light
		beamRange = style.Range
		local halfAngle = math.rad(style.Angle / 2)
		coneEdge = math.cos(halfAngle)
		beam.Color = ColorSequence.new(style.Color)
		view = pose
		emitter.CFrame = pose
		local obstruction = Workspace:Raycast(origin, direction * beamRange, rayParams)
		local length = if obstruction then obstruction.Distance else beamRange
		endAttachment.Position = Vector3.new(0, 0, -length)
		beam.Width1 = math.max(beam.Width0, length * 2 * math.tan(halfAngle))
		light.Enabled = previewMode
		beam.Enabled = true

		if pivot and pivot.Parent and pivot.Parent:IsA("BasePart") then
			pivot.CFrame = pivot.Parent.CFrame:ToObjectSpace(pose)
			local now = os.clock()
			if remotes and now >= nextAimAt then
				nextAimAt = now + AIM_INTERVAL
				local aim = remotes:FindFirstChild("FlashlightAim")
				if aim and aim:IsA("RemoteEvent") then
					aim:FireServer(direction)
				end
			end
		end
	end

	local function render(character: Model?)
		updateBeam(character)
		local fade = if ClientSettings.get().ReducedEffects then 0.6 else 0.6 + 0.12 * math.sin(os.clock() * 18)
		for part, original in originalTransparency do
			setTransparency(part, math.max(original, fade))
		end
		for head, pair in glowingEyes do
			for index, eye in pair do
				local side = if index == 1 then -1 else 1
				eye.CFrame = head.CFrame * CFrame.new(side * head.Size.X * 0.18, head.Size.Y * 0.1, -head.Size.Z * 0.54)
			end
		end
	end

	local function setEnabled(enabled: boolean, player: Player)
		if enabled == isOn then
			return
		end
		isOn = enabled
		if enabled then
			emitter.Parent = Workspace
			render(player.Character)
			RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, function()
				render(player.Character)
			end)
		else
			RunService:UnbindFromRenderStep(RENDER_STEP)
			view = nil
			emitter.Parent = nil
			table.clear(ghostParts)
			table.clear(litEyes)
			clearUnused()
		end
	end

	local function update(passengers: { Model }): { Model }
		local illuminated: { Model } = {}
		table.clear(ghostParts)
		table.clear(litEyes)
		local pose = view
		if not pose then
			clearUnused()
			return illuminated
		end

		for _, passenger in passengers do
			local head = passenger:FindFirstChild("Head")
			local face = if head and head:IsA("BasePart") then head else nil
			local target = face or passenger.PrimaryPart or passenger:FindFirstChildWhichIsA("BasePart", true)
			if not target then
				continue
			end
			local direction = target.Position - pose.Position
			local distance = direction.Magnitude
			if distance <= 0 or distance > beamRange or pose.LookVector:Dot(direction.Unit) < coneEdge then
				continue
			end
			local hit = Workspace:Raycast(pose.Position, direction, rayParams)
			if hit and not hit.Instance:IsDescendantOf(passenger) then
				continue
			end

			table.insert(illuminated, passenger)
			if passenger:GetAttribute("NoShadow") == true then
				for _, part in passenger:GetDescendants() do
					if part:IsA("BasePart") or part:IsA("Decal") then
						ghostParts[part] = true
						if originalTransparency[part] == nil then
							originalTransparency[part] = part.LocalTransparencyModifier
						end
					end
				end
			end
			if face and passenger:GetAttribute("GlowEyes") == true then
				litEyes[face] = true
				if not glowingEyes[face] then
					local pair = { makeEye(), makeEye() }
					for _, eye in pair do
						eye.Size = Vector3.one * (face.Size.Y * 0.19)
						eye.CFrame = face.CFrame
						eye.Parent = emitter
					end
					glowingEyes[face] = pair
				end
			end
		end
		clearUnused()
		return illuminated
	end

	return { setEnabled = setEnabled, update = update }
end

return Flashlight
