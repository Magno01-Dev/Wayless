--!strict
-- ProjectileClashVFXClient v1
-- StarterPlayer > StarterPlayerScripts > ProjectileClashVFXClient [LocalScript]
--
-- Client renderer for projectile clash VFX.
--
-- The server decides whether a clash is valid and sends only the confirmed
-- effect type + world position. This LocalScript clones the authored effect
-- from ReplicatedStorage and calls ParticleEmitter:Emit() locally so every
-- player actually sees the burst.
--
-- Required hierarchy:
-- ReplicatedStorage
-- ├─ ProjectileRemotes
-- │  └─ ProjectileClashVFX [RemoteEvent]
-- └─ VFX
--    └─ SparkKunaiParry [BasePart / Model / Attachment]
--       └─ Effect [Attachment]
--          ├─ Core [ParticleEmitter]
--          ├─ CoreMiniSparks [ParticleEmitter]
--          ├─ MiniSparks [ParticleEmitter]
--          └─ Sparks [ParticleEmitter]

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Debris =
	game:GetService("Debris")

local RunService =
	game:GetService("RunService")


local remotes =
	ReplicatedStorage:
	WaitForChild(
		"ProjectileRemotes"
	)

local clashVFXRemote =
	remotes:
	WaitForChild(
		"ProjectileClashVFX"
	) :: RemoteEvent


local VFX_FOLDER_NAME =
	"VFX"

local KUNAI_CLASH_TEMPLATE_NAME =
	"SparkKunaiParry"

local FALLBACK_CLEANUP_TIME =
	2.0

local warnedMissingTemplate =
	false

local DEBUG_CLASH_VFX =
	true


local function getKunaiClashTemplate(): Instance?

	local vfxFolder =
		ReplicatedStorage:
		FindFirstChild(
			VFX_FOLDER_NAME
		)


	if not vfxFolder then
		return nil
	end


	return vfxFolder:
		FindFirstChild(
			KUNAI_CLASH_TEMPLATE_NAME
		)
end


local function preparePart(
	part: BasePart
)

	part.Anchored =
		true

	part.CanCollide =
		false

	part.CanTouch =
		false

	part.CanQuery =
		false

	part.Massless =
		true
end


local function getEmitCount(
	emitter: ParticleEmitter
): number

	-- You can put an Attribute called EmitCount on each emitter
	-- if you want to tune the amount from Studio.

	local attributeValue =
		emitter:
		GetAttribute(
			"EmitCount"
		)


	if typeof(attributeValue) ==
		"number" then

		return math.max(
			1,
			math.floor(
				attributeValue
			)
		)
	end


	if emitter.Name ==
		"Core" then

		return 1
	end


	if emitter.Name ==
		"CoreMiniSparks" then

		return 5
	end


	if emitter.Name ==
		"MiniSparks" then

		return 10
	end


	if emitter.Name ==
		"Sparks" then

		return 18
	end


	return 8
end


local function parentEffectAtPosition(
	template: Instance,
	position: Vector3
): Instance?

	local effect =
		template:
		Clone()


	-- ========================================================
	-- BASEPART ROOT
	-- ========================================================

	if effect:IsA(
		"BasePart"
		) then

		preparePart(
			effect
		)


		-- Preserve authored rotation.
		effect.CFrame =
			CFrame.new(
				position
			)
			* effect.CFrame.Rotation


		effect.Parent =
			workspace


		return effect
	end


	-- ========================================================
	-- MODEL ROOT
	-- ========================================================

	if effect:IsA(
		"Model"
		) then

		for _,
			descendant in ipairs(
				effect:
					GetDescendants()
			) do

			if descendant:IsA(
				"BasePart"
				) then

				preparePart(
					descendant
				)
			end
		end


		local originalPivot =
			effect:
			GetPivot()


		effect.Parent =
			workspace


		effect:
			PivotTo(
				CFrame.new(
					position
				)
				* originalPivot.Rotation
			)


		return effect
	end


	-- ========================================================
	-- ATTACHMENT ROOT
	-- ========================================================

	if effect:IsA(
		"Attachment"
		) then

		local anchor =
			Instance.new(
				"Part"
			)


		anchor.Name =
			"KunaiClashVFXAnchor"

		anchor.Size =
			Vector3.new(
				0.1,
				0.1,
				0.1
			)

		anchor.Transparency =
			1


		preparePart(
			anchor
		)


		anchor.CFrame =
			CFrame.new(
				position
			)


		anchor.Parent =
			workspace


		effect.Parent =
			anchor


		return anchor
	end


	warn(
		"[ProjectileClashVFXClient] Unsupported root class for "
			.. KUNAI_CLASH_TEMPLATE_NAME
			.. ": "
			.. effect.ClassName
			.. ". Use a BasePart, Model, or Attachment."
	)


	effect:
		Destroy()


	return nil
end


local function emitAllParticles(
	container: Instance
)

	local longestLifetime =
		FALLBACK_CLEANUP_TIME

	local emitterCount =
		0


	for _,
		descendant in ipairs(
			container:
				GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			emitterCount +=
				1


			-- Burst only.
			descendant.Enabled =
				false


			descendant:
				Emit(
					getEmitCount(
						descendant
					)
				)


			longestLifetime =
				math.max(
					longestLifetime,
					descendant.Lifetime.Max
					+ 0.5
				)
		end
	end


	if emitterCount ==
		0 then

		warn(
			"[ProjectileClashVFXClient] "
				.. KUNAI_CLASH_TEMPLATE_NAME
				.. " was cloned, but no ParticleEmitter descendants were found."
		)

	elseif DEBUG_CLASH_VFX then

		print(
			"[ProjectileClashVFXClient] EMITTED",
			emitterCount,
			"emitters"
		)
	end


	Debris:
		AddItem(
			container,
			longestLifetime
		)
end


local function playKunaiClash(
	position: Vector3
)

	local template =
		getKunaiClashTemplate()


	if not template then

		if not warnedMissingTemplate then

			warnedMissingTemplate =
				true


			warn(
				"[ProjectileClashVFXClient] Missing ReplicatedStorage > VFX > "
					.. KUNAI_CLASH_TEMPLATE_NAME
			)
		end


		return
	end


	local container =
		parentEffectAtPosition(
			template,
			position
		)


	if not container then
		return
	end


	-- Give Roblox's renderer one frame to register the newly cloned
	-- ParticleEmitters before issuing the burst.

	RunService.RenderStepped:
		Wait()


	emitAllParticles(
		container
	)
end


clashVFXRemote.OnClientEvent:
	Connect(
		function(
			effectType: any,
			position: any
		)

			if effectType ~=
				"KunaiClash" then

				return
			end


			if typeof(position) ~=
				"Vector3" then

				return
			end


			if DEBUG_CLASH_VFX then

				print(
					"[ProjectileClashVFXClient] RECEIVED KunaiClash",
					position
				)
			end


			playKunaiClash(
				position
			)
		end
	)


print(
	"[ProjectileClashVFXClient] READY"
		.. " | KunaiClash=SparkKunaiParry"
		.. " | ClientEmit=ON"
)