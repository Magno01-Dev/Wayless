--!nonstrict
-- VFX: el servidor solo avisa un "pulso" por cada tick de daño; cada cliente dibuja
-- la corriente continua (ElementalFX > Lightning > LightningStream).
local ElementalFX = require(
    game:GetService("ReplicatedStorage")
        :WaitForChild("JutsuSystem")
        :WaitForChild("Shared")
        :WaitForChild("ElementalFX")
)
local sessions=setmetatable({}, {__mode="k"})
local VFX={}
function VFX.Pulse(context,origin,finish)
    local config=context.Config.Stream or {}
    local interval=typeof(config.TickInterval)=="number" and math.clamp(config.TickInterval,0.05,0.3) or 0.12
    local now=os.clock()
    local session=sessions[context]
    if not session or now-session.last>interval+0.25 then
        session={id=ElementalFX.NewId(),last=now}
        sessions[context]=session
    end
    session.last=now
    ElementalFX.Fire("LightningStream","Pulse",{
        Id=session.id,
        Caster=context.Character,
        Origin=origin,
        End=finish,
        Hold=interval+0.035,
    })
end
return VFX
