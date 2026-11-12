--!strict
-- Defines the ListGrants admin command.
-- EmoteGrants
return {
	Name = "emotegrants",
	Aliases = { "listemotes" },
	Description = "Lista os emotes liberados de um jogador.",
	Group = "Emote",
	Args = {
		{ Type = "player", Name = "jogador", Description = "Jogador a consultar." },
	},
}
