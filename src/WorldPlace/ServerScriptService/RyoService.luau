--!strict
-- RyoService v1 - Server Authoritative Currency
-- ServerScriptService > RyoService [ModuleScript]
--
-- Canonical player currency:
-- Player attribute "Ryo"
--
-- Mission/shop/etc. systems should mutate Ryō ONLY through this service.
--
-- NOTE:
-- This v1 does not include DataStore persistence yet.
-- The attribute survives character respawns because it lives on Player,
-- but resets when the player leaves/rejoins the server.

local Players =
	game:GetService(
		"Players"
	)


local RyoService = {}


local ATTRIBUTE_NAME =
	"Ryo"

local DEFAULT_STARTING_RYO =
	0

local MAX_RYO =
	999999999


local function sanitizeAmount(
	value: any
): number

	if typeof(value) ~= "number" then
		return 0
	end


	if value ~= value
		or value == math.huge
		or value == -math.huge then

		return 0
	end


	return math.clamp(
		math.floor(
			value
		),
		0,
		MAX_RYO
	)
end


function RyoService.InitializePlayer(
	player: Player
)

	local existing =
		player:GetAttribute(
			ATTRIBUTE_NAME
		)


	if typeof(existing) == "number" then

		player:SetAttribute(
			ATTRIBUTE_NAME,
			sanitizeAmount(
				existing
			)
		)


		return
	end


	player:SetAttribute(
		ATTRIBUTE_NAME,
		DEFAULT_STARTING_RYO
	)
end


function RyoService.Get(
	player: Player
): number

	local value =
		player:GetAttribute(
			ATTRIBUTE_NAME
		)


	return sanitizeAmount(
		value
	)
end


function RyoService.Set(
	player: Player,
	amount: number,
	_reason: string?
): (boolean, number, string)

	local finalAmount =
		sanitizeAmount(
			amount
		)


	player:SetAttribute(
		ATTRIBUTE_NAME,
		finalAmount
	)


	return true,
		finalAmount,
		"OK"
end


function RyoService.Add(
	player: Player,
	amount: number,
	reason: string?
): (boolean, number, string)

	if typeof(amount) ~= "number"
		or amount <= 0 then

		return false,
			RyoService.Get(
				player
			),
			"invalid amount"
	end


	local current =
		RyoService.Get(
			player
		)


	local finalAmount =
		math.clamp(
			current
			+ math.floor(
				amount
			),
			0,
			MAX_RYO
		)


	player:SetAttribute(
		ATTRIBUTE_NAME,
		finalAmount
	)


	if reason then

		print(
			"[RyoService] ADD",
			player.Name,
			math.floor(
				amount
			),
			"reason=",
			reason,
			"balance=",
			finalAmount
		)
	end


	return true,
		finalAmount,
		"OK"
end


function RyoService.CanAfford(
	player: Player,
	amount: number
): boolean

	if typeof(amount) ~= "number"
		or amount < 0 then

		return false
	end


	return RyoService.Get(
		player
	) >= math.floor(
		amount
	)
end


function RyoService.Spend(
	player: Player,
	amount: number,
	reason: string?
): (boolean, number, string)

	if typeof(amount) ~= "number"
		or amount <= 0 then

		return false,
			RyoService.Get(
				player
			),
			"invalid amount"
	end


	local spendAmount =
		math.floor(
			amount
		)


	local current =
		RyoService.Get(
			player
		)


	if current <
		spendAmount then

		return false,
			current,
			"not enough Ryo"
	end


	local finalAmount =
		current
	- spendAmount


	player:SetAttribute(
		ATTRIBUTE_NAME,
		finalAmount
	)


	if reason then

		print(
			"[RyoService] SPEND",
			player.Name,
			spendAmount,
			"reason=",
			reason,
			"balance=",
			finalAmount
		)
	end


	return true,
		finalAmount,
		"OK"
end


Players.PlayerAdded:
	Connect(
		function(
			player: Player
		)

			RyoService.InitializePlayer(
				player
			)
		end
	)


for _,
	player in ipairs(
		Players:GetPlayers()
	) do

	RyoService.InitializePlayer(
		player
	)
end


print(
	"[RyoService] READY v1"
		.. " | Attribute=Ryo"
		.. " | ServerAuthoritative=ON"
		.. " | Persistence=OFF"
)


return RyoService
