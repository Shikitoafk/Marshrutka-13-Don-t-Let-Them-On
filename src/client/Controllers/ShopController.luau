--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Strings"))

local ShopController = {}

local PANEL = Color3.fromRGB(21, 28, 39)
local ROW = Color3.fromRGB(32, 43, 58)
local TEXT = Color3.fromRGB(250, 244, 231)
local MUTED = Color3.fromRGB(198, 210, 225)
local AMBER = Color3.fromRGB(246, 198, 110)

type Offer = { name: string, benefit: string, id: number, pass: boolean, attribute: string? }
local OFFERS: { Offer } = {
	{ name = Strings.get("shop.vip"), benefit = Strings.get("shop.vip_benefit"), id = Config.GAMEPASS_VIP, pass = true, attribute = "VIPBusSkin" },
	{ name = Strings.get("shop.radio"), benefit = Strings.get("shop.radio_benefit"), id = Config.GAMEPASS_RADIO, pass = true, attribute = "HasRadio" },
	{ name = Strings.get("shop.amulet"), benefit = Strings.get("shop.amulet_benefit", { health = Config.AMULET_RESTORE_HEALTH }), id = Config.PRODUCT_AMULET, pass = false },
}

local function roundCorners(gui: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = gui
end

local function limitText(gui: GuiObject, minSize: number, maxSize: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = minSize
	limit.MaxTextSize = maxSize
	limit.Parent = gui
end

local function label(parent: Instance, text: string, position: UDim2, size: UDim2, minSize: number, maxSize: number): TextLabel
	local gui = Instance.new("TextLabel")
	gui.Text = text
	gui.Position = position
	gui.Size = size
	gui.BackgroundTransparency = 1
	gui.TextColor3 = TEXT
	gui.TextXAlignment = Enum.TextXAlignment.Left
	gui.TextScaled = true
	gui.TextWrapped = true
	gui.Font = Enum.Font.GothamMedium
	limitText(gui, minSize, maxSize)
	gui.Parent = parent
	return gui
end

local function button(parent: Instance, text: string, position: UDim2, size: UDim2): TextButton
	local gui = Instance.new("TextButton")
	gui.Text = text
	gui.Position = position
	gui.Size = size
	gui.BorderSizePixel = 0
	gui.BackgroundColor3 = AMBER
	gui.TextColor3 = PANEL
	gui.TextScaled = true
	gui.Font = Enum.Font.GothamBold
	limitText(gui, 14, 21)
	roundCorners(gui)
	gui.Parent = parent
	return gui
end

local function clampSize(gui: GuiObject, minSize: Vector2, maxSize: Vector2)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = minSize
	constraint.MaxSize = maxSize
	constraint.Parent = gui
end

local function findRadio(): (Sound?, BasePart?)
	local map = Workspace:FindFirstChild("Map")
	local bus = if map then map:FindFirstChild("Bus") else nil
	if not bus or not bus:IsA("Model") then
		return nil, nil
	end
	local radio = bus:FindFirstChild("Radio", true)
	return if radio and radio:IsA("Sound") and radio.SoundId ~= "" and radio.SoundId ~= "rbxassetid://0" then radio else nil, bus.PrimaryPart
end

function ShopController:Init(_controllers: { [string]: any }) end

function ShopController:Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.AutoLocalize = false
	screen.Name = "DepotShop"
	screen.DisplayOrder = 4
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ResetOnSpawn = false
	screen.Parent = playerGui

	local open = button(screen, Strings.get("shop.title"), UDim2.fromScale(0.97, 0.035), UDim2.fromScale(0.3, 0.13))
	open.Name = "OpenShop"
	open.AnchorPoint = Vector2.new(1, 0)
	clampSize(open, Vector2.new(106, 48), Vector2.new(174, 60))

	local shade = Instance.new("Frame")
	shade.Name = "ShopWindow"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new()
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.Active = true
	shade.Visible = false
	shade.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.95, 0.94)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	clampSize(panel, Vector2.zero, Vector2.new(505, 386))
	roundCorners(panel)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.29
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = panel
	panel.Parent = shade

	local title = label(panel, Strings.get("shop.title"), UDim2.fromScale(0.055, 0.025), UDim2.fromScale(0.89, 0.12), 19, 29)
	title.Font = Enum.Font.GothamBold
	local close = button(panel, Strings.get("ui.close"), UDim2.fromScale(0.7, 0.97), UDim2.fromScale(0.25, 0.16))
	close.Name = "CloseShop"
	close.AnchorPoint = Vector2.new(0, 1)
	clampSize(close, Vector2.new(0, 46), Vector2.new(math.huge, math.huge))
	local status = label(panel, "", UDim2.fromScale(0.055, 0.77), UDim2.fromScale(0.61, 0.21), 14, 17)
	status.TextColor3 = MUTED
	status.TextWrapped = true
	title.Size = UDim2.fromScale(0.48, 0.12)
	local tab = button(panel, Strings.get("cosmetics.tab"), UDim2.fromScale(0.55, 0.025), UDim2.fromScale(0.4, 0.13))
	clampSize(tab, Vector2.new(0, 44), Vector2.new(math.huge, math.huge))
	local offersPage = Instance.new("Frame")
	offersPage.Size = UDim2.fromScale(1, 1)
	offersPage.BackgroundTransparency = 1
	offersPage.Parent = panel
	local cosmeticsPage = offersPage:Clone()
	cosmeticsPage.Visible = false
	cosmeticsPage.Parent = panel
	local categoryButton = button(cosmeticsPage, "", UDim2.fromScale(0.05, 0.21), UDim2.fromScale(0.9, 0.14))
	clampSize(categoryButton, Vector2.new(0, 44), Vector2.new(math.huge, math.huge))
	local catalog = Instance.new("ScrollingFrame")
	catalog.Position = UDim2.fromScale(0.05, 0.43)
	catalog.Size = UDim2.fromScale(0.43, 0.34)
	catalog.AutomaticCanvasSize = Enum.AutomaticSize.Y
	catalog.CanvasSize = UDim2.fromScale(0, 0)
	catalog.BackgroundTransparency = 1
	catalog.BorderSizePixel = 0
	catalog.ScrollBarThickness = 4
	catalog.Parent = cosmeticsPage
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.Parent = catalog
	local preview = Instance.new("Frame")
	preview.Position = UDim2.fromScale(0.52, 0.43)
	preview.Size = UDim2.fromScale(0.43, 0.33)
	preview.BackgroundColor3 = ROW
	preview.BorderSizePixel = 0
	preview.ClipsDescendants = true
	roundCorners(preview)
	preview.Parent = cosmeticsPage
	local buy = button(cosmeticsPage, "", UDim2.fromScale(0.05, 0.97), UDim2.fromScale(0.59, 0.16))
	buy.AnchorPoint = Vector2.new(0, 1)
	clampSize(buy, Vector2.new(0, 44), Vector2.new(math.huge, math.huge))
	status.Position = UDim2.fromScale(0.055, 0.76)
	status.Size = UDim2.fromScale(0.61, 0.06)
	local category: Cosmetics.Category = "Flashlight"
	local item: Cosmetics.Item? = nil
	local owned: { [string]: boolean } = {}
	local busy = false
	local passPrompt: number? = nil
	local actionAvailable, actionRemote = pcall(Remotes.Function, "CosmeticAction")
	local refreshVersion = 0

	local function updateBuy()
		local selected = item
		if not selected then
			buy.Visible = false
			return
		end
		local equipped = player:GetAttribute("Equipped" .. category) or Cosmetics.Default[category]
		local hasItem = owned[selected.Id] or selected.Id == Cosmetics.Default[category]
		buy.Visible = true
		buy.Interactable = actionAvailable and not busy and not passPrompt and equipped ~= selected.Id
		buy.Text = if equipped == selected.Id then Strings.get("cosmetics.equipped")
			elseif hasItem then Strings.get("cosmetics.equip")
			elseif selected.GamepassId then Strings.get("cosmetics.robux")
			else Strings.get("cosmetics.price", { price = selected.Price })
	end

	local function refreshProfile()
		refreshVersion += 1
		local version = refreshVersion
		task.spawn(function()
			local ok, snapshot = pcall(function() return Remotes.Function("GetProfile"):InvokeServer() end)
			if version == refreshVersion and ok and type(snapshot) == "table" and type(snapshot.OwnedCosmetics) == "table" then
				owned = snapshot.OwnedCosmetics
				updateBuy()
			end
		end)
	end

	local function selectItem(selected: Cosmetics.Item)
		item = selected
		preview:ClearAllChildren()
		roundCorners(preview)
		if category == "Flashlight" then
			local beams: { [string]: { color: Color3, angle: number } } = Cosmetics.Beams
			local style = beams[selected.Id] or beams.Classic
			local beam = Instance.new("Frame")
			beam.AnchorPoint = Vector2.new(0, 0.5)
			beam.Position = UDim2.fromScale(0.12, 0.5)
			beam.Size = UDim2.fromScale(0.8, style.angle / 55)
			beam.BackgroundColor3 = style.color
			beam.BorderSizePixel = 0
			roundCorners(beam)
			beam.Parent = preview
			local gradient = Instance.new("UIGradient")
			gradient.Transparency = NumberSequence.new(0.16, 1)
			gradient.Parent = beam
		else
			local silhouette = label(preview, "●\n▮", UDim2.fromScale(0.25, 0.08), UDim2.fromScale(0.5, 0.8), 15, 24)
			silhouette.TextXAlignment = Enum.TextXAlignment.Center
			silhouette.TextColor3 = if selected.Id == "Hands" then Color3.new() else MUTED
			local y = if selected.Id == "Ceiling" then -0.65 elseif selected.Id == "Hands" then 0.95 else 0.08
			TweenService:Create(silhouette, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0.2),
				{ Position = UDim2.fromScale(0.25, y), TextTransparency = 1 }):Play()
		end
		updateBuy()
	end

	local function populateCosmetics()
		categoryButton.Text = Strings.get(if category == "Flashlight" then "cosmetics.flashlights" else "cosmetics.effects")
		for _, child in catalog:GetChildren() do
			if child:IsA("TextButton") then child:Destroy() end
		end
		catalog.CanvasPosition = Vector2.zero
		item = nil
		for _, entry in Cosmetics.list(category) do
			if entry.GamepassId ~= 0 then
				local row = button(catalog, Strings.get("cosmetics." .. entry.Id), UDim2.fromScale(0, 0), UDim2.new(0.95, 0, 0, 46))
				row.TextWrapped = true
				row.Activated:Connect(function() selectItem(entry) end)
				if not item then selectItem(entry) end
			end
		end
		updateBuy()
	end

	local function requestCosmetic(action: string, selectedCategory: Cosmetics.Category, selected: Cosmetics.Item)
		if not actionAvailable or busy then return end
		busy = true
		updateBuy()
		local ok, success, key = pcall(function() return actionRemote:InvokeServer(action, selectedCategory, selected.Id) end)
		busy = false
		if ok and success then owned[selected.Id] = true end
		status.Text = Strings.get(if ok and type(key) == "string" then key else "shop.unavailable")
		updateBuy()
		refreshProfile()
	end

	categoryButton.Activated:Connect(function()
		category = if category == "Flashlight" then "TakenEffect" else "Flashlight"
		populateCosmetics()
	end)
	tab.Activated:Connect(function()
		cosmeticsPage.Visible = not cosmeticsPage.Visible
		offersPage.Visible = not cosmeticsPage.Visible
		tab.Text = Strings.get(if cosmeticsPage.Visible then "shop.title" else "cosmetics.tab")
		status.Text = ""
		if cosmeticsPage.Visible then
			populateCosmetics()
			refreshProfile()
		end
	end)
	buy.Activated:Connect(function()
		local selected = item
		if not selected or not buy.Interactable or not cosmeticsPage.Visible then return end
		local pass = selected.GamepassId
		if owned[selected.Id] or not pass then
			requestCosmetic(if owned[selected.Id] then "Equip" else "Buy", category, selected)
		elseif pass > 0 then
			passPrompt = pass
			updateBuy()
			local ok = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass)
			if not ok then
				passPrompt = nil
				status.Text = Strings.get("shop.purchase_failed")
				updateBuy()
			end
		end
	end)
	for _, slot in { "EquippedFlashlight", "EquippedTakenEffect" } do
		player:GetAttributeChangedSignal(slot):Connect(updateBuy)
	end

	local actions: { [Offer]: TextButton } = {}
	local pending: Offer? = nil
	local radioSound: Sound? = nil

	local function refreshOffers()
		for offer, action in actions do
			local attribute = offer.attribute
			local owned = attribute ~= nil and player:GetAttribute(attribute) == true
			local enabled = offer.id > 0 and pending == nil and (not owned or attribute == "HasRadio")
			if offer.id <= 0 then
				action.Text = Strings.get("shop.unavailable")
			elseif owned and attribute == "HasRadio" then
				action.Text = Strings.get(if radioSound and radioSound.Parent then "shop.turn_off" else "shop.turn_on")
			elseif owned then
				action.Text = Strings.get("shop.owned")
			elseif pending == offer then
				action.Text = Strings.get("shop.purchasing")
			else
				action.Text = Strings.get("shop.buy")
			end
			action.Interactable = enabled
			action.BackgroundColor3 = if enabled then AMBER else PANEL
			action.TextColor3 = if enabled then PANEL else MUTED
		end
	end

	local function toggleRadio()
		local playing = radioSound
		if playing and playing.Parent then
			playing:Destroy()
			radioSound = nil
			return
		end
		local source, busRoot = findRadio()
		if not source then
			status.Text = Strings.get("shop.music_missing")
			return
		end
		local copy = source:Clone()
		if not copy then
			status.Text = Strings.get("shop.radio_unavailable")
			return
		end
		copy.Name = "LocalPersonalRadio"
		copy.Looped = true
		copy.Parent = busRoot or source.Parent
		copy:Play()
		radioSound = copy
	end

	local function activate(offer: Offer)
		if offer.id <= 0 or pending or not shade.Visible or not screen.Enabled then
			return
		end
		status.Text = ""
		local attribute = offer.attribute
		if attribute and player:GetAttribute(attribute) == true then
			if attribute == "HasRadio" then
				toggleRadio()
				refreshOffers()
			end
			return
		end
		pending = offer
		refreshOffers()
		local ok = pcall(function()
			if offer.pass then
				MarketplaceService:PromptGamePassPurchase(player, offer.id)
			else
				MarketplaceService:PromptProductPurchase(player, offer.id)
			end
		end)
		if not ok then
			pending = nil
			status.Text = Strings.get("shop.purchase_failed")
			refreshOffers()
		end
	end

	for index, offer in OFFERS do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromScale(0.05, 0.21 + (index - 1) * 0.184)
		row.Size = UDim2.fromScale(0.9, 0.174)
		row.BackgroundColor3 = ROW
		row.BorderSizePixel = 0
		roundCorners(row)
		row.Parent = offersPage
		local name = label(row, offer.name, UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.57, 0.39), 15, 21)
		name.Font = Enum.Font.GothamBold
		local benefit = label(row, offer.benefit, UDim2.fromScale(0.04, 0.45), UDim2.fromScale(0.57, 0.52), 13, 17)
		benefit.TextColor3 = MUTED
		local action = button(row, "", UDim2.fromScale(0.97, 0.5), UDim2.fromScale(0.34, 0.9))
		action.Name = if offer.attribute then offer.attribute else "Amulet"
		action.AnchorPoint = Vector2.new(1, 0.5)
		clampSize(action, Vector2.new(0, 44), Vector2.new(math.huge, 56))
		actions[offer] = action
		action.Activated:Connect(function()
			activate(offer)
		end)
	end

	open.Activated:Connect(function()
		status.Text = ""
		shade.Visible = true
		open.Visible = false
		refreshOffers()
		if cosmeticsPage.Visible then refreshProfile() end
	end)
	close.Activated:Connect(function()
		shade.Visible = false
		open.Visible = true
	end)

	local function finishPrompt(id: number, pass: boolean)
		local offer = pending
		if offer and offer.id == id and offer.pass == pass then
			pending = nil
			refreshOffers()
		end
	end

	-- Клиентские события только разблокируют кнопки после закрытия окна Roblox.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(buyer, id, purchased)
		if buyer == player then
			finishPrompt(id, true)
			if passPrompt == id then
				passPrompt = nil
				local selected = item
				if purchased then
					for _, slot: Cosmetics.Category in Cosmetics.Categories do
						for _, entry in Cosmetics.list(slot) do
							if entry.GamepassId == id then requestCosmetic("Buy", slot, entry) end
						end
					end
				end
				if selected == item then updateBuy() end
			end
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id)
		if userId == player.UserId then
			finishPrompt(id, false)
		end
	end)
	player:GetAttributeChangedSignal("VIPBusSkin"):Connect(refreshOffers)
	player:GetAttributeChangedSignal("HasRadio"):Connect(refreshOffers)
	refreshOffers()

	local function applyRoundState(state: string)
		screen.Enabled = state == "Lobby" or state == "Countdown"
		if not screen.Enabled then
			shade.Visible = false
			open.Visible = true
		end
	end
	if RunService:IsStudio() and Workspace:GetAttribute("StudioHudLobbyPreview") == true then
		local roundPreview = playerGui:WaitForChild("StudioRoundPreview") :: BindableEvent
		roundPreview.Event:Connect(applyRoundState)
	else
		Remotes.Event("RoundState").OnClientEvent:Connect(applyRoundState)
	end
end

return ShopController
