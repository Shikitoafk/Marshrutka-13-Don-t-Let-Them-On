--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Flashlight = {}

local RENDER_STEP = "MarshrutkaFlashlight"
local BEAM_ANGLE = 54
local BEAM_RANGE = Config.INSPECT_RANGE * 2
local CONE_EDGE = math.cos(math.rad(BEAM_ANGLE / 2))

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
	eye.Color = Color3.fromRGB(255, 216, 118)
	return eye
end

function Flashlight.new()
	local emitter = effectPart("MarshrutkaFlashlight")
	emitter.Size = Vector3.one * 0.15
	emitter.Transparency = 1

	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = BEAM_ANGLE
	light.Range = BEAM_RANGE
	light.Brightness = 2.8
	light.Color = Color3.fromRGB(255, 244, 215)
	light.Shadows = true
	light.Parent = emitter

	local originalShadows: { [BasePart]: boolean } = {}
	local glowingEyes: { [BasePart]: { Part } } = {}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local isOn = false

	local function clearUnused(shadows: { [BasePart]: boolean }, eyes: { [BasePart]: boolean })
		for part, original in originalShadows do
			if not shadows[part] then
				part.CastShadow = original
				originalShadows[part] = nil
			end
		end
		for head, pair in glowingEyes do
			if not eyes[head] then
				for _, eye in pair do
					eye:Destroy()
				end
				glowingEyes[head] = nil
			end
		end
	end

	local function followCamera()
		local camera = Workspace.CurrentCamera
		light.Enabled = camera ~= nil
		if camera then
			emitter.CFrame = camera.CFrame
		end
	end

	local function setEnabled(enabled: boolean)
		if enabled == isOn then
			return
		end
		isOn = enabled
		if enabled then
			followCamera()
			emitter.Parent = Workspace
			RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, followCamera)
		else
			RunService:UnbindFromRenderStep(RENDER_STEP)
			emitter.Parent = nil
			clearUnused({}, {})
		end
	end

	local function update(passengers: { Model }, character: Model?): { Model }
		local illuminated: { Model } = {}
		local shadows: { [BasePart]: boolean } = {}
		local eyes: { [BasePart]: boolean } = {}
		local camera = Workspace.CurrentCamera
		if not isOn or not camera then
			clearUnused(shadows, eyes)
			return illuminated
		end

		rayParams.FilterDescendantsInstances = if character then { character } else {}
		local view = camera.CFrame
		for _, passenger in passengers do
			local head = passenger:FindFirstChild("Head")
			local face = if head and head:IsA("BasePart") then head else nil
			local target = face or passenger.PrimaryPart or passenger:FindFirstChildWhichIsA("BasePart", true)
			if not target then
				continue
			end
			local direction = target.Position - view.Position
			local distance = direction.Magnitude
			if distance <= 0 or distance > BEAM_RANGE or view.LookVector:Dot(direction.Unit) < CONE_EDGE then
				continue
			end
			local hit = Workspace:Raycast(view.Position, direction, rayParams)
			if hit and not hit.Instance:IsDescendantOf(passenger) then
				continue
			end

			table.insert(illuminated, passenger)
			if passenger:GetAttribute("NoShadow") == true then
				for _, part in passenger:GetDescendants() do
					if part:IsA("BasePart") then
						shadows[part] = true
						if originalShadows[part] == nil then
							originalShadows[part] = part.CastShadow
							part.CastShadow = false
						end
					end
				end
			end
			if face and passenger:GetAttribute("GlowEyes") == true then
				eyes[face] = true
				local pair = glowingEyes[face]
				if not pair then
					pair = { makeEye(), makeEye() }
					glowingEyes[face] = pair
				end
				for index, eye in pair do
					local side = if index == 1 then -1 else 1
					eye.Size = Vector3.one * (face.Size.Y * 0.14)
					eye.CFrame = face.CFrame * CFrame.new(side * face.Size.X * 0.18, face.Size.Y * 0.1, -face.Size.Z * 0.51)
					eye.Parent = emitter
				end
			end
		end
		clearUnused(shadows, eyes)
		return illuminated
	end

	return { setEnabled = setEnabled, update = update }
end

return Flashlight
