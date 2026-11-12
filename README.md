# Roblox audio test

Arquivo de teste: `woahuseit.mp3`.

Este repositório hospeda o áudio para verificar o download HTTP a partir do servidor do Roblox Studio. Não contém o código do player mostrado no vídeo de referência.

- Tamanho original: 2.762.429 bytes.
- SHA-256 original: `9c2adc851bf40cd02dd7ad9832b3f92cb519ce5278383014425db72257ac9675`.
- O arquivo é mantido no formato MP3 original, sem conversão para eventos musicais.

O teste de download e o teste de reprodução são etapas distintas. Um download bem-sucedido confirma o acesso ao arquivo; a reprodução dentro do Roblox depende de um backend de áudio compatível.

## Código do jogo e ferramentas (place "filho")

- `docs/COMANDOS.md` — referência do console admin (Cmdr, tecla F2): grupos Emote, Media, Staff e Admin.
- `tools/media-studio/` — fontes do conversor "Media Studio" (sem binários; o `ffmpeg` fica em `tools/bin` da pasta original).
- `tools/studio-export/` — espelha os scripts do Studio em `src/`:
  1. `py tools/studio-export/receive_sources.py` (fica ouvindo em 127.0.0.1:8765);
  2. no Studio, em modo Edit com HTTP ligado, rode `tools/studio-export/export_sources.luau` na Command Bar.
- `src/` — espelho dos scripts do place (`.server.luau`, `.client.luau`, `.luau`; módulos com filhos viram `init.luau`).
