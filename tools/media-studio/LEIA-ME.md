# Áudio e vídeo — versão avançada

A atualização já está aplicada no projeto aberto no Studio. O emote **YippeVideo** usa os arquivos completos de `yippevideo.mp4`, mantém a dança de PaniniEvent e transforma o avatar em uma tela no mundo, visível dos dois lados. Parar, morrer ou trocar o emote restaura a aparência.

## O que foi corrigido

O carregamento travava porque a pasta havia sido trocada para `v3`, mas os links ainda usavam commits antigos em que essa pasta não existia. As configurações agora vêm de uma única definição de mídia e usam o commit `352f014ce93cd3683c250256bb73aa96ac34b094`, conferido com os arquivos reais.

- Imagem: **384×216, 20 FPS**, 3.308 quadros, 165,4 segundos completos. São 2,25 vezes mais pixels por quadro e 33% mais quadros por segundo que a versão 256×144/15 FPS.
- Compressão: cores em YCbCr e Zstd nativo; quadros completos, diferenças e XOR. A imagem preserva mais gradientes e contornos, com 76,5 MB de vídeo contra 48,4 MB antes. A versão antiga continua compatível.
- Áudio: perfil de fidelidade com **128 vozes/60 FPS** no computador; limite de 48 vozes preservado no celular. Corrigida a recuperação de vozes cujo sample deixa de estar disponível temporariamente.
- Reprodução: relógio compartilhado para áudio e imagem, carregamento antecipado, checksum, cache e tentativas limitadas. A preparação ao equipar agora mostra progresso e encerra com uma mensagem se falhar.
- Importação: respeita a resolução original e ajusta a duração do áudio para cobrir também os quadros finais do vídeo.
- Novas mídias: assistente local, três perfis, lotes de envio organizados e **um único instalador**, com backup e conferência do conteúdo hospedado antes de alterar o Studio.

## Resultado do teste no Studio

Teste individual no computador: preparação de **3,40 segundos**, reprodução por **182,77 segundos**, incluindo a repetição; **zero underruns de áudio**, zero amostras em buffering e dois quadros pulados em 3.656 apresentados. Maior diferença de relógio nas amostras: 0,074 segundo. Cabeça e torso voltaram à transparência original, a tela foi removida e a prévia parou corretamente.

As 272 verificações isoladas de integração passaram. O instalador conferiu manifestos e primeiras/últimas partes reais no GitHub. Uma versão inexistente foi rejeitada sem alterar fontes nem criar instâncias. Os relatórios completos estão nos arquivos `AdvancedRuntimeValidation.json`, `IntegrationRegressionValidation.json` e `AudioQualityValidation.json`.

## Adicionar uma música ou vídeo

1. Abra **StartMediaWorkbench.cmd** e deixe a janela aberta. Use a página local que aparecer.
2. Escolha o arquivo, escreva um nome único e selecione a qualidade. Em **Destino e regras do emote**, escolha a dança de referência e o desbloqueio. Ordem **0** escolhe a próxima posição automaticamente.
3. Clique em **Converter e preparar pacote**. Baixe e extraia o pacote pronto. A prévia do assistente mostra o original; a reconstrução deve ser conferida no Studio.
4. Envie os arquivos de cada pasta **UploadBatches**, um lote por vez, pelos links indicados. Cada lote tem até 20 arquivos/18 MiB. Finalize cada lote em **Commit changes**.
5. Depois do último envio, cole o SHA completo do commit em **Fixar o commit** e baixe o instalador atualizado. Isso evita misturar arquivos de versões diferentes.
6. Pare o Play no Studio, abra **View > Command Bar**, cole TODO o arquivo **StudioImport.luau** e execute. O instalador confere a mídia hospedada antes de fazer alterações. Inicie um novo Play.

Você não precisa mais editar VideoTracks, SpectralTracks e um módulo de emote para cada mídia. O instalador cria:

- `ServerStorage > MediaLibrary > Nome` — ModuleScript com metadados e URLs privadas.
- `ReplicatedStorage > Shared > MediaLibrary > Nome` — ModuleScript com as regras públicas do emote.

Para atualizar um nome existente, use a mesma capitalização e marque **Atualizar nome existente e guardar backup**. Use uma pasta nova no GitHub para cada versão. As permissões e a posse de emotes continuam sob validação do servidor.

Para remontar os lotes do teste YippeVideo, use **Já tenho uma conversão nesta pasta**. O pacote geral contém os arquivos canônicos de vídeo em `generated/YippeVideo/upload` e de áudio em `generated/YippeVideo/audio/upload`; o assistente gera novamente os lotes numerados.

O guia `MEDIA_WORKBENCH.md` detalha o assistente. `MIGRACAO.md` lista TODOS os caminhos, tipos e a ordem dos scripts completos em `Scripts/`.

## Recuperação

As fontes anteriores às alterações desta sessão estão em `ServerStorage > BeforeMediaUpgrade_20261024`. Importações posteriores guardam definições substituídas em `ServerStorage > MediaLibraryBackups`. A mídia local antiga ficou preservada em `generated/backups/YippeVideo_before_20261024` e não é necessária para a reprodução atual.

Se o carregamento falhar, confira o nome, a pasta e o commit, e se todos os lotes foram enviados. Não troque apenas `v2` por `v3` num link antigo. O instalador agora identifica esse erro antes da importação. HTTP deve estar habilitado no Studio.

## Limites e alternativas

Áudio e vídeo continuam sendo reconstruções, não reprodução direta do MP4/MP3 original. O estudo de áudio encontrou melhoria modesta no erro espectral; não é uma promessa de som idêntico. O vídeo consome em média cerca de 452 KiB/s, além de aproximadamente 63 KiB/s de áudio. O cache de vídeo tem limite de 96 MiB. Prefira o perfil Mais leve quando dados e desempenho forem prioridade.

A comparação visual em `QualityV2/Comparison.png` usa os mesmos instantes do original. Em 16 instantes medidos numa referência comum de 384×216, o PSNR passou de 28,74 para 36,90 dB e o SSIM de 0,9004 para 0,9850. São medidas de imagem, não testes de celular ou capacidade de um servidor cheio.

Um vídeo publicado como asset na plataforma é a alternativa para maior fidelidade nativa. Esta versão mantém o requisito de hospedar os dados fora do Roblox; nenhum áudio/vídeo foi enviado para a plataforma e a experiência não foi publicada.

## Checklist no Studio

- [ ] Abrir prévia e equipar YippeVideo; conferir progresso e começo do som.
- [ ] Ver a imagem dos dois lados da Part e confirmar o avatar invisível.
- [ ] Assistir até o final e conferir repetição e sincronização.
- [ ] Parar, trocar de emote, pular e morrer; confirmar aparência restaurada.
- [ ] Entrar com outra conta e testar sincronização; exclusivos exigem posse no servidor.
- [ ] Testar em celular e com vários jogadores, incluindo jogadores entrando atrasados.
- [ ] Importar uma mídia nova com nome único; conferir ordem e desbloqueio.
- [ ] Conferir volume em fones antes de disponibilizar para todos.
