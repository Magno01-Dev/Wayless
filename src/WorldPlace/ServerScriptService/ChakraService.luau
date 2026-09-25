--!strict
-- ChakraService v1.4 - Chakra Suppression Integration + Reliable Charge
-- ElDiabloLocoStudios / Roblox
--
-- ServerScriptService > ChakraService [ModuleScript]
--
-- Base behavior preserved from ChakraService v1.1 SurfaceCharge:
-- - Max / passive regen
-- - CombatTagged regen profile
-- - server-authoritative TrySpend
-- - Chakra Feet Solid / Water drain
-- - Surface/Water charge maintenance penalty
-- - damage / displacement / action cancellation
--
-- RELIABILITY FIXES:
-- 1) Ground charge no longer relies exclusively on Humanoid.FloorMaterial.
--    A short authoritative downward raycast confirms physical ground during
--    locomotion transitions where FloorMaterial briefly reports Air.
-- 2) Charge start rejection reason is published to the character for QA.
-- 3) Existing server API/remotes remain unchanged.

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")


local ChakraConfig =
	require(
		ReplicatedStorage:
		WaitForChild("ChakraConfig")
	)


local ChakraService =
	{}


local started =
	false


type ChakraState = {
	Character: Model?,
	Current: number,
	Max: number,
	LastSpendAt: number,
	FeetMode: string?,
	Charging: boolean,
	LastHealth: number,
}


local states: {[Player]: ChakraState} =
	{}


local remotes =
	ReplicatedStorage:
	FindFirstChild(
		"ChakraRemotes"
	)


if not remotes then

	remotes =
		Instance.new("Folder")

	remotes.Name =
		"ChakraRemotes"

	remotes.Parent =
		ReplicatedStorage
end


local feetStateEvent =
	remotes:
	FindFirstChild(
		"ChakraFeetState"
	)


if not feetStateEvent then

	feetStateEvent =
		Instance.new("RemoteEvent")

	feetStateEvent.Name =
		"ChakraFeetState"

	feetStateEvent.Parent =
		remotes
end


local chargeRequest =
	remotes:
	FindFirstChild(
		"ChakraChargeRequest"
	)


if not chargeRequest then

	chargeRequest =
		Instance.new("RemoteFunction")

	chargeRequest.Name =
		"ChakraChargeRequest"

	chargeRequest.Parent =
		remotes
end


local chargeVisualStateEvent =
	remotes:
	FindFirstChild(
		"ChakraChargeVisualState"
	)


if not chargeVisualStateEvent then

	chargeVisualStateEvent =
		Instance.new("RemoteEvent")

	chargeVisualStateEvent.Name =
		"ChakraChargeVisualState"

	chargeVisualStateEvent.Parent =
		remotes
end


-- R6 HRP-to-ground is normally around 3 studs.
-- 4.75 provides tolerance for animation / slope / tiny ledge transitions
-- without allowing genuine airborne charging.
local GROUND_CONFIRM_DISTANCE =
	4.75


local function clampValue(
	value: number,
	maxValue: number
): number

	return math.clamp(
		value,
		0,
		maxValue
	)
end


local function getAliveCharacter(
	player: Player
): (Model?, Humanoid?, BasePart?)

	local character =
		player.Character


	if not character
		or not character.Parent then

		return nil,
			nil,
			nil
	end


	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)


	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)


	if not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA(
			"BasePart"
		) then

		return nil,
			nil,
			nil
	end


	return character,
		humanoid,
		root
end


local function getRegenSettings(
	character: Model
): (number, number)

	local tagged =
		character:GetAttribute(
			"CombatTagged"
		) == true


	local profile =
		if tagged
		then ChakraConfig.Regen.CombatTagged
		else ChakraConfig.Regen.OpenWorld


	local regenMultiplier =
		character:GetAttribute(
			"Status_ChakraRegenMultiplier"
		)


	if typeof(regenMultiplier) ~=
		"number" then

		regenMultiplier =
			1

	end


	return profile.PerSecond
		* math.max(
			0,
			regenMultiplier
		),
		profile.DelayAfterSpend
end


local function getRegenStartsAt(
	state: ChakraState,
	character: Model
): number

	if state.LastSpendAt <= 0 then
		return 0
	end


	local _rate,
		delay =
		getRegenSettings(
			character
		)


	return state.LastSpendAt
		+ delay
end


local function getFeetDrainRate(
	feetMode: string?
): number

	if feetMode ==
		"Water" then

		return ChakraConfig.ChakraFeet.WaterDrainPerSecond
	end


	if feetMode ==
		"Solid" then

		return ChakraConfig.ChakraFeet.SolidDrainPerSecond
	end


	return 0
end


local function getChargeRate(
	state: ChakraState
): number

	local rate =
		ChakraConfig.Charge.PerSecond


	if state.FeetMode ~= nil
		and ChakraConfig.Charge.UseChakraFeetMaintenancePenalty ==
		true then

		rate -=
			getFeetDrainRate(
				state.FeetMode
			)
	end


	return math.max(
		0,
		rate
	)
end


local function getChargeMovementSpeed(
	character: Model,
	root: BasePart,
	feetMode: string?
): number

	if feetMode ~= nil then

		local normal =
			character:GetAttribute(
				"SurfaceNormal"
			)


		if typeof(normal) ==
			"Vector3"
			and normal.Magnitude >
			0.5 then

			local unitNormal =
				normal.Unit


			local velocity =
				root.AssemblyLinearVelocity


			local tangent =
				velocity
			- unitNormal
				* velocity:Dot(
					unitNormal
				)


			return tangent.Magnitude
		end
	end


	return Vector3.new(
		root.AssemblyLinearVelocity.X,
		0,
		root.AssemblyLinearVelocity.Z
	).Magnitude
end


local function isPhysicallyGrounded(
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	feetMode: string?
): boolean

	-- Chakra Feet attachment is already an authoritative support mode.
	if feetMode ~= nil then
		return true
	end


	local state =
		humanoid:GetState()


	if state ==
		Enum.HumanoidStateType.Swimming
		or state ==
		Enum.HumanoidStateType.Seated
		or state ==
		Enum.HumanoidStateType.Dead then

		return false
	end


	-- Fast path: normal Roblox grounded state.
	if humanoid.FloorMaterial ~=
		Enum.Material.Air then

		return true
	end


	-- Reliability path:
	-- locomotion controllers can briefly leave FloorMaterial == Air on a frame
	-- where the R6 character is still physically standing on a valid surface.
	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{character}

	params.IgnoreWater =
		false

	params.RespectCanCollide =
		true


	local result =
		workspace:
		Raycast(
			root.Position,
			-Vector3.yAxis
			* GROUND_CONFIRM_DISTANCE,
			params
		)


	if not result then
		return false
	end


	-- Without Chakra Feet, Terrain Water is not valid solid grounding for Charge.
	if result.Material ==
		Enum.Material.Water then

		return false
	end


	return true
end


local function syncAttributes(
	state: ChakraState
)

	local character =
		state.Character


	if not character
		or not character.Parent then

		return
	end


	local regenRate,
		regenDelay =
		getRegenSettings(
			character
		)


	character:SetAttribute(
		"ChakraSystemReady",
		true
	)

	character:SetAttribute(
		"Chakra",
		state.Current
	)

	character:SetAttribute(
		"MaxChakra",
		state.Max
	)

	character:SetAttribute(
		"ChakraRegenRate",
		regenRate
	)

	character:SetAttribute(
		"ChakraRegenDelay",
		regenDelay
	)

	character:SetAttribute(
		"ChakraRegenStartsAt",
		getRegenStartsAt(
			state,
			character
		)
	)

	character:SetAttribute(
		"ChakraCharging",
		state.Charging
	)

	character:SetAttribute(
		"ChakraChargeRate",
		getChargeRate(
			state
		)
	)

	character:SetAttribute(
		"ChakraFeetDrainPaused",
		state.Charging
			and state.FeetMode ~=
			nil
	)

	character:SetAttribute(
		"ChakraFeetServerMode",
		state.FeetMode
			or "Off"
	)
end


-- ============================================================
-- CHAKRA CHARGE 3D SOUND (SERVER-REPLICATED)
-- ============================================================

local CHARGE_SOUND_NAME =
	"ChakraChargeSound"

local CHARGE_SOUND_ID =
	"rbxassetid://111262226714062"

local CHARGE_SOUND_VOLUME =
	1

local CHARGE_SOUND_MIN_DISTANCE =
	8

local CHARGE_SOUND_MAX_DISTANCE =
	70


local function stopChargeSound(
	character: Model
)
	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA(
			"BasePart"
		) then

		return
	end

	local existing =
		root:FindFirstChild(
			CHARGE_SOUND_NAME
		)

	if existing
		and existing:IsA(
			"Sound"
		) then

		existing:Stop()
		existing:Destroy()
	end
end


local function startChargeSound(
	character: Model
)
	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA(
			"BasePart"
		) then

		return
	end

	local existing =
		root:FindFirstChild(
			CHARGE_SOUND_NAME
		)

	if existing then
		if existing:IsA(
			"Sound"
			) then

			existing.SoundId =
				CHARGE_SOUND_ID

			existing.Volume =
				CHARGE_SOUND_VOLUME

			existing.Looped =
				true

			existing.RollOffMode =
				Enum.RollOffMode.Inverse

			existing.RollOffMinDistance =
				CHARGE_SOUND_MIN_DISTANCE

			existing.RollOffMaxDistance =
				CHARGE_SOUND_MAX_DISTANCE

			if not existing.Playing then
				existing:Play()
			end

			return
		end

		existing:Destroy()
	end

	local sound =
		Instance.new(
			"Sound"
		)

	sound.Name =
		CHARGE_SOUND_NAME

	sound.SoundId =
		CHARGE_SOUND_ID

	sound.Volume =
		CHARGE_SOUND_VOLUME

	sound.Looped =
		true

	sound.RollOffMode =
		Enum.RollOffMode.Inverse

	sound.RollOffMinDistance =
		CHARGE_SOUND_MIN_DISTANCE

	sound.RollOffMaxDistance =
		CHARGE_SOUND_MAX_DISTANCE

	sound.Parent =
		root

	-- Play from the server so the Sound instance/state replicates to all clients.
	-- Calling Play immediately is intentional: Roblox can begin playback once
	-- the asset finishes loading on each client.
	sound:Play()
end


local function setChargeVisualActive(
	character: Model,
	active: boolean
)
	character:SetAttribute(
		"ChakraChargeVisualActive",
		active
	)

	if active then
		startChargeSound(
			character
		)
	else
		stopChargeSound(
			character
		)
	end
end


local function stopCharge(
	state: ChakraState,
	reason: string?
)

	if not state.Charging then
		return
	end


	state.Charging =
		false


	local character =
		state.Character


	if character
		and character.Parent then

		character:SetAttribute(
			"ChakraCharging",
			false
		)


		if reason then

			character:SetAttribute(
				"ChakraChargeStopReason",
				reason
			)
		end
	end
end


local function isChargeLocked(
	character: Model
): boolean

	return character:GetAttribute(
		"DownedActionLocked"
	) == true
		or character:GetAttribute(
			"IsDowned"
		) == true
		or character:GetAttribute(
			"IsCarried"
		) == true
		or character:GetAttribute(
			"IsCarrying"
		) == true
		or character:GetAttribute(
			"IsExecuting"
		) == true
		or character:GetAttribute(
			"IsStunned"
		) == true
		or character:GetAttribute(
			"Status_ChakraChargeBlocked"
		) == true
		or character:GetAttribute(
			"Status_ChakraSuppressed"
		) == true
		or character:GetAttribute(
			"IsDashing"
		) == true
		or character:GetAttribute(
			"TreeJumpActive"
		) == true
		or character:GetAttribute(
			"IsTreeJumping"
		) == true
		or character:GetAttribute(
			"IsAttacking"
		) == true
		or character:GetAttribute(
			"IsBlocking"
		) == true
		or character:GetAttribute(
			"MissionInteractionActive"
		) == true
		or character:GetAttribute(
			"JutsuCasting"
		) == true
end


local function publishStartReject(
	character: Model?,
	reason: string
)

	if character
		and character.Parent then

		character:SetAttribute(
			"ChakraChargeLastStartRejectReason",
			reason
		)

		character:SetAttribute(
			"ChakraChargeLastStartRejectAt",
			workspace:
				GetServerTimeNow()
		)
	end
end


local function canStartCharge(
	player: Player,
	state: ChakraState
): (boolean, string)

	local character,
		humanoid,
		root =
		getAliveCharacter(
			player
		)


	if not character
		or not humanoid
		or not root then

		return false,
			"CharacterUnavailable"
	end


	if state.Character ~=
		character then

		return false,
			"CharacterMismatch"
	end


	if state.Current >=
		state.Max - 0.001 then

		return false,
			"ChakraFull"
	end


	if character:GetAttribute(
		"Status_ChakraSuppressed"
		) == true then

		return false,
			"ChakraSuppressed"
	end


	if character:GetAttribute(
		"Status_ChakraChargeBlocked"
		) == true then

		return false,
			"ChakraChargeBlocked"
	end


	if isChargeLocked(
		character
		) then

		return false,
			"ActionLocked"
	end


	if not isPhysicallyGrounded(
		character,
		humanoid,
		root,
		state.FeetMode
		) then

		return false,
			"MustBeGroundedOrChakraFeet"
	end


	local movementSpeed =
		getChargeMovementSpeed(
			character,
			root,
			state.FeetMode
		)


	if movementSpeed >
		ChakraConfig.Charge.MaxStartHorizontalSpeed then

		return false,
			"MovingTooFast"
	end


	return true,
		"OK"
end


local function initializeCharacter(
	player: Player,
	character: Model
)

	local humanoid =
		character:
		WaitForChild(
			"Humanoid"
		) :: Humanoid


	local state =
		states[
	player
	]


	if not state then

		state = {
			Character = character,
			Current = ChakraConfig.MaxChakra,
			Max = ChakraConfig.MaxChakra,
			LastSpendAt = 0,
			FeetMode = nil,
			Charging = false,
			LastHealth = humanoid.Health,
		}


		states[
		player
		] =
			state

	else

		state.Character =
			character

		state.Current =
			state.Max

		state.LastSpendAt =
			0

		state.FeetMode =
			nil

		state.Charging =
			false

		state.LastHealth =
			humanoid.Health
	end


	character:SetAttribute(
		"ChakraLastSpendReason",
		""
	)

	character:SetAttribute(
		"ChakraExhausted",
		false
	)

	character:SetAttribute(
		"ChakraChargeStopReason",
		""
	)

	character:SetAttribute(
		"ChakraChargeLastStartRejectReason",
		""
	)

	character:SetAttribute(
		"ChakraChargeLastStartRejectAt",
		0
	)

	-- Separate visual state:
	-- ChakraCharging may become false when the meter reaches MAX, while the
	-- owning player can still be holding C and playing the charge animation/VFX.
	setChargeVisualActive(
		character,
		false
	)


	character:
		GetAttributeChangedSignal(
			"CombatTagged"
		):
		Connect(
			function()

				if state.Character ==
					character then

					syncAttributes(
						state
					)
				end
			end
		)


	character:
		GetAttributeChangedSignal(
			"Status_ChakraSuppressed"
		):
		Connect(
			function()

				if state.Character ~=
					character then

					return
				end


				if character:GetAttribute(
					"Status_ChakraSuppressed"
					) == true then

					state.FeetMode =
					nil


					if state.Charging then

						stopCharge(
							state,
							"ChakraSuppressed"
						)

					end


					setChargeVisualActive(
						character,
						false
					)

				end


				syncAttributes(
					state
				)
			end
		)


	character:
		GetAttributeChangedSignal(
			"Status_ChakraChargeBlocked"
		):
		Connect(
			function()

				if state.Character ~=
					character then

					return
				end


				if character:GetAttribute(
					"Status_ChakraChargeBlocked"
					) == true
					and state.Charging then

					stopCharge(
						state,
						"ChakraChargeBlocked"
					)


					setChargeVisualActive(
						character,
						false
					)

				end


				syncAttributes(
					state
				)
			end
		)


	character:
		GetAttributeChangedSignal(
			"Status_ChakraRegenMultiplier"
		):
		Connect(
			function()

				if state.Character ==
					character then

					syncAttributes(
						state
					)
				end
			end
		)


	humanoid.Died:
		Connect(
			function()

				if state.Character ==
					character then

					setChargeVisualActive(
						character,
						false
					)
				end
			end
		)


	humanoid.HealthChanged:
		Connect(
			function(
				newHealth: number
			)

				if state.Character ~=
					character then

					return
				end


				if newHealth <
					state.LastHealth
					- 0.001 then

					stopCharge(
						state,
						"Damaged"
					)
				end


				state.LastHealth =
				newHealth
			end
		)


	syncAttributes(
		state
	)
end


local function initializePlayer(
	player: Player
)

	if not states[
		player
		] then

		states[
		player
		] = {
			Character = nil,
			Current = ChakraConfig.MaxChakra,
			Max = ChakraConfig.MaxChakra,
			LastSpendAt = 0,
			FeetMode = nil,
			Charging = false,
			LastHealth = 100,
		}
	end


	player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				initializeCharacter(
					player,
					character
				)
			end
		)


	if player.Character then

		initializeCharacter(
			player,
			player.Character
		)
	end
end


function ChakraService.GetCurrent(
	player: Player
): number

	local state =
		states[
	player
	]


	return state
		and state.Current
		or 0
end


function ChakraService.GetMax(
	player: Player
): number

	local state =
		states[
	player
	]


	return state
		and state.Max
		or ChakraConfig.MaxChakra
end


function ChakraService.TrySpend(
	player: Player,
	amount: number,
	reason: string?
): (boolean, string, number)

	if typeof(amount) ~=
		"number"
		or amount <= 0 then

		return false,
			"InvalidAmount",
			ChakraService.GetCurrent(
				player
			)
	end


	local character,
		humanoid =
		getAliveCharacter(
			player
		)


	if not character
		or not humanoid then

		return false,
			"CharacterUnavailable",
			ChakraService.GetCurrent(
				player
			)
	end


	local state =
		states[
	player
	]


	if not state
		or state.Character ~=
		character then

		initializeCharacter(
			player,
			character
		)

		state =
			states[
		player
		]
	end


	if state.Current + 0.0001 <
		amount then

		return false,
			"InsufficientChakra",
			state.Current
	end


	state.Current =
		clampValue(
			state.Current
			- amount,
			state.Max
		)


	state.LastSpendAt =
		workspace:
		GetServerTimeNow()


	character:SetAttribute(
		"ChakraLastSpendReason",
		reason
			or "Spend"
	)


	if state.Current <= 0 then

		character:SetAttribute(
			"ChakraExhausted",
			true
		)
	end


	syncAttributes(
		state
	)


	return true,
		"OK",
		state.Current
end


feetStateEvent.OnServerEvent:
	Connect(
		function(
			player: Player,
			modeValue: any
		)

			local state =
			states[
			player
			]


			local character =
			player.Character


			if not state
				or not character
				or state.Character ~=
				character then

				return
			end


			local mode: string? =
			nil


			if modeValue ==
				"Solid" then

				mode =
				"Solid"

			elseif modeValue ==
				"Water" then

				mode =
				"Water"

			elseif modeValue ==
				"Off" then

				mode =
				nil

			else

				return
			end


			if mode ~= nil
				and character:GetAttribute(
					"Status_ChakraSuppressed"
				) == true then

				state.FeetMode =
				nil


				syncAttributes(
					state
				)


				return
			end


			if mode ~= nil
				and state.Current <= 0 then

				character:SetAttribute(
					"ChakraExhausted",
					true
				)


				state.FeetMode =
				nil


				syncAttributes(
					state
				)

				return
			end


			if mode ~= nil
				and state.Charging
				and state.FeetMode ==
				nil then

				stopCharge(
					state,
					"ChakraFeetActivated"
				)
			end


			state.FeetMode =
			mode


			syncAttributes(
				state
			)
		end
	)


chargeVisualStateEvent.OnServerEvent:
	Connect(
		function(
			player: Player,
			activeValue: any
		)

			if typeof(activeValue) ~=
				"boolean" then

				return
			end


			local state =
			states[
			player
			]


			if not state then
				return
			end


			local character =
			state.Character


			if not character
				or not character.Parent
				or player.Character ~=
				character then

				return
			end


			if activeValue then

				-- A client may only turn the multiplayer visual ON after the
				-- authoritative server has accepted Chakra Charge.
				if not state.Charging then
					return
				end


				local humanoid =
				character:
				FindFirstChildOfClass(
					"Humanoid"
				)


				if not humanoid
					or humanoid.Health <= 0 then

					return
				end
			end


			setChargeVisualActive(
				character,
				activeValue
			)
		end
	)


chargeRequest.OnServerInvoke =
	function(
		player: Player,
		actionValue: any
	)

	local state =
		states[
	player
	]


	if not state then

		return false,
			"StateUnavailable"
	end


	if actionValue ==
		"Stop" then

		stopCharge(
			state,
			"Released"
		)

		return true,
			"Stopped"
	end


	if actionValue ~=
		"Start" then

		return false,
			"InvalidAction"
	end


	if state.Charging then

		return true,
			"AlreadyCharging"
	end


	local allowed,
		reason =
		canStartCharge(
			player,
			state
		)


	if not allowed then

		publishStartReject(
			state.Character,
			reason
		)

		return false,
			reason
	end


	state.Charging =
		true


	local character =
		state.Character


	if character
		and character.Parent then

		character:SetAttribute(
			"ChakraCharging",
			true
		)

		character:SetAttribute(
			"ChakraChargeStopReason",
			""
		)

		character:SetAttribute(
			"ChakraChargeLastStartRejectReason",
			""
		)
	end


	return true,
		"Started"
end


local accumulated =
	0


RunService.Heartbeat:
	Connect(
		function(
			deltaTime: number
		)

			if not started then
				return
			end


			accumulated +=
			deltaTime


			if accumulated <
				ChakraConfig.Regen.UpdateInterval then

				return
			end


			local step =
			accumulated

			accumulated =
			0


			local now =
			workspace:
			GetServerTimeNow()


			for player,
				state in pairs(
					states
				) do

				local character,
				humanoid,
				root =
				getAliveCharacter(
					player
				)


				if not character
					or not humanoid
					or not root
					or state.Character ~=
					character then

					continue
				end


				-- =============================
				-- MANUAL CHAKRA CHARGE
				-- =============================
				if state.Charging then

					if isChargeLocked(
						character
						) then

						stopCharge(
							state,
							"ActionLocked"
						)

						syncAttributes(
							state
						)

						continue
					end


					local movementSpeed =
					getChargeMovementSpeed(
						character,
						root,
						state.FeetMode
					)


					if movementSpeed >
						ChakraConfig.Charge.CancelHorizontalSpeed then

						stopCharge(
							state,
							"Displaced"
						)

						syncAttributes(
							state
						)

						continue
					end


					local chargeRate =
					getChargeRate(
						state
					)


					state.Current =
					clampValue(
						state.Current
						+ chargeRate
						* step,
						state.Max
					)


					if state.Current > 0 then

						character:SetAttribute(
							"ChakraExhausted",
							false
						)
					end


					if state.Current >=
						state.Max then

						state.Current =
						state.Max

						stopCharge(
							state,
							"Full"
						)
					end


					syncAttributes(
						state
					)

					continue
				end


				-- =============================
				-- CHAKRA FEET DRAIN
				-- =============================
				if state.FeetMode ~=
					nil then

					local drainRate =
					getFeetDrainRate(
						state.FeetMode
					)


					if state.Current > 0 then

						state.Current =
						clampValue(
							state.Current
							- drainRate
							* step,
							state.Max
						)


						state.LastSpendAt =
						now


						character:SetAttribute(
							"ChakraLastSpendReason",
							if state.FeetMode ==
							"Water"
							then "ChakraFeetWater"
							else "ChakraFeetSolid"
						)
					end


					if state.Current <= 0 then

						state.Current =
						0

						state.FeetMode =
						nil


						character:SetAttribute(
							"ChakraExhausted",
							true
						)
					end


					syncAttributes(
						state
					)

					continue
				end


				-- =============================
				-- PASSIVE REGEN
				-- =============================
				local regenRate,
				regenDelay =
				getRegenSettings(
					character
				)


				if regenRate <= 0
					or state.Current >=
					state.Max then

					continue
				end


				local regenStartsAt =
				if state.LastSpendAt >
				0
				then state.LastSpendAt
				+ regenDelay
				else 0


				if now <
					regenStartsAt then

					continue
				end


				state.Current =
				clampValue(
					state.Current
					+ regenRate
					* step,
					state.Max
				)


				if state.Current > 0 then

					character:SetAttribute(
						"ChakraExhausted",
						false
					)
				end


				syncAttributes(
					state
				)
			end
		end
	)


function ChakraService.Start()

	if started then
		return
	end


	started =
		true


	Players.PlayerAdded:
		Connect(
			initializePlayer
		)


	Players.PlayerRemoving:
		Connect(
			function(
				player: Player
			)

				states[
				player
				] =
				nil
			end
		)


	for _,
		player in ipairs(
			Players:GetPlayers()
		) do

		initializePlayer(
			player
		)
	end


	print(
		"[ChakraService] READY v1.4 ChakraSuppression_ReliableCharge"
			.. " | Max="
			.. tostring(
				ChakraConfig.MaxChakra
			)
			.. " | GroundRay="
			.. tostring(
				GROUND_CONFIRM_DISTANCE
			)
			.. " | OpenRegen="
			.. tostring(
				ChakraConfig.Regen.OpenWorld.PerSecond
			)
			.. "/s"
			.. " | PvPRegen="
			.. tostring(
				ChakraConfig.Regen.CombatTagged.PerSecond
			)
			.. "/s"
			.. " | Charge="
			.. tostring(
				ChakraConfig.Charge.PerSecond
			)
			.. "/s"
			.. " | ChakraSuppression=ChargeBlocked+FeetOff+RegenMultiplier"
	)
end


return ChakraService
