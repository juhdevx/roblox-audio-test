# Migração e scripts completos

Este pacote atualiza o projeto existente. Preserve os módulos e assets do projeto que não estão nesta lista. Cada arquivo .luau em Scripts contém a fonte COMPLETA, pronta para colar no objeto com o mesmo caminho. Não cole um módulo dentro de outro.

A atualização já foi aplicada nesta sessão. Esta ordem serve para migrar outra cópia do mesmo projeto:

1. Pare Play e guarde uma cópia do projeto.
2. Aplique módulos compartilhados e os módulos de servidor/cliente.
3. Aplique os pontos de entrada Main e a tela EmoteWheel.
4. Crie as duas pastas MediaLibrary e importe a definição com generated/YippeVideo/StudioImport.luau.
5. Inicie um novo Play e execute o checklist de LEIA-ME.md.

Crie como Folder, se faltarem: ReplicatedStorage > Shared > VideoSequence; ReplicatedStorage > Shared > MediaLibrary; ServerStorage > MediaLibrary; ServerScriptService > VideoSequence; StarterPlayer > StarterPlayerScripts > VideoSequence. Utils, Registries e os demais sistemas já existem no projeto. Não há objetos do projeto para renomear ou apagar.

## Caminhos, tipos, alteração e fase

- **ReplicatedStorage > Shared > MediaLibrary > YippeVideo** — ModuleScript; fase 4. Definição do teste; a biblioteca atualiza áudio, vídeo e regras de câmera.
- **ReplicatedStorage > Shared > Registries > EmoteRegistry** — ModuleScript; fase 2. Integra os módulos de MediaLibrary ao registro existente e preserva a validação de nomes/ordem.
- **ReplicatedStorage > Shared > Registries > Emotes > DAVE** — ModuleScript; fase 2. Mantém a definição da música e dança existente.
- **ReplicatedStorage > Shared > Registries > Emotes > Drakeone** — ModuleScript; fase 2. Mantém a definição da música e dança existente.
- **ReplicatedStorage > Shared > Registries > Emotes > TestSound** — ModuleScript; fase 2. Mantém o emote de teste de áudio já existente.
- **ReplicatedStorage > Shared > Registries > Emotes > YippeVideo** — ModuleScript; fase 2. Definição do teste; a biblioteca atualiza áudio, vídeo e regras de câmera.
- **ReplicatedStorage > Shared > SpectralAudio > Config** — ModuleScript; fase 2. Concentra limites de transferência, memória, renderização e reprodução.
- **ReplicatedStorage > Shared > SpectralAudio > Format** — ModuleScript; fase 2. Valida os dados; no vídeo seleciona o codec correspondente sem quebrar arquivos antigos.
- **ReplicatedStorage > Shared > SpectralAudio > Tests** — ModuleScript; fase 2. Verificações nativas dos formatos de dados.
- **ReplicatedStorage > Shared > Types** — ModuleScript; fase 2. Tipos públicos de áudio/vídeo e descritores de emotes.
- **ReplicatedStorage > Shared > Utils > MediaLibrary** — ModuleScript; fase 2. Carrega definições e reúne faixas e emotes; novas mídias entram como dados.
- **ReplicatedStorage > Shared > VideoSequence > CodecV1** — ModuleScript; fase 2. Preserva o decodificador de vídeos antigos RVF1.
- **ReplicatedStorage > Shared > VideoSequence > CodecV2** — ModuleScript; fase 2. Valida e reconstrói quadros modernos, usando Zstd e trabalho incremental.
- **ReplicatedStorage > Shared > VideoSequence > CodecV2Tests** — ModuleScript; fase 2. Verifica formatos, limites, diferenças de quadros, busca e limpeza.
- **ReplicatedStorage > Shared > VideoSequence > Config** — ModuleScript; fase 2. Concentra limites de transferência, memória, renderização e reprodução.
- **ReplicatedStorage > Shared > VideoSequence > Format** — ModuleScript; fase 2. Valida os dados; no vídeo seleciona o codec correspondente sem quebrar arquivos antigos.
- **ReplicatedStorage > Shared > VideoSequence > Metadata** — ModuleScript; fase 2. Compartilha os limites de resolução, tempo e formato entre servidor e cliente.
- **ReplicatedStorage > Shared > VideoSequence > Tests** — ModuleScript; fase 2. Verificações nativas dos formatos de dados.
- **ServerScriptService > AudioSequence > Downloads** — ModuleScript; fase 2. Limita downloads, valida arquivos e reutiliza o cache do servidor.
- **ServerScriptService > AudioSequence > SpectralCatalog** — ModuleScript; fase 2. Expande e valida o catálogo autorizado de áudio.
- **ServerScriptService > AudioSequence > SpectralTracks** — ModuleScript; fase 2. Mantém as faixas antigas e incorpora as definições privadas de MediaLibrary.
- **ServerScriptService > AudioSequence > Transport** — ModuleScript; fase 2. Envia partes com limites de taxa, reparo e custo por jogador.
- **ServerScriptService > Main** — Script; fase 3. Inicialização fina dos serviços/controladores; preserva a ordem de Init/Start.
- **ServerScriptService > Services > RemoteService** — ModuleScript; fase 2. Inicializa os remotes centralizados de áudio/vídeo.
- **ServerScriptService > Services > SpectralAudioService** — ModuleScript; fase 2. Coordena catálogo, download e transporte do áudio no servidor.
- **ServerScriptService > Services > VideoSequenceService** — ModuleScript; fase 2. Coordena catálogo, download e transporte do vídeo no servidor.
- **ServerScriptService > Services > VideoWorldService** — ModuleScript; fase 2. Cria a Part, oculta o avatar com autoridade do servidor e restaura a aparência.
- **ServerScriptService > VideoSequence > Downloads** — ModuleScript; fase 2. Limita downloads, valida arquivos e reutiliza o cache do servidor.
- **ServerScriptService > VideoSequence > Transport** — ModuleScript; fase 2. Envia partes com limites de taxa, reparo e custo por jogador.
- **ServerScriptService > VideoSequence > VideoCatalog** — ModuleScript; fase 2. Valida metadados RVF1/RVF2 e publica somente os campos necessários ao cliente.
- **ServerScriptService > VideoSequence > VideoTracks** — ModuleScript; fase 2. Mantém vídeos antigos e incorpora as definições privadas de MediaLibrary.
- **ServerStorage > MediaLibrary > YippeVideo** — ModuleScript; fase 4. Definição do teste; a biblioteca atualiza áudio, vídeo e regras de câmera.
- **StarterPlayer > StarterPlayerScripts > Controllers > EmoteAudioController** — ModuleScript; fase 2. Encaminha sons espectrais ao controlador e preserva sons nativos.
- **StarterPlayer > StarterPlayerScripts > Controllers > EmoteController** — ModuleScript; fase 2. Mantém o pedido ao servidor e a preparação conjunta antes de tocar o emote.
- **StarterPlayer > StarterPlayerScripts > Controllers > MediaPreparationController** — ModuleScript; fase 2. Prepara os dois fluxos em paralelo; mostra progresso e encerra falhas/cancelamentos.
- **StarterPlayer > StarterPlayerScripts > Controllers > SpectralAudioController** — ModuleScript; fase 2. Escolhe a fonte, carrega o áudio, fornece o relógio e diagnósticos da reprodução.
- **StarterPlayer > StarterPlayerScripts > Controllers > VideoSequenceController** — ModuleScript; fase 2. Carrega, valida, prepara e desenha os quadros seguindo o relógio do áudio.
- **StarterPlayer > StarterPlayerScripts > Main** — LocalScript; fase 3. Inicialização fina dos serviços/controladores; preserva a ordem de Init/Start.
- **StarterPlayer > StarterPlayerScripts > SpectralAudio > MixBus** — ModuleScript; fase 2. Mantém a saída seca, controle de ganho e proteção de picos.
- **StarterPlayer > StarterPlayerScripts > SpectralAudio > NoiseBank** — ModuleScript; fase 2. Reconstrói as bandas residuais do áudio.
- **StarterPlayer > StarterPlayerScripts > SpectralAudio > PhaseTracking** — ModuleScript; fase 2. Mantém a continuidade e a correção de fase das vozes.
- **StarterPlayer > StarterPlayerScripts > SpectralAudio > Renderer** — ModuleScript; fase 2. Renderiza áudio ou imagem; recupera samples temporariamente indisponíveis e libera recursos.
- **StarterPlayer > StarterPlayerScripts > SpectralAudio > ValidationActor > Main** — LocalScript; fase 3. Inicialização fina dos serviços/controladores; preserva a ordem de Init/Start.
- **StarterPlayer > StarterPlayerScripts > SpectralAudio > Validator** — ModuleScript; fase 2. Coordena a validação de áudio sem bloquear a interface.
- **StarterPlayer > StarterPlayerScripts > SpectralAudio > ValidatorWorker** — ModuleScript; fase 2. Executa o trabalho incremental de validação de áudio.
- **StarterPlayer > StarterPlayerScripts > UI > Screens > EmoteWheel** — ModuleScript; fase 3. Integra prévia, progresso e mensagens de falha ao catálogo existente.
- **StarterPlayer > StarterPlayerScripts > VideoSequence > Renderer** — ModuleScript; fase 2. Renderiza áudio ou imagem; recupera samples temporariamente indisponíveis e libera recursos.

Novas mídias são importadas em dois ModuleScripts gerados a partir da mesma configuração. A definição privada contém os endereços; a pública contém apenas o emote. Não modifique os remotes para adicionar uma música.

Backups de fontes desta migração: ServerStorage > BeforeMediaUpgrade_20261024. Backups de definições do instalador: ServerStorage > MediaLibraryBackups.
