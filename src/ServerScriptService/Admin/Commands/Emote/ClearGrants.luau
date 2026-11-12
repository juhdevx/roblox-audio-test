--!strict
-- Defines the ClearGrants admin command.
-- ClearEmotes
return {
	Name = "clearemotes",
	Description = "Remove todos os emotes liberados de um jogador.",
	Group = "Emote",
	Args = {
		{ Type = "player", Name = "jogador", Description = "Jogador a limpar." },
	},
}
