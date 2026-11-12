--!strict
-- playemote <jogadores> <emote>: toca o emote no jogador mesmo sem ele ter o emote.
return {
	Name = "playemote",
	Aliases = { "forceemote" },
	Description = "Toca um emote no jogador (ignora a posse).",
	Group = "Emote",
	Args = {
		{ Type = "players", Name = "jogadores", Description = "Quem vai dançar." },
		{ Type = "emoteName", Name = "emote", Description = "Nome do emote." },
	},
}
