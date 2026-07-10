# FotosGDrive (Flutter)

App em Flutter que envia fotos de um álbum escolhido pelo usuário para
uma pasta com o **mesmo nome** no Google Drive, e deleta do dispositivo
após o upload ser confirmado.

No primeiro acesso, o app pede login na conta Google e o nome do álbum
(ex.: "Viagem 2026", "Aniversário da Ana"...). Esse nome fica salvo no
aparelho e é reaproveitado nas próximas aberturas.

Seu funcionamento pode ser visto em http://www.castellucci.net.br/fotosgdrive_walkthrough.html

O aplicativo esta disponivel em https://play.google.com/store/apps/details?id=com.fotosgdrive.app

## Antes de buildar

1. Copie `fotosgdrive-release.keystore` (o mesmo já usado na Play Store)
   para a raiz deste projeto. **Não commite esse arquivo.**
   
2. **Importante — Se udar Google Play App Signing**,
   é preciso cadastrar um **novo OAuth Client ID Android** no
   Google Cloud Console para o package `com.fotosgdrive.app` com esse
   mesmo SHA-1, com o escopo `drive.file` ativo.
   Não precisa colar Client ID nenhum no código — `google_sign_in` no
   Android valida direto por package name + SHA-1 do keystore.

## Build (100% via Docker, sem instalar Flutter local)

Duas formas de buildar, escolha a que preferir:

### Opção A — script direto (`docker-build.sh`)

```bash
./docker-build.sh
```

Builda a imagem a partir do `Dockerfile` e já gera `output/app-release.aab`
de uma vez, sem interação.

### Opção B — via Portainer + Console (`docker-compose.yml`)

Útil quando você quer acompanhar o build passo a passo ou rodar comandos
manualmente (`flutter doctor`, `flutter clean`, etc.) antes de gerar o AAB.

1. Coloque `fotosgdrive-release.keystore` na raiz do projeto (mesma pasta
   do `docker-compose.yml`).
2. No Portainer: **Stacks → Add stack**, cole o conteúdo de
   `docker-compose.yml` (ou aponte para o repositório Git) e **Deploy the
   stack**. O container `fotosgdrive-builder` sobe e fica parado, esperando
   comandos — ele não builda sozinho.
3. **Containers → fotosgdrive-builder → Console** (ícone `>_`), conectar
   com `/bin/bash`.
4. Dentro do container, rode tudo com um único comando:
   ```bash
   ./build.sh
   ```
   O `build.sh` confere se o keystore está no caminho certo
   (`$STORE_FILE`, por padrão `/app/fotosgdrive-release.keystore`) e se
   o alias/senha configurados realmente abrem esse keystore — falha
   com uma mensagem clara antes de gastar minutos rodando o Gradle à
   toa. Passando na checagem, ele mesmo roda `flutter clean`,
   `flutter pub get`, `flutter build appbundle --release` e copia o
   AAB gerado para a raiz do projeto (`app-release.aab`).
5. O `build.sh` termina copiando o AAB para a raiz do projeto dentro do
   container (`/app/app-release.aab`) — como esse caminho é o volume
   montado pelo `docker-compose.yml`, o arquivo já aparece direto na
   pasta do projeto no host, sem precisar de `docker cp`.

Na Opção A, o resultado é `output/app-release.aab` no host. Na Opção B,
é `app-release.aab` na raiz do projeto (host), graças ao `build.sh`.
Nos dois casos, o AAB está assinado com o keystore existente e pronto
para subir como atualização na Play Console (versão atual do projeto:
`1.0.11`).

## Estrutura

- `lib/services/auth_service.dart` — OAuth2 via `google_sign_in` (SDK
  nativo do Android, seletor de contas do Google Play Services); expõe
  um `http.Client` autenticado para a Drive API.
- `lib/services/drive_service.dart` — cria/reaproveita a pasta do
  álbum (nome escolhido pelo usuário), verifica duplicidade por nome
  antes de subir, upload multipart via `googleapis` Drive v3.
- `lib/services/media_service.dart` — lista fotos do álbum escolhido
  pelo usuário via `photo_manager` (MediaStore) e deleta localmente
  (`deleteWithIds`, que no Android 11+/14 dispara o dialog de
  confirmação do sistema). Mantém uma **imagem de controle** fixa
  (`assets/control_image.jpg`) que nunca é enviada nem excluída —
  existe só pra evitar que o álbum suma da galeria quando fica vazio
  (observado na Samsung). É criada automaticamente na primeira vez que
  o app tem permissão de fotos (após login ou antes de cada envio).
  **Identificada pelas dimensões fixas (640×640), não pelo nome do
  arquivo** — o Android não respeita de forma confiável o nome pedido
  no `saveImage` (salva com um nome numérico qualquer tipo
  `1783358322415.jpg`), então comparar por nome não funcionava e criava
  uma imagem nova a cada execução. `ensureControlPhoto()` também limpa
  duplicatas extras que tenham sobrado de antes dessa correção.
- `lib/services/album_config_service.dart` — persiste (via
  `shared_preferences`) o nome do álbum escolhido pelo usuário no
  primeiro acesso, para não perguntar de novo nas próximas aberturas.
- `lib/pages/onboarding_page.dart` — tela de primeiro acesso: login no
  Google + campo para digitar o nome do álbum/pasta a ser criado.
- `lib/theme/app_theme.dart` — paleta clara/azul (DM Sans via
  `google_fonts`), substituindo o visual escuro original de "log de
  terminal".
- `lib/pages/home_page.dart` — tela principal: cabeçalho gradiente,
  card de conta (avatar + e-mail + status), card do álbum atual
  (nome escolhido pelo usuário) com contagem de fotos e destino no Drive, card de progresso
  durante o envio, card de resultado (enviadas/removidas/falhas) ao
  concluir, aviso sobre exclusão só após confirmação. O log técnico
  detalhado continua existindo (útil pra depuração), mas fica recolhido
  em "Detalhes técnicos do processo" — discreto, não domina mais a
  tela. A versão do app (lida via `package_info_plus`, direto do
  `pubspec.yaml`) aparece no rodapé.

## O que ainda precisa de atenção antes de publicar

- Dois avisos que **não** dá pra resolver por aqui, porque dependem dos
  próprios plugins (não do nosso código):
  - `photo_manager` aplica o Kotlin Gradle Plugin diretamente, o que o
    Flutter avisa que vai parar de suportar ("Built-in Kotlin"). Só
    passa quando o mantenedor do `photo_manager` atualizar o plugin —
    não é algo pra mexer no `build.gradle` do projeto.
  - `warning: [options] source value 8 is obsolete` vem de dentro da
    configuração interna de algum plugin (não do nosso
    `compileOptions`, que já está em Java 17). Inofensivo, só some
    quando o plugin em questão atualizar a própria build.
- **Login em conta separada do celular:** o app usa `google_sign_in`
  (SDK nativo do Android). Ele mostra o seletor de contas já cadastradas
  no aparelho e, pra uma conta nova, aciona o fluxo "Adicionar conta ao
  dispositivo" do próprio Android — não há como evitar isso via código
  (é assim que qualquer app com login Google funciona no Android; ver
  seção "Limitação conhecida" abaixo).
- O MIME type do upload é detectado pela extensão do arquivo
  (`lib/utils/mime_utils.dart`), cobrindo JPG/JPEG, PNG, WEBP, GIF e
  HEIC/HEIF. Extensão desconhecida cai em `application/octet-stream`.

## Limitação conhecida: conta 100% nova no aparelho

Qualquer app Android que peça login Google — seja com `google_sign_in`
nativo, `flutter_appauth`/navegador, ou qualquer outra biblioteca —
esbarra na mesma regra do sistema operacional: uma conta que **nunca
foi usada naquele aparelho** precisa passar pelo fluxo "Adicionar conta
ao dispositivo" do Android em algum momento. Não é uma limitação da
nossa implementação; é assim que o Android/Google Play Services
funciona (chegamos a testar com `flutter_appauth` via navegador
esperando evitar isso, mas o Chrome faz exatamente o mesmo desvio pra
contas desconhecidas — ver
[issue #361 do AppAuth-Android](https://github.com/openid/AppAuth-Android/issues/361),
aberta desde 2018).

Dado que as duas abordagens têm essa mesma trava, ficamos com
`google_sign_in`: é bem mais simples (sem client_id/secret no código,
sem redirect URI pra derivar, sem JSON de credenciais separado) e o
resultado prático é idêntico.

**Mitigação prática:** use a conta de backup em qualquer app Google
nesse aparelho uma única vez (ex.: abrir o Gmail com ela e confirmar a
adição quando aparecer o aviso). A partir daí, todo login seguinte do
FotosGDrive com essa conta é direto, sem esse desvio.
