--!strict

local Mirror = {}

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
