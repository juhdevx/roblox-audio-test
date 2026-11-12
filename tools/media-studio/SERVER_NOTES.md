# Servidor de vídeo externo

O vídeo continua no GitHub. O servidor baixa apenas os segmentos registrados, valida o formato RVF1 e envia os dados aos clientes. Nenhum MP4 é enviado ao Roblox.

## Ordem de instalação

1. Criar `ReplicatedStorage > Shared > VideoSequence` com os ModuleScripts `Config` e `Format`.
2. Criar `ServerScriptService > VideoSequence` com os ModuleScripts `VideoTracks`, `VideoCatalog`, `Downloads` e `Transport`.
3. Criar o ModuleScript `ServerScriptService > Services > VideoSequenceService`.
4. Adicionar o serviço à lista do bootstrap. Chamar `Init(dependencies)` antes de `Start()` e `Destroy()` no encerramento.

Os módulos `ReplicatedStorage > Shared > AudioSequence > Protocol` e `LRU` já presentes no projeto são reutilizados. Os remotes `ReplicatedStorage > Remotes > VideoSequence > Request` e `Data` são criados e validados pelo serviço.

## Protocolo

- Cliente envia `Manifest`, `Load(id)`, `Ack(token)`, `Repair(token, indices)` ou `Cancel(id)`.
- Servidor responde com `Manifest`, `Header`, `Chunk` ou `Error(id, message)`.
- ID de segmento: `YippeVideo_0000`, com quatro dígitos e índice inicial zero.
- URLs nunca são recebidas do cliente. O manifesto público não inclui URLs.
- O receptor existente de AudioSequence aceita o cabeçalho e os chunks de 8 KiB.

## Limites

- Até 512 KiB/s de payload por jogador e 4 MiB/s de payload por servidor para vídeo, independentes do orçamento de áudio.
- Segmentos de até 2 MiB e uma transferência ativa por jogador.
- Cache do servidor de até 64 MiB, expiração em cinco minutos e downloads concorrentes deduplicados.
- Até três downloads simultâneos e 40 tentativas HTTP por minuto no serviço de vídeo.
- A validação confere checksum, estrutura e correspondência com as dimensões, quadros e posição do registro.
- Cancelar ou sair do servidor invalida respostas pendentes. Reiniciar o serviço também invalida tarefas anteriores.

## Adicionar outro vídeo

Depois de converter e hospedar os arquivos, adicionar uma entrada em `VideoTracks` e associar `Song.Video` no módulo do emote. Usar o campo `AudioTrack` para apontar para a faixa convertida do mesmo vídeo. Preferir a revisão fixa do GitHub gerada após o upload.

## Verificação

`ServerValidation.json` registra os testes de segurança, limites, cache, cancelamento e reinicialização. Eles exercitam os módulos reais com dependências controladas e não substituem os testes completos no cliente.
