--!strict
-- videos [jogador]: lista os vídeos disponíveis e, se houver jogador, quais ele já tem.
return {
	Name = "videos",
	Aliases = { "listvideos", "media" },
	Description = "Lista os vídeos (resolução, FPS, duração) e quem tem acesso.",
	Group = "Media",
	Args = {
		{ Type = "player", Name = "jogador", Description = "Mostra se esse jogador tem cada vídeo.", Optional = true },
	},
}
