--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local RateLimit = require(script.Parent.Parent.RateLimit)
require(Shared:WaitForChild("Remotes"))

local AIM_RATE = 12
local SYNC_INTERVAL = 0.1
local TOGGLE_COOLDOWN = 0.2

type Lamp = {
	tool: Tool,
	lens: BasePart,
	pivot: Attachment,
	light: SpotLight,
	click: Sound?,
	nextToggleAt: number,
}

local FlashlightService = {}
local registry: { [string]: any } = {}

local function part(name: string, size: Vector3, color: Color3): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Size = size
	result.Color = color
	result.Material = Enum.Material.SmoothPlastic
	result.CanCollide = false
	result.CanTouch = false
	result.CanQuery = false
	result.CastShadow = false
	result.Massless = true
	return result
end

local function makeLamp(player: Player, battery: number): Lamp
	local id = player:GetAttribute("EquippedFlashlight")
	local styles: { [string]: { color: Color3, angle: number } } = Cosmetics.Beams
	local style = if type(id) == "string" then styles[id] or styles.Classic else styles.Classic

	local tool = Instance.new("Tool")
	tool.Name = "Flashlight"
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.Grip = CFrame.new(0, -0.15, 0)
	tool:SetAttribute("ConductorFlashlight", true)
	tool:SetAttribute("Battery", math.ceil(battery))

	local handle = part("Handle", Vector3.new(0.35, 0.35, 0.9), style.color:Lerp(Color3.new(0.09, 0.1, 0.12), 0.72))
	handle.Parent = tool
	local lens = part("Lens", Vector3.new(0.5, 0.5, 0.2), style.color)
	lens.CFrame = handle.CFrame * CFrame.new(0, 0, -0.5)
	lens.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = handle, lens
	weld.Parent = lens

	local pivot = Instance.new("Attachment")
	pivot.Name = "Aim"
	pivot.Position = Vector3.new(0, 0, -lens.Size.Z / 2)
	pivot.Parent = lens
	local light = Instance.new("SpotLight")
	light.Name = "Lamp"
	light.Face = Enum.NormalId.Front
	light.Enabled = false
	light.Range = 45
	light.Angle = math.clamp(style.angle + 22, 45, 55)
	light.Brightness = 5
	light.Color = style.color
	light.Shadows = true
	light.Parent = pivot

	local click: Sound? = nil
	local soundId = Config.SOUNDS.Knock
	if soundId ~= "" and soundId ~= "rbxassetid://0" then
		local sound = Instance.new("Sound")
		sound.Name = "Switch"
		sound.SoundId = soundId
		sound.Volume = 0.18
		sound.RollOffMaxDistance = 14
		sound.Parent = lens
		click = sound
	end
	return { tool = tool, lens = lens, pivot = pivot, light = light, click = click, nextToggleAt = 0 }
end

local function setOn(lamp: Lamp, enabled: boolean)
	lamp.light.Enabled = enabled
	lamp.lens.Material = if enabled then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

function FlashlightService:Init(services: { [string]: any })
	registry = services
end

function FlashlightService:Start()
	local round, route, roles, ghosts = registry.RoundService, registry.RouteService, registry.RoleService, registry.GhostService
	if not (round and route and roles and ghosts) then
		return
	end

	local running = false
	local lamps: { [Player]: Lamp } = {}
	local batteries: { [Player]: number } = {}
	local elapsed = 0

	local function canUse(player: Player)
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		return running and not route:IsFinished() and table.find(round:GetRiders(), player) ~= nil
			and roles:GetDriver() ~= player and not ghosts:IsGhost(player) and humanoid ~= nil and humanoid.Health > 0
	end

	local function remove(player: Player)
		local lamp = lamps[player]
		if lamp then
			lamps[player] = nil
			lamp.tool:Destroy()
		end
	end

	local function give(player: Player, backpack: Backpack): Lamp
		local battery = batteries[player] or Config.FLASHLIGHT_BATTERY
		batteries[player] = battery
		local lamp = makeLamp(player, battery)
		lamps[player] = lamp
		lamp.tool.Activated:Connect(function()
			local now = os.clock()
			if lamps[player] ~= lamp or now < lamp.nextToggleAt or lamp.tool.Parent ~= player.Character or not canUse(player) then
				return
			end
			lamp.nextToggleAt = now + TOGGLE_COOLDOWN
			if (batteries[player] or 0) <= 0 then return end
			setOn(lamp, not lamp.light.Enabled)
			if lamp.click then lamp.click:Play() end
		end)
		lamp.tool.Unequipped:Connect(function()
			setOn(lamp, false)
			lamp.pivot.Orientation = Vector3.zero
		end)
		lamp.tool.Parent = backpack
		return lamp
	end

	-- Движение камеры передаётся отдельно от штатного Tool.Activated.
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local function connectAim(child: Instance)
		if child.Name ~= "FlashlightAim" or not child:IsA("RemoteEvent") then return end
		local allowAim = RateLimit.new(AIM_RATE)
		child.OnServerEvent:Connect(function(player: Player, direction: unknown)
			if not allowAim(player) or typeof(direction) ~= "Vector3" then return end
			local length = direction.Magnitude
			-- Сравнение диапазона отсекает также NaN и бесконечность.
			if not (length >= 0.99 and length <= 1.01) then return end
			local lamp = lamps[player]
			if not lamp or not lamp.light.Enabled or lamp.tool.Parent ~= player.Character or not canUse(player) then return end
			local pose = CFrame.lookAlong(lamp.pivot.WorldPosition, direction)
			lamp.pivot.CFrame = lamp.lens.CFrame:ToObjectSpace(pose)
		end)
	end
	remotes.ChildAdded:Connect(connectAim)
	local aim = remotes:FindFirstChild("FlashlightAim")
	if aim then connectAim(aim) end

	route.StopChanged:Connect(function(index: number, _name: string, phase: string)
		if index == 1 and phase == "Approaching" then
			running = true
			elapsed = 0
			table.clear(batteries)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		remove(player)
		batteries[player] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		if not running then return end
		elapsed += dt
		if elapsed < SYNC_INTERVAL then return end
		local step = elapsed
		elapsed = 0
		if route:IsFinished() then
			running = false
			for player in lamps do remove(player) end
			return
		end
		for player in lamps do
			if not canUse(player) then remove(player) end
		end
		for _, player: Player in round:GetRiders() do
			if not canUse(player) then continue end
			local backpack = player:FindFirstChildOfClass("Backpack")
			if not backpack then continue end
			local lamp = lamps[player]
			if not lamp or (lamp.tool.Parent ~= backpack and lamp.tool.Parent ~= player.Character) then
				remove(player)
				give(player, backpack)
			elseif lamp.light.Enabled then
				local battery = math.max(0, (batteries[player] or 0) - step)
				batteries[player] = battery
				lamp.tool:SetAttribute("Battery", math.ceil(battery))
				if battery == 0 then setOn(lamp, false) end
			end
		end
	end)
end

return FlashlightService
