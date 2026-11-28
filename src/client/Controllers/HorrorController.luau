--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ClientSettings = require(script.Parent.Parent.ClientSettings)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HorrorController = {}

local LOW_HEALTH = 50
local HANDPRINT_TIME = 10
local PHONE_TIME = 4
local JUMPSCARE_TIME = 1.5
local ROAD_DISAPPEAR_DISTANCE = 15
local MAX_ROAD_FIGURE_TIME = 30
local DARK = Color3.fromRGB(8, 10, 13)
local PALE = Color3.fromRGB(209, 211, 191)

type Effect = { update: (number) -> boolean, clear: () -> () }
type Payload = { [string]: unknown }

local function getBus(): Model?
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	return if bus and bus:IsA("Model") then bus else nil
end

local function sound(id: string, parent: Instance, volume: number, looped: boolean): Sound?
	if id == "" or id == "0" or id == "rbxassetid://0" then
		return nil
	end
	local result = Instance.new("Sound")
	result.SoundId = id
	result.Volume = volume
	result.Looped = looped
	result.RollOffMinDistance = 4
	result.RollOffMaxDistance = 45
	result.Parent = parent
	return result
end

local function frame(parent: Instance, color: Color3, x: number, y: number, w: number, h: number): Frame
	local result = Instance.new("Frame")
	result.BorderSizePixel = 0
	result.BackgroundColor3 = color
	result.Position = UDim2.fromScale(x, y)
	result.Size = UDim2.fromScale(w, h)
	result.Parent = parent
	return result
end

local function rounded(target: Frame, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = target
end

local function part(parent: Instance, color: Color3, size: Vector3): Part
	local result = Instance.new("Part")
	result.Anchored = true
	result.CanCollide = false
	result.CanTouch = false
	result.CanQuery = false
	result.CastShadow = false
	result.Color = color
	result.Size = size
	result.Parent = parent
	return result
end

local function figure(parent: Instance, seated: boolean): Model
	local model = Instance.new("Model")
	local lift = if seated then -1 else 0
	local body = part(model, DARK, Vector3.new(1.65, 2.4, 0.72))
	body.CFrame = CFrame.new(0, 2.5 + lift, 0)
	local head = part(model, DARK, Vector3.new(0.98, 1.25, 0.94))
	head.Shape = Enum.PartType.Ball
	head.CFrame = CFrame.new(0.12, 4.25 + lift, 0)
	for _, side in { -1, 1 } do
		local arm = part(model, DARK, Vector3.new(0.36, 2.2, 0.42))
		arm.CFrame = CFrame.new(side * 0.97, 2.39 + lift, 0) * CFrame.Angles(0, 0, side * 0.12)
		local leg = part(model, DARK, Vector3.new(0.58, 1.5, 0.63))
		leg.CFrame = if seated
			then CFrame.new(side * 0.42, 0.25, -0.55) * CFrame.Angles(math.pi / 2, 0, 0)
			else CFrame.new(side * 0.42, 0.75, 0)
	end
	model.WorldPivot = CFrame.identity
	model.Parent = parent
	return model
end

local function handprints(parent: Instance): Part
	local pane = part(parent, DARK, Vector3.new(2.6, 1.35, 0.02))
	pane.Transparency = 1
	local printGui = Instance.new("SurfaceGui")
	printGui.Face = Enum.NormalId.Front
	printGui.LightInfluence = 0
	printGui.CanvasSize = Vector2.new(260, 135)
	printGui.Parent = pane
	for index, x in { 0.1, 0.55 } do
		local hand = frame(printGui, DARK, x, if index == 1 then 0.09 else 0.24, 0.35, 0.63)
		hand.BackgroundTransparency = 1
		hand.Rotation = if index == 1 then -15 else 19
		rounded(frame(hand, PALE, 0.3, 0.38, 0.55, 0.53), 0.35)
		for finger = 1, 4 do
			rounded(frame(hand, PALE, 0.23 + finger * 0.135, 0.06 + math.abs(finger - 2) * 0.07, 0.1, 0.42), 0.5)
		end
		local thumb = frame(hand, PALE, 0.16, 0.45, 0.14, 0.35)
		thumb.Rotation = -32
		rounded(thumb, 0.5)
	end
	return pane
end

local function vignette(screen: ScreenGui): { Frame }
	local edges = {
		frame(screen, DARK, 0, 0, 0.25, 1),
		frame(screen, DARK, 0.75, 0, 0.25, 1),
		frame(screen, DARK, 0, 0, 1, 0.25),
		frame(screen, DARK, 0, 0.75, 1, 0.25),
	}
	for index, edge in edges do
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = ({ 0, 180, 90, 270 })[index]
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = edge
		edge.Visible = false
	end
	return edges
end

local function scareImage(screen: ScreenGui): Frame
	local shade = frame(screen, DARK, 0, 0, 1, 1)
	shade.Visible = false
	local face = frame(shade, PALE, 0.5, 0.5, 0.88, 0.92)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Rotation = -9
	local shape = Instance.new("UIAspectRatioConstraint")
	shape.AspectRatio = 0.66
	shape.AspectType = Enum.AspectType.FitWithinMaxSize
	shape.Parent = face
	rounded(face, 0.44)
	for _, x in { 0.13, 0.59 } do
		local socket = frame(face, DARK, x, 0.25, 0.28, 0.26)
		socket.Rotation = if x < 0.5 then 17 else -17
		rounded(socket, 0.48)
		rounded(frame(socket, PALE, 0.38, 0.34, 0.18, 0.27), 0.5)
	end
	local mouth = frame(face, DARK, 0.36, 0.58, 0.3, 0.32)
	mouth.Rotation = 13
	rounded(mouth, 0.46)
	return shade
end

local function routePointAhead(root: BasePart, distance: number): Vector3
	local route = if root.Parent and root.Parent.Parent then root.Parent.Parent:FindFirstChild("Route") else nil
	if not route then
		return root.Position + root.CFrame.LookVector * distance
	end
	local points: { BasePart } = {}
	for _, child in route:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	local closestGap, bestIndex, bestT = math.huge, 0, 0
	for i = 2, #points do
		local a = points[i - 1].Position
		local segment = points[i].Position - a
		local lengthSquared = segment:Dot(segment)
		if lengthSquared > 0 then
			local t = math.clamp((root.Position - a):Dot(segment) / lengthSquared, 0, 1)
			local gap = (root.Position - (a + segment * t)).Magnitude
			if gap < closestGap then
				closestGap, bestIndex, bestT = gap, i, t
			end
		end
	end
	if bestIndex == 0 then
		return root.Position + root.CFrame.LookVector * distance
	end
	local start = points[bestIndex - 1].Position:Lerp(points[bestIndex].Position, bestT)
	for i = bestIndex, #points do
		local segment = points[i].Position - start
		if segment.Magnitude >= distance then
			return start + segment.Unit * distance
		end
		distance -= segment.Magnitude
		start = points[i].Position
	end
	return start
end

local function rearSeat(bus: Model, root: BasePart): BasePart?
	local seats = bus:FindFirstChild("Seats")
	local rear: BasePart? = nil
	local rearZ = -math.huge
	if seats then
		for _, seat in seats:GetChildren() do
			if seat:IsA("BasePart") then
				local z = root.CFrame:PointToObjectSpace(seat.Position).Z
				if z > rearZ then
					rear, rearZ = seat, z
				end
			end
		end
	end
	return rear
end

type NeckJoint = Motor6D | AnimationConstraint
type NeckPose = { base: CFrame, applied: CFrame? }

local function getNeckJoint(model: Instance): (NeckJoint?, BasePart?, Attachment?)
	local neck = model:FindFirstChild("Neck", true)
	if neck and neck:IsA("Motor6D") and neck.Part1 then
		return neck, neck.Part0, nil
	end
	if neck and neck:IsA("AnimationConstraint") then
		local attachment = neck.Attachment0
		local torso = if attachment then attachment.Parent else nil
		if torso and torso:IsA("BasePart") then
			return neck, torso, attachment
		end
	end
	return nil, nil, nil
end

local function restoreNeck(joint: NeckJoint, pose: NeckPose)
	if joint:IsA("Motor6D") then
		joint.C0 = pose.base
	elseif joint.Transform == pose.applied then
		joint.Transform = pose.base
	end
end

function HorrorController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "TripHorror"
	screen.DisplayOrder = 10
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.ResetOnSpawn = false
	screen.Parent = playerGui
	local edges = vignette(screen)
	local jumpscare = scareImage(screen)
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Enabled = false
	correction.Saturation = -0.32
	correction.Contrast = 0.12
	correction.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Enabled = false
	bloom.Intensity = 0.28
	bloom.Size = 18
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local stage = Instance.new("Folder")
	stage.Name = "ClientScares"
	stage.Parent = Workspace
	local heartbeat = sound(Config.SOUNDS.Heartbeat, SoundService, 0.32, true)
	local music = sound(Config.SOUNDS.Music, SoundService, 0.14, true)
	if music then music.Name = "TripMusic" end
	local scream = sound(Config.SOUNDS.Jumpscare, SoundService, 0.66, false)
	local effects: { [string]: Effect } = {}
	local round = "Lobby"
	local health = Config.BUS_MAX_HEALTH
	local jumpPlayed = false
	local jumpUntil = 0
	local shakeStarted, shakeUntil, shakeAmount = 0, 0, 0
	local shakenCamera: Camera? = nil
	local originalCamera, appliedCamera = CFrame.identity, CFrame.identity

	local function clear(name: string)
		local effect = effects[name]
		if effect then
			effect.clear()
			effects[name] = nil
		end
	end

	local function keep(name: string, duration: number, update: (number) -> boolean, cleanup: () -> ())
		clear(name)
		local start = os.clock()
		effects[name] = {
			update = function(now) return now - start < duration and update(now - start) end,
			clear = cleanup,
		}
	end

	local function playAt(id: string, target: Instance, volume: number)
		local cue = sound(id, target, volume, false)
		if cue then
			cue:Play()
		end
	end

	local function shake(duration: number, amount: number)
		if ClientSettings.get().ReducedEffects then return end
		shakeStarted = os.clock()
		shakeUntil = shakeStarted + duration
		shakeAmount = amount
	end

	local function restoreCamera()
		local camera = shakenCamera
		if camera and camera.CFrame == appliedCamera then
			camera.CFrame = originalCamera
		end
		shakenCamera = nil
	end

	local function showJumpscare()
		if jumpPlayed then return end
		jumpPlayed = true
		jumpUntil = os.clock() + JUMPSCARE_TIME
		if not ClientSettings.get().ReducedEffects then
			jumpscare.Visible = true
			if scream then scream:Play() end
		end
	end

	local function applyRound(state: string)
		if round == state then return end
		round = state
		local running = state == "Running"
		correction.Enabled, bloom.Enabled = running, running and not ClientSettings.get().ReducedEffects
		if music then
			if running then music:Play() else music:Stop() end
		end
		if not running then
			for _, effect in effects do effect.clear() end
			table.clear(effects)
			if heartbeat then heartbeat:Stop() end
			shakeUntil = 0
			restoreCamera()
			for _, edge in edges do edge.Visible = false end
		end
		if state ~= "Results" then
			jumpPlayed, jumpUntil, jumpscare.Visible = false, 0, false
			if scream then scream:Stop() end
		end
	end

	local function watchBusHealth(value: number)
		health = value
		if heartbeat then
			local low = round == "Running" and health <= LOW_HEALTH
			if low and not heartbeat.IsPlaying then heartbeat:Play() end
			if not low and heartbeat.IsPlaying then heartbeat:Stop() end
		end
	end

	local function onScare(name: string, data: Payload)
		if name == "Jumpscare" then
			if round == "Running" or round == "Results" then showJumpscare() end
			return
		end
		if round ~= "Running" or type(data) ~= "table" then return end
		local bus = getBus()
		local root = if bus then bus.PrimaryPart else nil
		if not bus or not root then return end
		local function busPresent(): boolean return root:IsDescendantOf(Workspace) end

		if name == "WindowKnock" and (data.Side == "Left" or data.Side == "Right") and type(data.Z) == "number" then
			local side = if data.Side == "Left" then -1 else 1
			local box, size = bus:GetBoundingBox()
			local localCenter = root.CFrame:PointToObjectSpace(box.Position)
			local halfLength = math.max(0, size.Z / 2 - 1.4)
			local z = math.clamp(data.Z, localCenter.Z - halfLength, localCenter.Z + halfLength)
			local localPose = CFrame.lookAlong(Vector3.new(localCenter.X + side * (size.X / 2 - 0.45), localCenter.Y + size.Y * 0.15, z), Vector3.new(-side, 0, 0))
			local pane = handprints(stage)
			pane.CFrame = root.CFrame * localPose
			playAt(Config.SOUNDS.Knock, pane, 0.65)
			keep(name, HANDPRINT_TIME, function()
				pane.CFrame = root.CFrame * localPose
				return busPresent()
			end, function() pane:Destroy() end)
		elseif name == "RoofBang" then
			clear(name)
			local roof = part(stage, DARK, Vector3.one * 0.05)
			roof.Transparency = 1
			local _, size = bus:GetBoundingBox()
			roof.CFrame = root.CFrame * CFrame.new(0, size.Y * 0.9, 0)
			playAt(Config.SOUNDS.Bang, roof, 0.72)
			shake(0.55, 1)
			local lamps: { { source: BasePart, proxy: Part, transparency: number } } = {}
			local fixtures = bus:FindFirstChild("InteriorLights")
			if fixtures then
				for _, lamp in fixtures:GetChildren() do
					if lamp:IsA("BasePart") then
						local proxy = part(roof, lamp.Color, lamp.Size)
						proxy.CFrame = lamp.CFrame
						proxy.Material = lamp.Material
						table.insert(lamps, { source = lamp, proxy = proxy, transparency = lamp.LocalTransparencyModifier })
						lamp.LocalTransparencyModifier = 1
					end
				end
			end
			keep(name, 1, function(age)
				roof.CFrame = root.CFrame * CFrame.new(0, size.Y * 0.9, 0)
				for _, lamp in lamps do
					local tilt = if ClientSettings.get().ReducedEffects then 0 else math.sin(age * 20) * (1 - age) * 0.35
					lamp.proxy.CFrame = lamp.source.CFrame * CFrame.Angles(0, 0, tilt)
				end
				return busPresent()
			end, function()
				for _, lamp in lamps do lamp.source.LocalTransparencyModifier = lamp.transparency end
				roof:Destroy()
			end)
		elseif name == "FigureOnRoad" and type(data.Distance) == "number" then
			local target = routePointAhead(root, math.clamp(data.Distance, 20, 200))
			local silhouette = figure(stage, false)
			silhouette:PivotTo(CFrame.new(target))
			keep(name, MAX_ROAD_FIGURE_TIME, function()
				return busPresent() and (root.Position - target).Magnitude > ROAD_DISAPPEAR_DISTANCE
			end, function() silhouette:Destroy() end)
		elseif name == "BackSeatFigure" and type(data.Duration) == "number" then
			local seat = rearSeat(bus, root)
			if not seat then return end
			local silhouette = figure(stage, true)
			silhouette:ScaleTo(0.65)
			local offset = CFrame.new(0, seat.Size.Y / 2, 0)
			silhouette:PivotTo(seat.CFrame * offset)
			keep(name, math.clamp(data.Duration, 0, 10), function()
				silhouette:PivotTo(seat.CFrame * offset)
				return seat:IsDescendantOf(Workspace)
			end, function() silhouette:Destroy() end)
		elseif name == "PhoneRing" and type(data.Seat) == "string" then
			local seats = bus:FindFirstChild("Seats")
			local seat = if seats then seats:FindFirstChild(data.Seat) else nil
			if not seat or not seat:IsA("BasePart") then return end
			local handset = part(stage, DARK, Vector3.new(0.29, 0.06, 0.5))
			local offset = CFrame.new(0, -seat.Size.Y / 2 - 0.22, 0)
			handset.CFrame = seat.CFrame * offset
			local ring = sound(Config.SOUNDS.PhoneRing, handset, 0.65, true)
			if ring then ring:Play() end
			keep(name, PHONE_TIME, function()
				handset.CFrame = seat.CFrame * offset
				return seat:IsDescendantOf(Workspace)
			end, function() handset:Destroy() end)
		elseif name == "Stare" and type(data.Duration) == "number" then
			local folder = bus:FindFirstChild("Passengers")
			if not folder then return end
			clear(name)
			local necks: { [NeckJoint]: NeckPose } = {}
			keep(name, math.clamp(data.Duration, 0, 10), function()
				local camera = Workspace.CurrentCamera
				if not camera or not busPresent() then return false end
				for joint, pose in necks do
					if not joint:IsDescendantOf(folder) then
						restoreNeck(joint, pose)
						necks[joint] = nil
					end
				end
				for _, model in folder:GetChildren() do
					local joint, torso, attachment = getNeckJoint(model)
					if joint and torso then
						local pose: NeckPose = necks[joint] or { base = if joint:IsA("Motor6D") then joint.C0 else joint.Transform }
						necks[joint] = pose
						local jointPose = if attachment then attachment.WorldCFrame else torso.CFrame * pose.base
						local offset = jointPose:PointToObjectSpace(camera.CFrame.Position)
						if offset.Magnitude > 0.1 then
							local yaw = math.atan2(-offset.X, -offset.Z)
							local pitch = math.atan2(offset.Y, Vector2.new(offset.X, offset.Z).Magnitude)
							local turn = CFrame.Angles(math.clamp(pitch, -0.4, 0.4), yaw, 0)
							if joint:IsA("Motor6D") then
								joint.C0 = pose.base * turn
							else
								-- Между кадрами Animator может обновить Transform. Не складываем свой поворот с собой.
								local current = joint.Transform
								if current ~= pose.applied then pose.base = current end
								joint.Transform = turn * pose.base
								pose.applied = joint.Transform
							end
						end
					end
				end
				return true
			end, function()
				for joint, pose in necks do
					restoreNeck(joint, pose)
				end
			end)
		end
	end

	-- Roblox применяет базовый Transform анимации до PreSimulation.
	RunService.PreSimulation:Connect(function()
		local stare = effects.Stare
		if round == "Running" and stare and not stare.update(os.clock()) then
			clear("Stare")
		end
	end)
	RunService:BindToRenderStep("MarshrutkaHorrorRestore", Enum.RenderPriority.Camera.Value - 1, restoreCamera)
	RunService:BindToRenderStep("MarshrutkaHorror", Enum.RenderPriority.Camera.Value + 2, function()
		local now = os.clock()
		if jumpscare.Visible and now >= jumpUntil then
			jumpscare.Visible = false
			if scream then scream:Stop() end
		end
		if round ~= "Running" then return end
		for name, effect in effects do
			if name ~= "Stare" and not effect.update(now) then clear(name) end
		end
		local reduced = ClientSettings.get().ReducedEffects
		local activeShake = not reduced and now < shakeUntil
		local intensity = if activeShake then (shakeUntil - now) / (shakeUntil - shakeStarted) * shakeAmount else 0
		local pulse = if not reduced and health <= LOW_HEALTH then 0.17 * (1 + math.sin(now * 7)) else 0
		for _, edge in edges do
			edge.Visible = true
			edge.BackgroundTransparency = math.clamp(0.62 - pulse - intensity * 0.25, 0.12, 1)
		end
		local camera = Workspace.CurrentCamera
		if activeShake and camera then
			originalCamera = camera.CFrame
			shakenCamera = camera
			appliedCamera = originalCamera * CFrame.Angles(math.noise(now * 29) * intensity * 0.055, math.noise(15, now * 29) * intensity * 0.043, 0)
			camera.CFrame = appliedCamera
		end
	end)
	ClientSettings.Changed:Connect(function()
		local reduced = ClientSettings.get().ReducedEffects
		bloom.Enabled = round == "Running" and not reduced
		if reduced then
			shakeUntil = 0
			restoreCamera()
			jumpscare.Visible = false
			if scream then scream:Stop() end
		end
	end)

	Remotes.Event("RoundState").OnClientEvent:Connect(applyRound)
	Remotes.Event("BusState").OnClientEvent:Connect(function(_speed: number, value: number) watchBusHealth(value) end)
	Remotes.Event("ScareEvent").OnClientEvent:Connect(onScare)
	Remotes.Event("AnomalyEscalated").OnClientEvent:Connect(function(_level: number, _effect: string)
		if round == "Running" then shake(0.7, 1.25) end
	end)
	Remotes.Event("RunEnded").OnClientEvent:Connect(function(summary: { Won: boolean })
		if summary.Won == false then onScare("Jumpscare", {}) end
	end)

	if RunService:IsStudio() and Workspace:GetAttribute("StudioHorrorPreview") == true then
		local preview = Instance.new("BindableEvent")
		preview.Name = "StudioHorrorPreview"
		preview.Parent = playerGui
		preview.Event:Connect(function(name: string, data: Payload?)
			if name == "Lobby" then
				applyRound("Lobby")
			else
				applyRound("Running")
				if name == "LowHealth" then
					watchBusHealth(LOW_HEALTH)
				else
					onScare(name, data or {})
				end
			end
		end)
	end
end

return HorrorController
