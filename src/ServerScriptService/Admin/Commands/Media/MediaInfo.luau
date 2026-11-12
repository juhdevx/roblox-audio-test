--!strict
-- mediainfo <video>: detalhes técnicos (vídeo e áudio) de um emote de vídeo.
return {
	Name = "mediainfo",
	Aliases = { "videoinfo" },
	Description = "Mostra codec, resolução, FPS, duração e áudio de um vídeo.",
	Group = "Media",
	Args = {
		{ Type = "videoEmote", Name = "video", Description = "Nome do vídeo." },
	},
}
