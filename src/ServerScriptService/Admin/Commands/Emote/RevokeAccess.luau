--!strict
-- Defines the RevokeAccess admin command.
-- TakeEmote
return {
	Name = "takeemote",
	Aliases = { "revokeemote" },
	Description = "Remove a liberação de um emote de um jogador.",
	Group = "Emote",
	Args = {
		{ Type = "player", Name = "jogador", Description = "Quem vai perder o acesso." },
		{ Type = "emoteName", Name = "emote", Description = "Nome do emote (Tab para completar)." },
	},
}
