--!strict
-- giveall <jogadores> [categoria]: libera todos os emotes de uma categoria (padrão: exclusive, que inclui os vídeos).
return {
	Name = "giveall",
	Aliases = { "giveexclusives", "grantall" },
	Description = "Libera todos os emotes de uma categoria (exclusive, video, all...).",
	Group = "Emote",
	Args = {
		{ Type = "players", Name = "jogadores", Description = "Quem vai receber (. = você, * = todos)." },
		{ Type = "emoteCategory", Name = "categoria", Description = "all, default, exclusive, video, special, gamepass, syncable, traversal.", Optional = true },
	},
}
