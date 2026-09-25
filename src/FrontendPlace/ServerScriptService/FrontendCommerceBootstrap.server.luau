--!strict
-- ServerScriptService > FrontendCommerceBootstrap
-- WAYLESS Developer Product receipt router v1.
--
-- Current product:
--   Buy Character Slot -> AccountProfileService.GrantPurchasedSlotReceipt
--
-- SECURITY / RELIABILITY:
--   * The client only opens Roblox's purchase prompt. It never grants a slot.
--   * ProcessReceipt is the sole authority for granting the purchased slot.
--   * Receipt idempotency is stored atomically in the AccountProfile itself.
--   * Unknown products are NOT acknowledged; they return NotProcessedYet.
--   * If the player's account profile is not ready, Roblox is asked to retry.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CommerceConfig = require(Shared:WaitForChild("FrontendCommerceConfig"))

local Services = ServerScriptService:WaitForChild("Services")
local AccountProfileService = require(Services:WaitForChild("AccountProfileService"))

local PRODUCT_BUY_CHARACTER_SLOT = tonumber(CommerceConfig.BuyCharacterSlotProductId) or 0

local function ensureCommerceEvent(): RemoteEvent
	local system = ReplicatedStorage:FindFirstChild("FrontendSystem")
	if not system then
		system = Instance.new("Folder")
		system.Name = "FrontendSystem"
		system.Parent = ReplicatedStorage
	end

	local remotes = system:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = system
	end

	local existing = remotes:FindFirstChild("FrontendCommerceUpdated")
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local event = Instance.new("RemoteEvent")
	event.Name = "FrontendCommerceUpdated"
	event.Parent = remotes
	return event
end

local commerceUpdated = ensureCommerceEvent()

local function processCharacterSlotReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local playerId = tonumber(receiptInfo.PlayerId)
	local purchaseId = tostring(receiptInfo.PurchaseId or "")
	local productId = tonumber(receiptInfo.ProductId) or 0

	if not playerId or purchaseId == "" then
		warn("[FrontendCommerce] INVALID RECEIPT", receiptInfo)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	AccountProfileService.Start()
	if not AccountProfileService.IsReady(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, reason, slotId = AccountProfileService.GrantPurchasedSlotReceipt(
		player,
		purchaseId,
		productId
	)

	if not ok then
		warn(
			"[FrontendCommerce] SLOT RECEIPT RETRY",
			player.Name,
			"Purchase=" .. purchaseId,
			"Reason=" .. tostring(reason)
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	commerceUpdated:FireClient(player, {
		Kind = "CharacterSlotPurchased",
		ProductId = productId,
		SlotId = slotId,
		Reason = reason,
	})

	print(
		"[FrontendCommerce] SLOT PURCHASE GRANTED",
		player.Name,
		"Slot=" .. tostring(slotId),
		"Receipt=" .. purchaseId,
		"Reason=" .. tostring(reason)
	)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = function(receiptInfo: any): Enum.ProductPurchaseDecision
	local productId = tonumber(receiptInfo.ProductId) or 0

	if PRODUCT_BUY_CHARACTER_SLOT > 0 and productId == PRODUCT_BUY_CHARACTER_SLOT then
		return processCharacterSlotReceipt(receiptInfo)
	end

	warn(
		"[FrontendCommerce] UNHANDLED PRODUCT",
		"ProductId=" .. tostring(productId),
		"PurchaseId=" .. tostring(receiptInfo.PurchaseId)
	)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

if PRODUCT_BUY_CHARACTER_SLOT <= 0 then
	warn("[FrontendCommerce] READY v1 | BuyCharacterSlotProductId=0 | purchases disabled until configured")
else
	print(
		"[FrontendCommerce] READY v1 | BuyCharacterSlotProductId=" .. tostring(PRODUCT_BUY_CHARACTER_SLOT)
			.. " | ReceiptIdempotency=ACCOUNT_ATOMIC"
	)
end
