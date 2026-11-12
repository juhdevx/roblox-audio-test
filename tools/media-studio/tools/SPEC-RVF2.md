# RVF2 — formato de vídeo usado na versão avançada

RVF1 continua documentado em SPEC.md e é aceito pelo dispatcher. Uma mídia nova usa RVF2 por padrão. Os arquivos são little-endian, independentes por segmento e limitados a 4 MiB por segmento.

O cabeçalho tem 64 bytes: magic RVF2 em 0; versão u16 em 4 (1); tamanho do cabeçalho u16 em 6; bytes totais u32 em 8; Adler32 u32 em 12; largura/altura/FPS/quadros u16 em 16/18/20/22; primeiro quadro e total u32 em 24/28; quadros por segmento u16 em 32; paleta 0 em 34; encoding 2 em 36; tile 0 em 38; duração f32 em 40; bytes brutos por quadro u32 em 44; bits dos três canais u8 em 48/49/50; compressão Zstd=1 em 51; layout u8 em 52. Os bytes restantes são zero. O checksum trata os bytes 12..15 como zero.

Cada registro tem comprimento comprimido u32, comprimento bruto u32, modo u8, três bytes reservados zero e o bloco Zstd. Modo 0 substitui o quadro; modo 1 faz XOR com o quadro anterior; modo 2 aplica diferenças. O primeiro quadro do segmento deve ser completo. O comprimento descomprimido é verificado antes da descompressão.

O layout 1 usa YCbCr 4:2:0 com 6 bits por canal no perfil atual; o layout 0 permite RGBA quantizado. Limites públicos: dimensões entre 16 e 512, área até 512×288, 4..30 FPS e segmento de até quatro segundos. O conversor usa dois segundos por segmento e respeita a resolução original.

A interface do codec expõe Header, Begin, Step, Validate, Prepare/PrepareFor e Decoder.new. O decodificador expõe Step, Seek e Destroy. Prepare constrói a tabela de cor em pequenos intervalos; Step mantém a imagem anterior até o quadro estar pronto. O orçamento de CPU é cooperativo: uma operação nativa indivisível pode excedê-lo.

A entrada de vídeo inclui Width, Height, FPS, Frames, Duration, SegmentFrames, Segments, Encoding=2 e AudioTrack. O relógio vem da faixa de áudio. A definição é gerada em MediaLibrary, junto com a entrada de áudio e o emote. Não adicione um codec novo para cada vídeo.

Para validar uma conversão: execute codec_v2.py com o modo de validação ou use o Media Workbench. O manifesto registra SHA256, checksum, bytes e quadros por segmento. A comparação de qualidade usa a fonte redimensionada e não mede a perda causada por reduzir a resolução original.
