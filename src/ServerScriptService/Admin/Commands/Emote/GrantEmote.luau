--!strict
-- Defines the GrantEmote admin command.
-- GiveEmote
return {
	Name = "giveemote",
	Aliases = { "grantemote" },
	Description = "Libera um emote para um jogador.",
	Group = "Emote",
	Args = {
		{ Type = "player", Name = "jogador", Description = "Quem vai receber." },
		{ Type = "emoteName", Name = "emote", Description = "Nome do emote (Tab para completar)." },
	},
}
