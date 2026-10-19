--!strict
-- ReplicatedStorage > JutsuSystem > Shared > ClientBurst
--
-- ParticleEmitter:Emit() llamado en el SERVIDOR no se ve en los clientes.
-- Con este módulo el servidor solo "pide" la ráfaga y cada cliente la emite.
--
-- Servidor:   ClientBurst.Emit(emitter, cantidad)
-- Cliente:    ClientBurst.Listen()   (lo llama JutsuVFXController una vez)

local CollectionService =
	game:GetService("CollectionService")

local TAG =
	"JutsuClientBurst"

local ClientBurst = {}

function ClientBurst.Emit(
	emitter: ParticleEmitter,
	count: number
)
	emitter:SetAttribute(
		"EmitCount",
		math.max(1, math.floor(count))
	)

	-- Cada pedido cambia el contador, así se puede emitir varias veces
	local nonce =
		emitter:GetAttribute("BurstNonce")

	emitter:SetAttribute(
		"BurstNonce",
		(if typeof(nonce) == "number" then nonce else 0) + 1
	)

	CollectionService:AddTag(
		emitter,
		TAG
	)
end

local listening =
	false

function ClientBurst.Listen()
	if listening then
		return
	end

	listening =
		true

	local function burst(
		emitter: Instance
	)
		if not emitter:IsA("ParticleEmitter") then
			return
		end

		local count =
			emitter:GetAttribute("EmitCount")

		if typeof(count) == "number"
			and count > 0 then

			emitter:Emit(
				count
			)
		end
	end

	local function track(
		emitter: Instance
	)
		burst(emitter)

		emitter:GetAttributeChangedSignal("BurstNonce"):Connect(function()
			burst(emitter)
		end)
	end

	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)

	-- Los que ya existen (por ejemplo, al entrar al juego) no se emiten:
	-- su ráfaga ya pasó. Solo se escuchan pedidos nuevos.
	for _, emitter in CollectionService:GetTagged(TAG) do
		emitter:GetAttributeChangedSignal("BurstNonce"):Connect(function()
			burst(emitter)
		end)
	end
end

return ClientBurst
