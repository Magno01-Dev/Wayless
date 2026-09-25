--!nonstrict
local remote=game:GetService("ReplicatedStorage"):WaitForChild("WaylessLightningStreamVFX")
local sessions=setmetatable({}, {__mode="k"})
local sequence=0
local VFX={}
function VFX.Pulse(context,origin,finish)
    local config=context.Config.Stream or {}
    local interval=typeof(config.TickInterval)=="number" and math.clamp(config.TickInterval,0.05,0.3) or 0.12
    local now=os.clock()
    local session=sessions[context]
    if not session or now-session.last>interval+0.25 then
        sequence+=1
        session={id=sequence,last=now}
        sessions[context]=session
    end
    session.last=now
    remote:FireAllClients(session.id,context.Character,origin,finish,interval+0.035)
end
return VFX
