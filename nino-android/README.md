# Nino de Bolso (Android)

O Nino é um bichinho virtual que anda por cima dos seus apps no Android. Ele conversa com você, cria lembretes que tocam na hora, lembra do que você conta, olha a sua tela quando você deixa e dá dicas sozinho.

## Instalar

1. Baixe `release/Nino.apk` no celular.
2. Abra o arquivo. Se o Android pedir, permita instalar apps dessa origem (navegador ou gerenciador de arquivos).
3. Abra o **Nino** e siga a seção **Pra ele ficar com você**:
   - **Aparecer sobre outros apps**: obrigatório, é o que deixa ele andar pela tela.
   - **Notificações**: para os lembretes tocarem com o app fechado.
   - **Cérebro de IA**: a chave da API (veja abaixo).
   - **Não deixar o celular fechar o Nino**: opcional, ajuda em celulares que economizam bateria demais.
4. Toque em **Soltar o Nino na tela**.

## Cérebro de IA

O Nino usa o Claude pela API da Anthropic, com a sua chave:

1. Crie uma chave em [console.anthropic.com](https://console.anthropic.com), na seção **API Keys**.
2. Cole a chave no app e toque em **Testar**.

O uso da API é cobrado por mensagem na sua conta da Anthropic, separado de qualquer assinatura do claude.ai. O modelo padrão é o Claude Opus 5.5. Nos ajustes você pode trocar para o Sonnet 5.5 ou para o Haiku 5.5, que é bem mais barato. A chave fica só no celular.

Sem chave, o Nino continua brincando, comendo, dormindo e lembrando das suas tarefas. Só não conversa nem entende a tela.

## Como brincar com ele

| Gesto | O que acontece |
| --- | --- |
| Tocar | Abre o menu: Conversar, Olhar a tela, Comer, Brincar, Dormir, Esconder e Guardar |
| Tocar duas vezes | Carinho, com coraçõezinhos |
| Segurar | Abre a conversa direto |
| Arrastar e soltar | Ele voa, quica e cai no chão. Dá para jogar ele longe! |

Ele tem barriga, energia e alegria, que mudam com o tempo. Também sobe de nível, a folhinha cresce e no nível 5 nasce uma flor. Ele dorme de noite e acorda quando descansa.

## O que ele faz sozinho

- **Lembretes de verdade**: peça na conversa ("me lembra de tomar remédio às 21h"). Vira um alarme com notificação, mesmo com o app fechado, e o Nino pula na tela para avisar.
- **Bom dia**: no primeiro desbloqueio da manhã ele te cumprimenta e conta quantos lembretes você tem.
- **Pausas**: depois de uma hora seguida de tela, sugere uma pausa. Depois da meia-noite, sugere dormir.
- **Bateria**: avisa quando está fraca e comemora quando você carrega.
- **Puxar assunto**: curiosidades, perguntas e lembranças do que você contou. A frequência é ajustável e dá para deixar em silêncio.
- **Ajuda automática com a tela** (opcional): com a visão ligada, ele espia a tela de tempos em tempos (só quando ela mudou) e só fala se tiver algo útil, como um golpe suspeito, uma tradução, um resumo ou uma dica.

## Olhar a tela

Toque em **Olhar a tela** no menu. O próprio Android pede permissão e mostra que a tela está sendo compartilhada. Escolha **Tela inteira** para ele ajudar em qualquer app. A visão vale até você tocar em **Parar** no aviso do Android ou reiniciar o celular. Apps protegidos, como os de banco, aparecem pretos para ele.

As imagens da tela só vão para a IA da Anthropic quando o Nino olha (por pedido seu ou pela ajuda automática que você ligou). Conversas, tarefas e memórias ficam no celular.

## Limites

- Só funciona no Android 8 ou mais novo. O iPhone não permite apps andando por cima de outros apps.
- Alguns celulares (Xiaomi, Samsung e outros) fecham apps em segundo plano. Se o Nino sumir sozinho, libere o app em **Bateria → Sem restrições**.
- A voz usa o leitor de texto do próprio celular. Para falar com ele, use o microfone da conversa.

## Compilar

Requer JDK 17 ou mais novo e o Android SDK 35:

```bash
echo "sdk.dir=/caminho/para/android-sdk" > local.properties
./gradlew assembleRelease
# APK em app/build/outputs/apk/release/app-release.apk
```

O APK é assinado com a chave de depuração em `app/debug.keystore` (senha `android`), guardada no repositório para que toda versão nova instale por cima da anterior sem apagar os dados. É uma chave de uso pessoal: não use esta assinatura para publicar o app em loja.
