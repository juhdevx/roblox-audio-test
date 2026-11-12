# Console de admin (Cmdr) — place "filho"

Abra com **F2** no jogo. `help` lista tudo; `help <comando>` mostra os argumentos.
Atalhos de alvo: `.` = você · `*` = todos · `**` = os outros · `?` = aleatório.

## Cargos

| Nível | Cargo | Como ganha |
|---|---|---|
| 3 | Owner | `Owners` em `ServerStorage/Config/PermissionConfig` (fixo) |
| 2 | Staff | `rank <jogador> staff` (salvo no DataStore `Ranks_v1`) ou lista `Staff` do config |
| 1 | Moderator | `rank <jogador> moderator` ou lista `Moderators` |
| 0 | User | padrão |

Mínimo por grupo (`GroupMinimumTier`): Emote 2 · Media 2 · Staff 3 · Admin 2 · DefaultAdmin 2 · DefaultDebug 2 · DefaultUtil 1.
Exceções por comando (`CommandMinimumTier`): `auditdump`, `rank`, `unrank`, `ban`, `unban`, `gotoplace`, `takeall` exigem Owner.

## Grupo Emote

| Comando | Argumentos | O que faz |
|---|---|---|
| `giveemote` (`grantemote`) | jogador, emote | Libera um emote (nome com Tab, sem diferenciar maiúsculas). |
| `takeemote` (`revokeemote`) | jogador, emote | Remove a liberação. |
| `giveall` (`giveexclusives`) | jogadores, [categoria] | Libera **todos** de uma categoria. Padrão `exclusive` (inclui os vídeos). |
| `takeall` (`revokeall`) | jogadores, [categoria] | Remove todos da categoria; os emotes padrão ficam. |
| `playemote` (`forceemote`) | jogadores, emote | Toca o emote no jogador mesmo sem ele ter. |
| `stopemote` (`stopvideo`) | jogadores | Para o emote/vídeo atual. |
| `emotegrants` (`listemotes`) | jogador | Lista o que o jogador tem. |
| `clearemotes` | jogador | Limpa tudo que foi liberado. |

Categorias (`emoteCategory`): `all`, `default`, `exclusive`, `video`, `special`, `gamepass`, `syncable`, `traversal`.

## Grupo Media

| Comando | Argumentos | O que faz |
|---|---|---|
| `showvideo` (`playvideo`, `video`) | jogadores, vídeo | Avatar vira tela e o vídeo toca para todos verem. |
| `videos` (`listvideos`, `media`) | [jogador] | Lista os vídeos com resolução, FPS, duração e se o jogador tem. |
| `mediainfo` (`videoinfo`) | vídeo | Codec, quadros, partes, áudio espectral e modelo da dança. |

Exemplo: `showvideo * T7E3` · `giveall . video` · `stopemote *`.

## Grupo Staff

| Comando | Argumentos | O que faz |
|---|---|---|
| `rank` (`setrank`, `promote`) | jogador (nome ou UserId), cargo | Define `user`, `moderator` ou `staff`. Persistente. |
| `ranks` (`staff`, `listranks`) | — | Cargo de todos online. |

## Grupo Admin

`whoami` · `auditdump [n]` (últimos comandos, DataStore `CmdrAudit_v1`) · `reloademotes`.

## Onde fica o código

- Comandos: `ServerScriptService/Admin/Commands/{Admin,Emote,Media,Staff}` (definição + `*Server`).
- Tipos: `ServerScriptService/Admin/Types` (`emoteName`, `emoteCategory`, `videoEmote`, `rankName`, `accessKey`).
- Cargos: `Admin/Modules/Permissions`; regras: `ServerStorage/Config/PermissionConfig`.
- Toque forçado: `EmoteService.ForcePlay(player, name)`.
- Categoria de vídeo: `EmoteRegistry` marca `Video = true` quando `Song.Video` existe; a roda mostra `[ VIDEO ]`
  com o gradiente `StarterGui/MainUI/Resources/EmoteGradients/Video`.
