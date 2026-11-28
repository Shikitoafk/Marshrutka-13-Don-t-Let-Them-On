--!strict

local Mirror = {}

local CABIN_AMBIENT = Color3.fromRGB(83, 84, 98)
local FALLBACK_LIGHT = Color3.fromRGB(158, 136, 105)
local CABIN_LIGHT_DIRECTION = Vector3.new(-0.25, -1, -0.5).Unit

local function cabinLightColor(bus: Model): Color3
	local fixtures = bus:FindFirstChild("InteriorLights")
	if not fixtures then return FALLBACK_LIGHT end
	local red, green, blue, count = 0, 0, 0, 0
	for _, light in fixtures:GetDescendants() do
		if light:IsA("Light") then
			count += 1
			local brightness = if light.Enabled then math.clamp(light.Brightness, 0, 1) else 0
			local color = light.Color
			red += color.R * brightness
			green += color.G * brightness
			blue += color.B * brightness
		end
	end
	return if count > 0 then Color3.new(red / count, green / count, blue / count) else FALLBACK_LIGHT
end

local function clonePart(part: BasePart): BasePart?
	local copy = part:Clone()
	if not copy then
		return nil
	end
	for _, child in copy:GetChildren() do
		if not (child:IsA("Decal") or child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance")) then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanTouch = false
	copy.CanQuery = false
	copy.LocalTransparencyModifier = 0
	return copy
end

function Mirror.new(viewport: ViewportFrame)
	viewport.Ambient = CABIN_AMBIENT
	viewport.LightColor = FALLBACK_LIGHT
	local camera = Instance.new("Camera")
	camera.FieldOfView = 70
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local scene = Instance.new("WorldModel")
	scene.Parent = viewport
	local copies: { [BasePart]: BasePart } = {}

	local function clear()
		scene:ClearAllChildren()
		table.clear(copies)
	end

	local function update(bus: Model?): boolean
		local marker = if bus then bus:FindFirstChild("Mirror") else nil
		if not bus or not marker or not marker:IsA("BasePart") then
			clear()
			return false
		end

		camera.CFrame = marker.CFrame
		viewport.LightDirection = marker.CFrame:VectorToWorldSpace(CABIN_LIGHT_DIRECTION)
		viewport.LightColor = cabinLightColor(bus)
		local seen: { [BasePart]: boolean } = {}
		local function copyVisibleChildren(parent: Instance)
			for _, child in parent:GetChildren() do
				if child == marker or (child:IsA("Model") and child:GetAttribute("HiddenInMirror") == true) then
					continue
				end
				if child:IsA("BasePart") and child.Transparency < 1 then
					local copy = copies[child]
					if not copy then
						local newCopy = clonePart(child)
						if newCopy then
							newCopy.Parent = scene
							copies[child] = newCopy
							copy = newCopy
						end
					end
					if copy then
						seen[child] = true
						copy.CFrame = child.CFrame
						copy.Transparency = child.Transparency
						copy.Color = child.Color
					end
				end
				copyVisibleChildren(child)
			end
		end
		copyVisibleChildren(bus)

		for part, copy in copies do
			if not seen[part] then
				copy:Destroy()
				copies[part] = nil
			end
		end
		return true
	end

	return { update = update, clear = clear }
end

return Mirror
