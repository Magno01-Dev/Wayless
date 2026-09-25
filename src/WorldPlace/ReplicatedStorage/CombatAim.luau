--!strict
-- CombatAim v4 - No Inset Double Correction
--
-- PLACE:
-- ReplicatedStorage > CombatAim (ModuleScript)
--
-- PURPOSE:
-- Shared CLIENT-side aiming utility.
--
-- CombatCrosshairController registers the actual Reticle GuiObject here.
-- Any future projectile / jutsu / throwable LocalScript can require this
-- module and ask for:
--
--   CombatAim.GetAimRay()
--   CombatAim.GetAimTarget(...)
--   CombatAim.GetDirectionFromOrigin(...)
--
-- The ray is generated through the CENTER OF THE ACTUAL RETICLE on screen,
-- not through the center of the camera viewport.
--
-- IMPORTANT SERVER RULE:
-- This module is for local aim acquisition / immediate feedback.
-- The client may send an aim direction/point to the server, but the server
-- must still validate the attack, cooldown, origin, range and target.

local Players =
	game:GetService("Players")

local GuiService =
	game:GetService("GuiService")

local UserInputService =
	game:GetService("UserInputService")

local player =
	Players.LocalPlayer

local CombatAim = {}

local registeredReticle: GuiObject? =
	nil


local function getCamera(): Camera?

	return workspace.CurrentCamera

end


local function createDefaultRaycastParams(): RaycastParams

	local params =
		RaycastParams.new()


	params.FilterType =
		Enum.RaycastFilterType.Exclude


	local character =
		if player
		then player.Character
		else nil


	if character then

		params.FilterDescendantsInstances = {
			character
		}

	else

		params.FilterDescendantsInstances =
			{}

	end


	params.IgnoreWater =
		false


	return params

end


function CombatAim.SetReticle(
	reticle: GuiObject
)

	registeredReticle =
		reticle

end


function CombatAim.ClearReticle(
	reticle: GuiObject?
)

	if reticle == nil
		or registeredReticle ==
		reticle then

		registeredReticle =
			nil

	end

end


function CombatAim.GetViewportPoint(): Vector2

	-- IMPORTANT:
	-- v2 was one GUI-inset correction too low.
	-- v3 corrected the inset in the opposite direction and ended up too high.
	--
	-- For the current combat setup, MouseBehavior is LockCenter and the Reticle
	-- is drawn from GetMouseLocation(). We therefore use that coordinate DIRECTLY
	-- with ViewportPointToRay -- no +GuiInset and no -GuiInset.
	--
	-- This is the midpoint between the two previous behaviors and avoids applying
	-- the top-bar offset twice in either direction.

	if UserInputService.MouseBehavior ==
		Enum.MouseBehavior.LockCenter then

		return UserInputService:
			GetMouseLocation()

	end


	local reticle =
		registeredReticle


	if reticle
		and reticle.Parent then

		return reticle.AbsolutePosition
			+ (
				reticle.AbsoluteSize
				* 0.5
			)

	end


	return UserInputService:
		GetMouseLocation()

end


-- Backward-compatible helper.
function CombatAim.GetScreenPoint(): Vector2

	return CombatAim.GetViewportPoint()

end


function CombatAim.GetAimRay(
	depth: number?
): Ray?

	local camera =
		getCamera()


	if not camera then
		return nil
	end


	local viewportPoint =
		CombatAim.GetViewportPoint()


	-- Same coordinate goes directly into ViewportPointToRay.
	-- No GuiService inset conversion is applied here.
	return camera:ViewportPointToRay(
		viewportPoint.X,
		viewportPoint.Y,
		depth or 0
	)

end


function CombatAim.GetAimTarget(
	maxDistance: number?,
	raycastParams: RaycastParams?
): (
	Vector3?,
	RaycastResult?
	)

	local ray =
		CombatAim.GetAimRay()


	if not ray then

		return nil,
			nil

	end


	local distance =
		maxDistance or 1000


	local params =
		raycastParams
		or createDefaultRaycastParams()


	local result =
		workspace:Raycast(
			ray.Origin,
			ray.Direction
			* distance,
			params
		)


	if result then

		return result.Position,
			result

	end


	return ray.Origin
		+ ray.Direction
		* distance,
		nil

end


function CombatAim.GetDirectionFromOrigin(
	worldOrigin: Vector3,
	maxDistance: number?,
	raycastParams: RaycastParams?
): (
	Vector3?,
	Vector3?,
	RaycastResult?
	)

	local targetPoint,
		result =
		CombatAim.GetAimTarget(
			maxDistance,
			raycastParams
		)


	if not targetPoint then

		return nil,
			nil,
			nil

	end


	local delta =
		targetPoint
	- worldOrigin


	if delta.Magnitude <
		0.001 then

		return nil,
			targetPoint,
			result

	end


	-- Esta es la dirección que debe usar un proyectil que realmente nace
	-- desde una mano, Attachment o arma. Así compensa la paralaje entre
	-- la cámara y el punto físico de salida.
	return delta.Unit,
		targetPoint,
		result

end


return CombatAim
