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
local REFUND_RETRY_INTERVAL = 2 ^ MAX_ATTEMPTS

type Ledger = { [string]: boolean | string }
type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string }

-- В одной записи чек одновременно служит купленным зарядом.
local amulets = if Config.PRODUCT_AMULET > 0 then DataStoreService:GetDataStore(Config.DATASTORE_NAME .. "_Amulets") else nil
local revives = if Config.PRODUCT_REVIVE > 0 then DataStoreService:GetDataStore(Config.DATASTORE_NAME .. "_Revives") else nil
local vipOwners: { [Player]: boolean } = {}
local consuming: { [Player]: boolean } = {}
local reviveBusy: { [number]: boolean } = {}
local nextReviveAt: { [Player]: number } = {}
type GhostService = {
	IsGhost: (any, Player) -> boolean,
	Revive: (any, Player) -> boolean,
	GetRevivesLeft: ((any) -> number)?,
}
local ghosts: GhostService? = nil

local function updateLedger(store: GlobalDataStore?, userId: number, transform: (Ledger) -> Ledger?): Ledger?
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
			warn(`[MonetizationService] Не удалось сохранить покупку: {result}`)
		end
	end
	return nil
end

local function publishRevives(player: Player, ledger: Ledger)
	if player.Parent ~= Players then return end
	local count = 0
	for _, state in ledger do
		if state == true then count += 1 end
	end
	player:SetAttribute("ReviveCredits", count)
end

local function refundRevive(userId: number, receiptId: string, useId: string): Ledger?
	return updateLedger(revives, userId, function(current)
		-- Повтор после потерянного ответа не должен отменить более позднее списание.
		if current[receiptId] == useId then
			current[receiptId] = true
		end
		return current
	end)
end

local function retryReviveRefund(userId: number, receiptId: string, useId: string)
	task.delay(REFUND_RETRY_INTERVAL, function()
		if reviveBusy[userId] then
			retryReviveRefund(userId, receiptId, useId)
			return
		end
		reviveBusy[userId] = true
		local ledger = refundRevive(userId, receiptId, useId)
		reviveBusy[userId] = nil
		if not ledger then
			retryReviveRefund(userId, receiptId, useId)
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then publishRevives(player, ledger) end
	end)
end

local function getReceiptDecision(receipt: Receipt): Enum.ProductPurchaseDecision
	local userId = receipt.PlayerId
	local isRevive = receipt.ProductId == Config.PRODUCT_REVIVE and revives ~= nil
	local store = if isRevive then revives elseif receipt.ProductId == Config.PRODUCT_AMULET then amulets else nil
	if not store or type(receipt.PurchaseId) ~= "string"
		or receipt.PurchaseId == "" or type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0
	then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if isRevive and reviveBusy[userId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if isRevive then reviveBusy[userId] = true end

	local receiptId = receipt.PurchaseId
	local added = false
	local ledger = updateLedger(store, userId, function(current)
		-- UpdateAsync может вызвать функцию повторно при записи с другого сервера.
		added = current[receiptId] == nil
		if added then
			current[receiptId] = true
		end
		return current
	end)
	if isRevive then
		local online = Players:GetPlayerByUserId(userId)
		if ledger and online then publishRevives(online, ledger) end
		reviveBusy[userId] = nil
	end
	local status = if ledger then ledger[receiptId] else nil
	if status ~= true and type(status) ~= "string" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if isRevive and status == true then
		task.spawn(function()
			MonetizationService:RedeemRevive(player, receiptId)
		end)
	end
	if added and not isRevive and player.Parent == Players then
		notify:FireClient(player, "notify.amulet_added", "Good")
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
	if revives and player.UserId > 0 then
		task.spawn(function()
			local userId = player.UserId
			if reviveBusy[userId] then return end
			reviveBusy[userId] = true
			local ledger = updateLedger(revives, userId, function(current) return current end)
			local online = Players:GetPlayerByUserId(userId)
			if ledger and online then publishRevives(online, ledger) end
			reviveBusy[userId] = nil
		end)
	end
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
	local ledger = updateLedger(amulets, player.UserId, function(current)
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

function MonetizationService:RedeemRevive(player: Player, preferredReceipt: string?): boolean
	local service = ghosts
	local userId = player.UserId
	if not service or not revives or player.Parent ~= Players or userId <= 0 or reviveBusy[userId] or not service:IsGhost(player) then
		return false
	end
	reviveBusy[userId] = true
	local useId = HttpService:GenerateGUID(false)
	local selected: string? = nil
	local ledger = updateLedger(revives, userId, function(current)
		selected = nil
		for receiptId, state in current do
			if state == useId or (state == true and (preferredReceipt == nil or receiptId == preferredReceipt)) then
				selected = receiptId
				current[receiptId] = useId
				break
			end
		end
		return current
	end)
	local receiptId = selected
	local restored = false
	if ledger and receiptId and ledger[receiptId] == useId then
		local ok, result = pcall(service.Revive, service, player)
		restored = ok and result == true
		if not restored then
			local refunded = refundRevive(userId, receiptId, useId)
			if refunded then
				ledger = refunded
			else
				retryReviveRefund(userId, receiptId, useId)
			end
		end
	end
	local online = Players:GetPlayerByUserId(userId)
	if ledger and online then publishRevives(online, ledger) end
	reviveBusy[userId] = nil
	return restored
end

function MonetizationService:Init(services: { [string]: any })
	ghosts = services.GhostService
	MarketplaceService.ProcessReceipt = getReceiptDecision
	-- Бесплатное возвращение выполняет GhostService. Здесь тратим сохранённый заряд,
	-- только когда V04 сообщает, что бесплатных больше нет.
	Remotes.Event("ReviveRequest").OnServerEvent:Connect(function(player: Player)
		local service = ghosts
		local getRevivesLeft = if service then service.GetRevivesLeft else nil
		local now = os.clock()
		if service and getRevivesLeft and getRevivesLeft(service) == 0 and now >= (nextReviveAt[player] or 0) then
			nextReviveAt[player] = now + 1
			self:RedeemRevive(player)
		end
	end)
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
		nextReviveAt[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		loadPasses(player)
	end
end

return MonetizationService
