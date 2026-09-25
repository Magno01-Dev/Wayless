--!strict
-- DiabloStudios
-- ServerScriptService > StatusEffects > StatusEffectRuntime
-- StatusFX Runtime v1.8 - DamageService + Elemental Potency
--
-- Server owns effect lifetime / stacking / DOT / replicated flags.
-- Movement is NOT enforced here anymore.
-- Sprint/Dash/Jump/Surface controllers consume Status_* attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

print("[StatusEffectRuntime] BOOT v1.8 ElementalPotency")

local services =
	ServerScriptService:WaitForChild("Services")

local StatusEffectService =
	require(
		services:WaitForChild(
			"StatusEffectService"
		)
	)

local DeveloperAccessService =
	require(
		services:WaitForChild(
			"DeveloperAccessService"
		)
	)

DeveloperAccessService.Start()

local DamageService =
	require(
		ServerScriptService:WaitForChild(
			"DamageService"
		)
	)

local remotes =
	ReplicatedStorage:WaitForChild(
		"StatusEffectRemotes"
	)

local devApply =
	remotes:WaitForChild(
		"DevApply"
	) :: RemoteEvent

-- Production DOT adapter.
--
-- StatusEffectService owns timing/stacking only; DamageService remains the
-- single damage gateway so player DOT can enter Downed, preserve the
-- existing Substitution/Execute protections, and retain SourcePlayer
-- attribution.
--
-- IgnoreArmor intentionally preserves the original StatusFX semantics:
-- Poison/Bleed/Burn were direct health effects in the validation adapter.
-- Routing them through normal Armor here would also consume Armor durability
-- on every tick and change the authored DOT damage values.
StatusEffectService.SetDamageHandler(function(
	targetCharacter: Model,
	amount: number,
	context: {[string]: any}
)
	local humanoid =
		targetCharacter:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0
		or amount <= 0 then

		return
	end

	local targetPlayer =
		Players:GetPlayerFromCharacter(
			targetCharacter
		)

	local sourcePlayer =
		if typeof(context.SourcePlayer) == "Instance"
		and context.SourcePlayer:IsA("Player")
		then context.SourcePlayer
		else nil

	local effectId =
		if typeof(context.EffectId) == "string"
		then context.EffectId
		else "Unknown"

	local potency =
		1.0

	if typeof(context.Metadata) == "table"
		and typeof(
			context.Metadata.ElementalPotency
		) == "number" then

		potency =
			math.max(
				0,
				context.Metadata.ElementalPotency
			)
	end

	amount *= potency

	local resolution =
		DamageService.Apply({
			TargetCharacter =
			targetCharacter,

			TargetHumanoid =
			humanoid,

			TargetPlayer =
			targetPlayer,

			Attacker =
			sourcePlayer,

			Damage =
			amount,

			SourceType =
			"StatusEffect",

			SourceId =
			effectId,

			IgnoreArmor =
			true,
		})

	print(
		"[StatusFX Damage]",
		effectId,
		targetCharacter.Name,
		"| result=",
		resolution.Result,
		"| damage=",
		string.format(
			"%.2f",
			resolution.FinalDamage
		),
		"| stacks=",
		context.Stacks
	)
end)

StatusEffectService.Start()

local ALLOWED = {
	Poison = true,
	Bleed = true,

	-- Burn remains a compatibility input; ElementalCombatService maps it
	-- to canonical Burning.
	Burn = true,
	Burning = true,
	Unsteady = true,
	Charged = true,
	Heavy = true,
	Wet = true,

	Slow = true,
	Stun = true,
	ChakraSuppression = true,
}

-- QA durations only.
local DEV_DURATION_OVERRIDE = {
	Slow = 5.0,
	Stun = 3.0,
	ChakraSuppression = 8.0,
}

devApply.OnServerEvent:Connect(function(
	player: Player,
	action: string,
	effectId: string?
)
	if not DeveloperAccessService.IsDeveloper(
		player
		) then
		warn(
			"[StatusEffectRuntime] DEV APPLY REJECTED",
			player.Name,
			"NotDeveloper"
		)

		return
	end

	local character =
		player.Character

	if not character then
		return
	end

	if action == "Clear" then
		local removed =
			StatusEffectService.Clear(
				character
			)

		print(
			"[StatusEffectRuntime] CLEAR",
			player.Name,
			"| removed=",
			removed
		)

		return
	end

	if action ~= "Apply"
		or typeof(effectId) ~= "string"
		or not ALLOWED[effectId] then

		return
	end

	local ok,
	result =
		StatusEffectService.Apply(
			character,
			effectId,
			{
				Duration =
				DEV_DURATION_OVERRIDE[
				effectId
				],
				SourcePlayer =
				player,
				SourceCharacter =
				character,
			}
		)

	print(
		"[StatusEffectRuntime] APPLY",
		player.Name,
		effectId,
		"| ok=",
		ok,
		"| result=",
		result,
		"| devDuration=",
		DEV_DURATION_OVERRIDE[
		effectId
		] or "default"
	)
end)

-- ============================================================
-- DEV INDICATOR ONLY
-- ============================================================

local function ensureIndicator(
	character: Model
): TextLabel?

	local head =
		character:FindFirstChild(
			"Head"
		)

	if not head
		or not head:IsA(
			"BasePart"
		) then

		return nil
	end

	local gui =
		head:FindFirstChild(
			"StatusFX_Indicator"
		)

	if not gui then
		gui =
			Instance.new(
				"BillboardGui"
			)

		gui.Name =
			"StatusFX_Indicator"

		gui.Size =
			UDim2.fromOffset(
				300,
				64
			)

		gui.StudsOffset =
			Vector3.new(
				0,
				2.8,
				0
			)

		gui.AlwaysOnTop =
			true

		gui.Parent =
			head

		local label =
			Instance.new(
				"TextLabel"
			)

		label.Name =
			"Label"

		label.Size =
			UDim2.fromScale(
				1,
				1
			)

		label.BackgroundTransparency =
			1

		label.TextSize =
			15

		label.Font =
			Enum.Font.GothamBold

		label.TextWrapped =
			true

		label.Text =
			""

		label.Parent =
			gui
	end

	local label =
		gui:FindFirstChild(
			"Label"
		)

	if label
		and label:IsA(
			"TextLabel"
		) then

		return label
	end

	return nil
end

local function updateIndicator(
	character: Model
)
	local label =
		ensureIndicator(
			character
		)

	if not label then
		return
	end

	local root =
		character:FindFirstChild(
			"StatusEffects"
		)

	local names = {}

	if root then
		for _, child in ipairs(
			root:GetChildren()
			) do

			if child:IsA(
				"Folder"
				) then

				local stacks =
					child:GetAttribute(
						"Stacks"
					) or 1

				local display =
					child.Name

				if child.Name == "Slow" then
					display = "SLOW 40%"
				elseif child.Name == "Stun" then
					display = "STUN"
				elseif child.Name ==
					"ChakraSuppression" then
					display =
						"CHAKRA SUPPRESSED"
				end

				if stacks > 1 then
					display ..=
						" x"
						.. tostring(
							stacks
						)
				end

				table.insert(
					names,
					display
				)
			end
		end
	end

	table.sort(
		names
	)

	label.Text =
		table.concat(
			names,
			"  •  "
		)

	label.Visible =
		#names > 0
end

local indicatorAccumulator = 0

RunService.Heartbeat:Connect(function(
	deltaTime
)
	indicatorAccumulator +=
		deltaTime

	if indicatorAccumulator <
		0.10 then

		return
	end

	indicatorAccumulator =
		0

	for _, player in ipairs(
		Players:GetPlayers()
		) do

		local character =
			player.Character

		if character then
			updateIndicator(
				character
			)
		end
	end
end)

print(
	"[StatusEffectRuntime] READY v1.9 UnifiedDevAuth"
		.. " | MovementEnforcement=DIRECT_CONTROLLERS"
		.. " | ServerWalkSpeedWrites=OFF"
		.. " | ServerVelocityWrites=OFF"
		.. " | DOT=DamageService+Downed"
		.. " | DOTArmor=IGNORE_PRESERVE_AUTHORED_DAMAGE"
		.. " | DOTSourceAttribution=ON"
		.. " | BillboardIndicator=ON"
)
