--!strict
-- ChakraFeetReplicationClient v2
--
-- StarterPlayer > StarterCharacterScripts > ChakraFeetReplicationClient
--
-- Reads the LOCAL SurfaceController state and forwards changes to server.
-- No movement, camera, animation, physics, or VFX logic here.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local character =
	script.Parent

local movementRemotes =
	ReplicatedStorage:
	WaitForChild(
		"MovementRemotes"
	)

local chakraFeetStateRequest =
	movementRemotes:
	WaitForChild(
		"ChakraFeetStateRequest"
	) :: RemoteEvent


local ATTRIBUTE_NAME =
	"ChakraFeetActive"

local lastSent: boolean? =
	nil


local function sendCurrentState()

	local current =
		character:GetAttribute(
			ATTRIBUTE_NAME
		) == true


	if lastSent ==
		current then

		return

	end


	lastSent =
		current


	chakraFeetStateRequest:
		FireServer(
			current
		)

end


-- SurfaceController may set the attribute after this script starts.
task.defer(
	sendCurrentState
)


character:
	GetAttributeChangedSignal(
		ATTRIBUTE_NAME
	):
	Connect(
		sendCurrentState
	)
