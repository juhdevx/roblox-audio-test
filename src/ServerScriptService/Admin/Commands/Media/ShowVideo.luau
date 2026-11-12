--!strict
-- showvideo <jogadores> <video>: transforma o avatar do jogador numa tela e toca o vídeo (ignora a posse).
return {
	Name = "showvideo",
	Aliases = { "playvideo", "video" },
	Description = "Mostra um vídeo no jogador (avatar vira tela). Use `videos` para ver os nomes.",
	Group = "Media",
	Args = {
		{ Type = "players", Name = "jogadores", Description = "Quem vira a tela (. = você, * = todos)." },
		{ Type = "videoEmote", Name = "video", Description = "Nome do vídeo (Tab para completar)." },
	},
}
