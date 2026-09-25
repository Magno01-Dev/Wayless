-- WaterSoundController
--
-- StarterPlayer > StarterCharacterScripts
--
-- Evita el sonido de sumergirse cuando:
--   - estamos caminando SOBRE el agua con Chakra Feet
--   - saltamos DESDE Water Walk
--
-- No modifica fisica, animaciones ni estados del Humanoid.
--
-- Si Chakra Feet se desactiva y el personaje realmente se sumerge,
-- WaterWalking / WaterJumping son false y el sonido se reproduce normal.

local character = script.Parent

local connectedSounds = {}


-- =========================
-- STATE
-- =========================

local function shouldSuppressWaterEntrySound()

	return character:GetAttribute(
		"WaterWalking"
	) == true
		or character:GetAttribute(
			"WaterJumping"
		) == true

end


-- =========================
-- SOUND DETECTION
-- =========================

local function looksLikeWaterEntrySound(
	sound
)

	if not sound:IsA("Sound") then
		return false
	end


	local name =
		string.lower(
			sound.Name
		)


	-- Roblox / presets suelen usar nombres como:
	-- Splash, WaterSplash, SwimSplash, etc.
	return string.find(
		name,
		"splash",
		1,
		true
	) ~= nil
		or string.find(
			name,
			"submerge",
			1,
			true
		) ~= nil

end


-- =========================
-- CONNECT SOUND
-- =========================

local function connectSound(
	sound
)

	if not looksLikeWaterEntrySound(
		sound
		) then

		return
	end


	if connectedSounds[
		sound
		] then

		return
	end


	connectedSounds[
	sound
	] =
		sound.Played:Connect(
			function()

				if shouldSuppressWaterEntrySound() then

					sound:Stop()

				end

			end
		)


	sound.Destroying:Connect(
		function()

			local connection =
				connectedSounds[
			sound
			]


			if connection then

				connection:Disconnect()

				connectedSounds[
				sound
				] = nil

			end

		end
	)

end


-- =========================
-- EXISTING SOUNDS
-- =========================

for _, descendant in ipairs(
	character:GetDescendants()
	) do

	if descendant:IsA("Sound") then

		connectSound(
			descendant
		)

	end

end


-- =========================
-- FUTURE SOUNDS
-- =========================

character.DescendantAdded:Connect(
	function(descendant)

		if descendant:IsA("Sound") then

			connectSound(
				descendant
			)

		end

	end
)


-- =========================
-- EXTRA SAFETY
-- =========================
--
-- Algunos CharacterSounds pueden iniciar el sonido en el mismo frame
-- en que cambian los atributos. Cuando entramos en WaterWalking o
-- WaterJumping, detenemos cualquier Splash que ya haya empezado.

local function stopCurrentWaterEntrySounds()

	if not shouldSuppressWaterEntrySound() then
		return
	end


	for _, descendant in ipairs(
		character:GetDescendants()
		) do

		if looksLikeWaterEntrySound(
			descendant
			)
				and descendant.IsPlaying then

			descendant:Stop()

		end

	end

end


character:GetAttributeChangedSignal(
	"WaterWalking"
):Connect(
	stopCurrentWaterEntrySounds
)


character:GetAttributeChangedSignal(
	"WaterJumping"
):Connect(
	stopCurrentWaterEntrySounds
)
