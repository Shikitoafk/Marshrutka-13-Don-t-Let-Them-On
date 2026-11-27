--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ClientSettings = require(script.Parent.Parent.ClientSettings)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Controller = {}
local EFFECT_TIME = 0.65

local function createPart(parent: Instance, size: Vector3, pose: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Size, part.CFrame, part.Color = size, pose, color
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = false, false, false, false
	part.Parent = parent
	return part
end

function Controller:Start()
	local effects = Instance.new("Folder")
	effects.Name = "TakenEffects"
	effects.Parent = Workspace

	Remotes.Event("PlayerTaken").OnClientEvent:Connect(function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		local character = if player then player.Character else nil
		if not player or not character then return end
		local id = player:GetAttribute("EquippedTakenEffect")
		local item = if type(id) == "string" then Cosmetics.find("TakenEffect", id) else nil
		local effect = if item and not ClientSettings.get().ReducedEffects then item.Id else Cosmetics.Default.TakenEffect
		local visual = Instance.new("Folder")
		visual.Parent = effects
		local pose = character:GetPivot()
		local tween = TweenInfo.new(EFFECT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "HumanoidRootPart" then
				local copy = createPart(visual, part.Size, part.CFrame, part.Color)
				copy.Transparency = math.max(0.24, part.Transparency)
				local offset = if effect == "Hands" then Vector3.new(0, -4, 0)
					elseif effect == "Ceiling" then Vector3.new(0, 6, 0)
					else Vector3.new(0, 0.6, 0)
				TweenService:Create(copy, tween, { CFrame = copy.CFrame + offset, Transparency = 1 }):Play()
			end
		end
		if effect == "Hands" then
			for _, side in { -1, 1 } do
				local angle = side * -0.35
				local handPose = pose * CFrame.new(side * 0.9, -1.9, 0) * CFrame.Angles(0, 0, angle)
				for index = 0, 4 do
					local size = if index == 0 then Vector3.new(0.44, 0.83, 0.28) else Vector3.new(0.09, 0.34, 0.12)
					local placement = if index == 0 then CFrame.identity else CFrame.new((index - 2.5) * 0.11, 0.53, 0)
					local hand = createPart(visual, size, handPose * placement, Color3.fromRGB(14, 11, 18))
					TweenService:Create(hand, tween, { CFrame = hand.CFrame + Vector3.new(0, -2.5, 0), Transparency = 1 }):Play()
				end
			end
		elseif effect == "Ash" then
			for index = 1, 12 do
				local angle = index * 2.4
				local spark = createPart(visual, Vector3.one * 0.14, pose + Vector3.new(math.cos(angle), index / 5 - 1, math.sin(angle)),
					Color3.fromRGB(172, 135, 112))
				spark.Material = Enum.Material.Neon
				TweenService:Create(spark, tween, { CFrame = spark.CFrame + Vector3.new(math.cos(angle), 1.4, math.sin(angle)), Transparency = 1 }):Play()
			end
		end
		task.delay(EFFECT_TIME, function() visual:Destroy() end)
	end)
	Remotes.Event("RoundState").OnClientEvent:Connect(function(state: string)
		if state ~= "Running" then effects:ClearAllChildren() end
	end)
end

return Controller
