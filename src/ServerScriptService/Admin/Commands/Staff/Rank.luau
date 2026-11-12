--!strict
-- rank <jogadorId> <cargo>: dá cargo moderator/staff (persiste entre servidores). Só Owner.
return {
	Name = "rank",
	Aliases = { "setrank", "promote" },
	Description = "Define o cargo de um jogador: user, moderator ou staff (salvo no DataStore).",
	Group = "Staff",
	Args = {
		{ Type = "playerId", Name = "jogador", Description = "Nome (online) ou UserId." },
		{ Type = "rankName", Name = "cargo", Description = "user, moderator ou staff." },
	},
}
