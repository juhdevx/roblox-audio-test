--!strict
-- stopemote <jogadores>: encerra o emote atual (inclui vídeos).
return {
	Name = "stopemote",
	Aliases = { "stopvideo" },
	Description = "Para o emote/vídeo que o jogador está tocando.",
	Group = "Emote",
	Args = {
		{ Type = "players", Name = "jogadores", Description = "Quem vai parar." },
	},
}
