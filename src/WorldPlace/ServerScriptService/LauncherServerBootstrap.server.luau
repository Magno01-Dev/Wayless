--!strict
-- LauncherServerBootstrap v1.0
-- ServerScriptService > LauncherServerBootstrap [Script]

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")


print(
	"[LauncherBootstrap] BOOT v1.0"
)


local combatRemotes =
	ReplicatedStorage:
	FindFirstChild(
		"CombatRemotes"
	)

if not combatRemotes then

	combatRemotes =
		Instance.new(
			"Folder"
		)

	combatRemotes.Name =
		"CombatRemotes"

	combatRemotes.Parent =
		ReplicatedStorage
end


local launcherEvent =
	combatRemotes:
	FindFirstChild(
		"LauncherEvent"
	)


if launcherEvent
	and not launcherEvent:IsA(
		"RemoteEvent"
	) then

	warn(
		"[LauncherBootstrap] FATAL LauncherEvent wrong class:",
		launcherEvent.ClassName
	)

	return
end


if not launcherEvent then

	launcherEvent =
		Instance.new(
			"RemoteEvent"
		)

	launcherEvent.Name =
		"LauncherEvent"

	launcherEvent.Parent =
		combatRemotes
end


local remote =
	launcherEvent :: RemoteEvent


remote:SetAttribute(
	"LauncherServerVersion",
	"1.0"
)


print(
	"[LauncherBootstrap] REMOTE READY | ",
	remote:GetFullName()
)


local core =
	script.Parent:
	FindFirstChild(
		"LauncherServerCore"
	)


if not core
	or not core:IsA(
		"ModuleScript"
	) then

	warn(
		"[LauncherBootstrap] FATAL: LauncherServerCore ModuleScript missing"
	)

	return
end


local ok,
	result =
	pcall(
		require,
		core
	)


if not ok then

	warn(
		"[LauncherBootstrap] CORE LOAD FAILED >>> ",
		result
	)

	return
end


print(
	"[LauncherBootstrap] READY v1.0 | CoreLoaded=",
	result
)
