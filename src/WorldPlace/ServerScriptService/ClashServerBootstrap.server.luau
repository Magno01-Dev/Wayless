--!strict
-- ClashServerBootstrap v2.5
-- MUST be a normal Script in ServerScriptService.
--
-- This file is intentionally tiny. Its only jobs are:
-- 1) prove server execution,
-- 2) create/tag ClashEvent,
-- 3) require ClashServerCore safely,
-- 4) expose the exact Core load error if one exists.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")


print(
	"[ClashBootstrap] BOOT v2.5 | SERVER SCRIPT IS RUNNING"
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


local clashEvent =
	combatRemotes:
	FindFirstChild(
		"ClashEvent"
	)

if clashEvent
	and not clashEvent:IsA(
		"RemoteEvent"
	) then

	warn(
		"[ClashBootstrap] FATAL: CombatRemotes.ClashEvent exists but is ",
		clashEvent.ClassName,
		", expected RemoteEvent."
	)

	return
end


if not clashEvent then

	clashEvent =
		Instance.new(
			"RemoteEvent"
		)

	clashEvent.Name =
		"ClashEvent"

	clashEvent.Parent =
		combatRemotes
end


local remote =
	clashEvent :: RemoteEvent


remote:SetAttribute(
	"ClashServerBootstrapOnline",
	true
)

remote:SetAttribute(
	"ClashServerVersion",
	"2.5"
)

remote:SetAttribute(
	"ClashServerCoreLoaded",
	false
)


print(
	"[ClashBootstrap] REMOTE READY v2.5 | ",
	remote:GetFullName()
)


local coreModule =
	script.Parent:
	FindFirstChild(
		"ClashServerCore"
	)


if not coreModule then

	warn(
		"[ClashBootstrap] FATAL: ModuleScript 'ClashServerCore' "
			.. "was not found next to this Bootstrap in ServerScriptService."
	)

	return
end


if not coreModule:IsA(
	"ModuleScript"
	) then

	warn(
		"[ClashBootstrap] FATAL: 'ClashServerCore' is ",
		coreModule.ClassName,
		", expected ModuleScript."
	)

	return
end


print(
	"[ClashBootstrap] Requiring ClashServerCore..."
)


local ok,
	result =
	pcall(
		require,
		coreModule
	)


if not ok then

	remote:SetAttribute(
		"ClashServerCoreLoaded",
		false
	)

	remote:SetAttribute(
		"ClashServerCoreError",
		tostring(
			result
		)
	)


	warn(
		"[ClashBootstrap] CORE LOAD FAILED v2.5 >>> ",
		result
	)

	return
end


remote:SetAttribute(
	"ClashServerCoreLoaded",
	true
)

remote:SetAttribute(
	"ClashServerCoreError",
	nil
)


print(
	"[ClashBootstrap] CORE LOADED v2.5 | result=",
	result
)

print(
	"[ClashBootstrap] READY v2.5 | Bootstrap=ON | Core=ON"
)
