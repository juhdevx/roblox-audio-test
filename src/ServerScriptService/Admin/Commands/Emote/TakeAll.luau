--!strict
-- takeall <jogadores> [categoria]: remove todos os emotes de uma categoria (os padrão nunca saem).
return {
	Name = "takeall",
	Aliases = { "revokeall" },
	Description = "Remove todos os emotes de uma categoria (exclusive, video, all...). Emotes padrão ficam.",
	Group = "Emote",
	Args = {
		{ Type = "players", Name = "jogadores", Description = "Quem vai perder os emotes." },
		{ Type = "emoteCategory", Name = "categoria", Description = "all, exclusive, video, special, gamepass, syncable, traversal.", Optional = true },
	},
}
