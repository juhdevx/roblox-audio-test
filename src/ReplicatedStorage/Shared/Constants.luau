--!strict
-- Names shared across remote, tag, and attribute contracts.
return table.freeze({
    Actions = table.freeze({Play="Play", Sync="Sync", Stop="Stop", Started="Started", SyncStart="SyncStart", Rejected="Rejected", StopEmote="StopEmote", RefreshInventory="RefreshInventory", PlaySound="PlaySound", StopSound="StopSound"}),
    Tags = table.freeze({EmoteSound="EmoteSound", EmotePrompt="EmotePrompt", BarsMeter="EmoteBarsMeter"}),
    Attributes = table.freeze({Emoting="Emoting", EmoteSound="EmoteSound", ShowActive="EmoteShowActive", ShowHost="EmoteShowHost"}),
})
