--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MonetizationService = {}
local notify = Remotes.Event("Notify")
local MAX_ATTEMPTS = 4

type Ledger = { [string]: boolean | string }
type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string }

-- В одной записи чек одновременно служит купленным зарядом.
local amulets = if Config.PRODUCT_AMULET > 0 then DataStoreService:GetDataStore(Config.DATASTORE_NAME .. "_Amulets") else nil
local vipOwners: { [Player]: boolean } = {}
local consuming: { [Player]: boolean } = {}

local function updateAmulets(userId: number, transform: (Ledger) -> Ledger?): Ledger?
	local store = amulets
	if not store then
		return nil
	end
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(function()
			return store:UpdateAsync(tostring(userId), function(current): (Ledger?, { number }?)
				if current ~= nil and type(current) ~= "table" then
					return nil, nil
				end
				local ledger = transform(current or {})
				if ledger then
					return ledger, { userId }
				end
				return nil, nil
			end)
		end)
		if ok then
			return result
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		else
			warn(`[MonetizationService] Не удалось сохранить Оберег: {result}`)
		end
	end
	return nil
end

local function getReceiptDecision(receipt: Receipt): Enum.ProductPurchaseDecision
	local userId = receipt.PlayerId
	if not amulets or receipt.ProductId ~= Config.PRODUCT_AMULET or type(receipt.PurchaseId) ~= "string"
		or receipt.PurchaseId == "" or type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0
	then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = receipt.PurchaseId
	local added = false
	local ledger = updateAmulets(userId, function(current)
		-- UpdateAsync может вызвать функцию повторно при записи с другого сервера.
		added = current[receiptId] == nil
		if added then
			current[receiptId] = true
		end
		return current
	end)
	local status = if ledger then ledger[receiptId] else nil
	if status ~= true and type(status) ~= "string" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if added and player.Parent == Players then
		notify:FireClient(player, "Оберег добавлен.", "Good")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function markPassOwned(player: Player, id: number)
	if player.Parent ~= Players then
		return
	end
	if id > 0 and id == Config.GAMEPASS_VIP then
		vipOwners[player] = true
		player:SetAttribute("VIPBusSkin", true)
	end
	if id > 0 and id == Config.GAMEPASS_RADIO then
		player:SetAttribute("HasRadio", true)
	end
end

local function checkPass(player: Player, id: number)
	if id <= 0 then
		return
	end
	local ok, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	if ok then
		if owned then
			markPassOwned(player, id)
		end
	else
		warn(`[MonetizationService] Не удалось проверить геймпасс {id}: {owned}`)
	end
end

local function loadPasses(player: Player)
	task.spawn(checkPass, player, Config.GAMEPASS_VIP)
	task.spawn(checkPass, player, Config.GAMEPASS_RADIO)
end

function MonetizationService:HasVIP(player: Player): boolean
	return vipOwners[player] == true
end

function MonetizationService:ConsumeAmulet(player: Player): boolean
	if not amulets or player.Parent ~= Players or player.UserId <= 0 or consuming[player] then
		return false
	end
	consuming[player] = true
	local useId = HttpService:GenerateGUID(false)
	local ledger = updateAmulets(player.UserId, function(current)
		local available: string? = nil
		for receiptId, state in current do
			if state == useId then
				return current
			elseif state == true then
				available = receiptId
			end
		end
		if available then
			current[available] = useId
			return current
		end
		return nil
	end)
	consuming[player] = nil
	if ledger then
		for _, state in ledger do
			if state == useId then
				return true
			end
		end
	end
	return false
end

function MonetizationService:Init(_services: { [string]: any })
	MarketplaceService.ProcessReceipt = getReceiptDecision
end

function MonetizationService:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, purchased)
		if purchased and player:IsA("Player") then
			markPassOwned(player, id)
		end
	end)
	Players.PlayerAdded:Connect(loadPasses)
	Players.PlayerRemoving:Connect(function(player)
		vipOwners[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		loadPasses(player)
	end
end

return MonetizationService
