--!strict
-- Sends administrative notifications through the registered project remote.
local Notify = {}
local remote: RemoteEvent
function Notify.Init(dependencies: any) remote = dependencies.RemoteService.Get("Admin", "Notify") end
function Notify.send(player: Player, text: string, kind: string?)
    if player.Parent then remote:FireClient(player, {text=text, kind=kind or "info", t=os.time()}) end
end
function Notify.broadcast(text: string, kind: string?)
    remote:FireAllClients({text=text, kind=kind or "info", t=os.time()})
end
return Notify
