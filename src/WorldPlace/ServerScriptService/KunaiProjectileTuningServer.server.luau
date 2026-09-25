--!strict
-- KunaiProjectileTuningServer v1
-- ServerScriptService > KunaiProjectileTuningServer
--
-- Additive correction for the CURRENT stable KunaiServer v2.8.
-- Do NOT replace KunaiServer.
--
-- Fixes:
-- 1) Throw SFX no longer races away with the projectile. The existing throw
--    Sound instance is re-parented to the thrower's Right Arm / HRP.
-- 2) Hard server-side flight-distance cap of 300 studs traveled.
--
-- Hit/stick sounds stay at the impact point exactly as before.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- =========================
-- TUNING
-- =========================

local MAX_FLIGHT_DISTANCE = 300

local KUNAI_THROW_SOUND_ID =
	"rbxassetid://9105104700"

local KUNAI_PREFIX =
	"Kunai_"

-- Small tolerance for large Heartbeat steps.
local RANGE_EPSILON = 0.5

-- =========================
-- STATE
-- =========================

type TrackedKunai = {
	model: Model,
	lastPosition: Vector3,
	traveled: number,
	owner: Player?,
	descendantConnection: RBXScriptConnection?,
	ancestryConnection: RBXScriptConnection?,
}

local tracked: {[Model]: TrackedKunai} =
	{}


local function getBlade(
	model: Model
): BasePart?

	local primary =
		model.PrimaryPart

	if primary
		and primary:IsA(
			"BasePart"
		) then

		return primary
	end

	for _, descendant in ipairs(
		model:GetDescendants()
		) do
		if descendant:IsA(
			"BasePart"
			) then

			return descendant
		end
	end

	return nil
end


local function getOwnerFromModel(
	model: Model
): Player?

	if string.sub(
		model.Name,
		1,
		#KUNAI_PREFIX
		) ~= KUNAI_PREFIX then

		return nil
	end

	local playerName =
		string.sub(
			model.Name,
			#KUNAI_PREFIX + 1
		)

	if playerName == "" then
		return nil
	end

	local instance =
		Players:FindFirstChild(
			playerName
		)

	if instance
		and instance:IsA(
			"Player"
		) then

		return instance
	end

	return nil
end


local function getThrowSoundParent(
	owner: Player?
): BasePart?

	if not owner then
		return nil
	end

	local character =
		owner.Character

	if not character then
		return nil
	end

	local rightArm =
		character:
		FindFirstChild(
			"Right Arm"
		)

	if rightArm
		and rightArm:IsA(
			"BasePart"
		) then

		return rightArm
	end

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if root
		and root:IsA(
			"BasePart"
		) then

		return root
	end

	return nil
end


local function moveThrowSoundToPlayer(
	sound: Sound,
	owner: Player?
)
	if sound.SoundId ~=
		KUNAI_THROW_SOUND_ID then

		return
	end

	-- Avoid touching a sound we've already relocated.
	if sound:GetAttribute(
		"KunaiThrowSoundRelocated"
		) == true then

		return
	end

	local soundParent =
		getThrowSoundParent(
			owner
		)

	if not soundParent then
		return
	end

	sound:SetAttribute(
		"KunaiThrowSoundRelocated",
		true
	)

	-- Re-parent the SAME currently-playing Sound. Its PlaybackPosition and
	-- Debris lifetime are preserved; only the 3D emitter position changes.
	sound.Parent =
		soundParent
end


local function untrack(
	model: Model
)
	local data =
		tracked[model]

	if not data then
		return
	end

	if data.descendantConnection then
		data.descendantConnection:
			Disconnect()
	end

	if data.ancestryConnection then
		data.ancestryConnection:
			Disconnect()
	end

	tracked[model] =
		nil
end


local function trackKunai(
	model: Model
)
	if tracked[model] then
		return
	end

	if string.sub(
		model.Name,
		1,
		#KUNAI_PREFIX
		) ~= KUNAI_PREFIX then

		return
	end

	-- Substitution's welded visual copies are stored elsewhere and named
	-- SubstitutionKunai_..., so they never enter this tracker.
	local blade =
		getBlade(model)

	if not blade then
		-- Model may have just replicated into the folder before descendants.
		task.defer(
			function()
				if model.Parent then
					trackKunai(
						model
					)
				end
			end
		)

		return
	end

	local owner =
		getOwnerFromModel(
			model
		)

	local data: TrackedKunai = {
		model = model,
		lastPosition = blade.Position,
		traveled = 0,
		owner = owner,
		descendantConnection = nil,
		ancestryConnection = nil,
	}

	tracked[model] =
		data

	-- Catch the throw Sound created immediately after KunaiServer parents
	-- the projectile model.
	data.descendantConnection =
		model.DescendantAdded:
		Connect(
			function(descendant)
				if descendant:IsA(
					"Sound"
					) then

					moveThrowSoundToPlayer(
						descendant,
						data.owner
					)
				end
			end
		)

	-- Race-safe scan in case the Sound was created between ChildAdded and
	-- connecting DescendantAdded.
	for _, descendant in ipairs(
		model:GetDescendants()
		) do
		if descendant:IsA(
			"Sound"
			) then

			moveThrowSoundToPlayer(
				descendant,
				data.owner
			)
		end
	end

	data.ancestryConnection =
		model.AncestryChanged:
		Connect(
			function(
				_child,
				parent
			)
				if parent == nil then
					untrack(
						model
					)
				end
			end
		)
end


local kunaiFolder =
	Workspace:
	WaitForChild(
		"Kunais"
	)

for _, child in ipairs(
	kunaiFolder:GetChildren()
	) do
	if child:IsA(
		"Model"
		) then

		trackKunai(
			child
		)
	end
end

kunaiFolder.ChildAdded:
	Connect(
		function(child)
			if child:IsA(
				"Model"
				) then

				trackKunai(
					child
				)
			end
		end
	)


RunService.Heartbeat:
	Connect(
		function()
			for model, data in pairs(
				tracked
				) do
				if not model.Parent then
					untrack(
						model
					)

					continue
				end

				local blade =
				getBlade(
					model
				)

				if not blade then
					continue
				end

				local currentPosition =
				blade.Position

				local segment =
				(
					currentPosition
					- data.lastPosition
				).Magnitude

				-- A stuck kunai naturally contributes ~0 every frame, so its
				-- existing 90-second stuck lifetime remains untouched.
				if segment <
					100 then

					data.traveled +=
					segment
				end

				data.lastPosition =
				currentPosition

				if data.traveled >=
					MAX_FLIGHT_DISTANCE
					- RANGE_EPSILON then

					if model.Parent then
						model:Destroy()
					end

					untrack(
						model
					)
				end
			end
		end
	)

print(
	"[KunaiProjectileTuning] READY throwSoundAtPlayer=ON maxFlightDistance="
		.. tostring(
			MAX_FLIGHT_DISTANCE
		)
)
