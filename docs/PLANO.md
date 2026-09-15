# Plano — BKmasterplayer 🎵 (player de música multiplataforma)

## Contexto

Queremos um player de música próprio, open source, que:
- rode em **PC (Linux primeiro, Windows depois)**, depois **Android** e mais pra frente **iOS/macOS** (quando tiver um Mac);
- toque de **servidores de streaming open source**, principalmente o **Navidrome** (API Subsonic/OpenSubsonic), e depois outros (Gonic, Ampache, LMS, Jellyfin...);
- seja compatível com o **AudioMuse-AI** (análise sônica por IA) pelo plugin do Navidrome, e também pela API direta dele;
- tenha **customização completa** (tema, layout, comportamento, áudio);
- tenha **transição automática estilo DJ** (beatmatching por BPM, alinhamento de compasso/frase, tom harmônico, time-stretch sem mudar o tom), aberta e configurável.

A pasta do projeto está vazia. Este arquivo é o documento central: na Fase 0 ele vira `docs/PLANO.md` no repositório.

---

## Status (14/09/2026): PC (Linux) completo · Android completo (com Android Auto e Festa)

Legenda: ✅ feito e testado · 🔶 parcial · ⏳ próximo

| Fase | Status |
|---|---|
| 0. Setup | ✅ repo, licença MIT (era GPL-3.0 até 14/09), Navidrome de teste em Docker, gerador de músicas com gabarito |
| 1. MVP Linux | ✅ login, biblioteca, busca, streaming com cache, fila, gapless, MPRIS com capa |
| 2. Player completo | ✅ ReplayGain, EQ, crossfade, letras, favoritos, playlists, fila salva/sincronizada, offline, mini player, bandeja, atalhos |
| 3. AudioMuse | ✅ via Navidrome (Mix instantâneo, rádio sônica, caminho sônico, rádio infinita) · ⏳ API direta (busca por texto/CLAP, Alchemy, Music Map) |
| 4. Customização | ✅ Personalização gráfica total: cores (paleta, contraste, cores à mão), fontes, formas, fundo (gradiente/capa/imagem), estrutura das telas (abas, player flutuante), animações; galeria com 8 temas prontos, temas próprios, arquivos de tema/backup e backups automáticos. O padrão continua idêntico ao visual original |
| 5. AutoMix DJ | ✅ análise (Beat This!), grade, tom, estrutura, planejador, time-stretch, estilos, configurações, modelo por potência |
| 6. Windows | ⏳ |
| 7. Android | ✅ APK arm64 (Android 8+): tudo do PC menos bandeja/mini player, com notificação de mídia, botões do fone/Bluetooth, foco de áudio, AutoMix, Festa por Bluetooth e Android Auto; instalado no celular (Galaxy M35, Android 16) · ⏳ Festa entre dois celulares reais, Android Auto num carro/DHU, análise econômica |
| 8. iOS/macOS | ⏳ |

### Medições (testes automatizados)
- **Gapless:** saída idêntica, amostra por amostra, à concatenação dos arquivos (FLAC e MP3). Com conversão 44,1→48 kHz, sem emenda (o conversor passa de uma faixa para a outra).
- **Análise:** BPM exato nas faixas confiáveis; fase da grade com erro de até 7 ms; intro/outro no compasso certo. Faixas duvidosas são marcadas como não confiáveis e não são sincronizadas.
- **AutoMix (sintético):** bumbos da faixa que entra alinhados aos da que sai em ~1 ms, com e sem time-stretch.
- **AutoMix (música real, 76 faixas do Mandragora em ordem de BPM, `examples/eval_mix`):** 61 de 75 transições sincronizadas no modelo pequeno (58 no completo); nas que têm bateria clara dos dois lados, 16 de 18 a ±10 ms, mediana 2–3 ms. As não sincronizadas são quase todas BPM distante demais (eco no compasso) ou faixas sem batida regular.
- **Equalizador:** ganho medido a ±0,7 dB do pedido em cada banda.

### Pedidos do usuário atendidos
- Capa em qualquer controle de mídia: MPRIS com `file://`, testado com KDE Connect ligado.
- Notificação de troca de música que nunca empilha e sempre aparece (KDE Plasma testado).
- AutoMix totalmente configurável, com os padrões já no melhor ajuste.
- Duração da transição quando a música não é clara.
- Modelo de análise escolhido pela potência do aparelho.
- Segue a saída padrão do sistema (Bluetooth), sem travadas.
- Nome **BKmasterplayer 🎵** (antes BKplayer, BKT Player e BK Music Player; trocado em 14/09); aba "Músicas" com a biblioteca inteira; botão do AutoMix que liga/desliga na barra.
- Botões da caixa Bluetooth (JBL): o app se registra direto no BlueZ como player AVRCP (o `mpris-proxy` foi desativado com `systemctl --user mask mpris-proxy`, porque entregava os botões ao primeiro player registrado, ex.: o celular via KDE Connect).
- Álbum tocado em ordem só fica sem mixagem se o áudio for contínuo (ao vivo, mixado); álbuns com silêncio entre as faixas são mixados.
- Backup do estado de 13/09 em `~/Documentos/BKplayer-backup-2026-09-13` e na tag git `backup-2026-09-13`.

### Android (14/09)
- **Motor em Rust no celular:** o cpal abre o áudio pela AAudio, que precisa da JVM e do `Context`. O Dart carrega a biblioteca por FFI (`dlopen`), sem JVM; por isso o `BkApplication` (Kotlin) carrega o motor antes com `System.loadLibrary` e entrega o `Context` pelo JNI (`app/rust/src/android.rs`). Mínimo Android 8.0 (API 26, onde a AAudio começa).
- **C++ do time-stretch:** liga no `libc++_shared.so` do NDK, que o Flutter não empacota; o Gradle copia do NDK para as ABIs do build.
- **Serviço de mídia:** `audio_service` + `audio_session` (`lib/mobile/media_session.dart`): notificação com capa (do cache local, sem a URL com o token), tela de bloqueio, botões do fone/caixa Bluetooth, pausa em ligação e quando o fone desconecta, volume abaixado para o GPS. Na pausa o serviço sai do primeiro plano e solta o wake lock.
- **audio_service corrigido** (`app/third_party/audio_service`, ver `BKPLAYER.md`): botão de mídia com o serviço fora do primeiro plano derrubava o app (ANR "startForegroundService() did not then call startForeground()"). Testado no emulador: pausar/tocar/próxima/anterior/parar em segundo plano, sem ANR.
- **Bateria:** o motor suspende o stream de áudio depois de 10 s parado (vale também no PC).
- **Tela:** navegação de baixo com Início, Buscar, Biblioteca (álbuns, músicas, artistas, playlists, gêneros, favoritos, downloads) e Ajustes; "voltar" do Android volta para a aba de origem; botão do AutoMix no mini player.
- **Cache e downloads** ficam na pasta de dados do app (o Android esvazia a pasta de cache quando falta espaço).
- **Gerar o APK:** `./dev/build_apk.sh` → `dist/bkplayer_<versão>_arm64.apk` (~22 MB, bibliotecas comprimidas). Assinado com a chave `~/.android/bkplayer-release.jks` (senha em `app/android/key.properties`, fora do git): **guardar backup**, sem ela as próximas versões não instalam por cima.
- **Emulador de teste:** AVD `bk_test` (Android 15 x86_64) com o Navidrome de teste em `http://10.0.2.2:4534`.

### Endereço de casa e Connect (14/09)
- **Endereço de casa:** a conta tem um endereço opcional da rede local (login e Ajustes). O app usa esse endereço quando o `ping` dele responde (~1,5 s no máximo). Volta ao principal na primeira chamada que falhar e testa de novo quando a rede muda (Wi-Fi/dados), quando o app volta ao primeiro plano e a cada 45 s fora de casa. Ao trocar, a próxima faixa é reagendada pelo endereço novo; o cache não muda, porque as chaves são por conta. Teste: `test/local_address_test.dart`.
- **BKmasterplayer Connect** (`lib/connect/`), tocar e controlar entre aparelhos da mesma conta:
  - **Descoberta:** anúncio UDP (porta 47801) com id, nome, plataforma, porta e hash do usuário. Pela internet (ex.: Tailscale), dá para "Adicionar pelo endereço".
  - **Controle:** WebSocket (TCP 47800). O aparelho controlado confere as credenciais no próprio servidor (`ping` com o token de quem controla), com limite de tentativas.
  - **Uso:** o botão "Aparelhos" abre "Tocar em". Se o outro aparelho já toca, passa a controlá-lo; se está parado, a fila daqui vai para lá do mesmo ponto. "Este aparelho" traz a música de volta e pausa lá.
  - **Testado:** PC (instância de teste) controlado por script e pelo app no emulador (conectar, play, próxima, pausar, trazer de volta).

### Músicas do aparelho e Last.fm (14/09)
- **Sem servidor:** no login, "Usar só as músicas do aparelho" (ou pastas nos Ajustes). O motor lê tags, duração, ReplayGain e capa (embutida ou da pasta) com índice incremental (76 faixas reais em 2,7 s; 1 ms na releitura). `LocalProvider` (`lib/data/local/`) monta álbuns, artistas, gêneros, busca sem acento, favoritos, execuções, playlists e letras `.lrc`.
- **Last.fm** (chave grátis do usuário, Ajustes): músicas e artistas parecidos para o mix e a rádio quando não há AudioMuse (casados com o servidor ou com as músicas do aparelho), mais tocadas e bio do artista (`lib/data/lastfm.dart`, `similar.dart`).

### Festa (14/09; chamada de "Jam" no código)
Nome trocado de "Jam" para "Festa" (em inglês, "Party") para não confundir com a marca do Spotify. No código continua `jam` (arquivos, rotas, protocolo), que não aparece para quem usa.
Ouvir junto com quem está perto: os convidados adicionam músicas e controlam o que toca no aparelho do dono (`lib/jam/`).
- **Entrada só com aprovação:** cada pedido aparece em qualquer tela ou na notificação (Recusar / Aceitar / "Aceitar sempre"). Ninguém entra sozinho, a não ser quem está na lista de aceitos automaticamente (editável nos Ajustes).
- **Meios:** rede local (anúncio UDP + WebSocket `/jam` e upload `/jam/upload` no servidor do Connect) e, no Android, Bluetooth/Wi-Fi Direct (Nearby Connections, `JamNearby.kt`), que dispensa Wi-Fi em comum (convidado no 4G). A lógica é a mesma nos dois (`JamLink`).
- **Músicas:** "Adicionar" busca nas músicas do dono pelo próprio dono (o convidado não precisa de conta no servidor dele); "Minhas" manda do servidor do convidado (MP3 320), do aparelho ou de um arquivo, como arquivo, pelo meio mais rápido que o Nearby negociar. O dono só toca o que ele mesmo mostrou ou recebeu como arquivo (nunca um caminho vindo do convidado).
- **Beacon:** com a Festa aberta, o dono anuncia por Bluetooth LE; o convidado tem um scan econômico registrado no sistema (funciona com o app fechado) e recebe "Tem uma Festa do BKmasterplayer perto de você" (no máximo a cada 30 min).
- **Sem conta:** "Entrar numa Festa por perto" direto no login.
- **Testado:** no emulador e na instância de teste do PC, com scripts no papel do outro lado (recusar, aceitar, aceitar sempre, busca, adicionar, controlar, arquivo de 3,5 MB). Falta testar entre dois celulares reais (Nearby e beacon).

### Modo DJ (14/09)
"Modo DJ a partir desta música" (menu da música; botão na fila): o AudioMuse e o AutoMix escolhem juntos a próxima pelo melhor encaixe (`lib/player/dj_mode.dart`).
- **Candidatas:** parecidas do AudioMuse (ou Last.fm/servidor), sem repetir o que já tocou.
- **Nota:** 45% parecença + 30% andamento (inclui meio/dobro do tempo, dentro do que o time-stretch alcança) + 25% tom na roda Camelot, com penalidade para o mesmo artista ou um recente.
- **Análise:** o motor analisa as 5 melhores (BPM e tom) enquanto sobra tempo antes do fim da atual; nos dados móveis, só as que não precisam ser baixadas. Com cache, a escolha sai em ~1 s.

### Android Auto e o caminho para o CarPlay (14/09)
- **Navegação no carro** (`lib/mobile/auto_browser.dart`): abas Início (aleatórias, Modo DJ e mix da atual, favoritas, mais tocados, álbuns aleatórios), Recentes, Álbuns (grade) e Playlists; tocar uma música toca a pasta a partir dela. Busca na tela do carro, pedido de voz ("tocar X no BKmasterplayer", com o foco em artista/álbum/música), "Continuar ouvindo" e fila (janela de 100 em volta da atual).
- **Capas:** o carro só aceita `content://`. O `BkArtProvider` serve pela chave; a URL com o token fica num arquivo privado do app.
- **Aberto pelo carro com o app fechado:** o serviço espera o login e a fila salva antes de responder.
- **Testado** no emulador com um cliente MediaBrowser próprio (navegar, capas lidas por outro app, busca, voz, tocar por id, pular na fila, abertura a frio). Para ver a tela do carro: Android Auto no celular → Configurações → tocar 10× na versão → "Iniciar servidor da unidade principal"; no PC, `adb forward tcp:5277 tcp:5277` e `~/android-sdk/extras/google/auto/desktop-head-unit`.
- **CarPlay (quando houver o Mac):** a árvore do `AutoBrowser` não depende do Android. No iOS, um adaptador de templates (`CPTabBarTemplate` com as mesmas abas, `CPListTemplate` para pastas, `CPNowPlayingTemplate`) chama `children`, `search`, `resolve` e `voice` e toca pelo mesmo `PlayerController`. Exige o entitlement `com.apple.developer.carplay-audio` pedido à Apple.

### Outros (14/09)
- **Celular deitado e tablet:** barra lateral compacta no celular deitado; layout de computador no tablet (menor lado ≥ 600 dp), com barra lateral e botões do player que rolam; tocando agora com pouca altura põe a capa ao lado dos controles.
- **Logo pelo tema:** `BkLogo` desenhada com as cores do tema ativo (nunca some no fundo); abertura do Android clara/escura conforme o aparelho.
- **Baixar a biblioteca inteira** (Downloads): mostra quantas músicas e o tamanho, avisa nos dados móveis; depois vira "Baixar as novas".
- **Letras e capas que faltam:** letras do LRCLIB (sincronizadas) e do Musixmatch (API oficial, com a chave do usuário, com o aviso de direitos e o rastreio que os termos pedem); capas do Cover Art Archive (MusicBrainz) e do Deezer para as músicas do aparelho. A fonte aparece embaixo da letra; liga/desliga nos Ajustes. (iTunes e lyrics.ovh saíram em 14/09 por causa dos termos de uso; ver `docs/JURIDICO.md`.)
- **Opus e outros formatos que o motor não decodifica:** o servidor converte para MP3 automaticamente, também no download offline.

### Ajustes em telas e Personalização gráfica (14/09)
Pedido do usuário: cada tipo de configuração na própria tela e tudo da aparência modificável, com o visual original como padrão (*"gostei da aparência original, só quero ter como modificar tudo se alguém quiser"*).
- **Ajustes** (`lib/ui/pages/settings/`): lista de categorias com resumo (Conta e servidor, Personalização gráfica, Reprodução, AutoMix, Downloads e cache, Letras/capas/Last.fm, Aparelhos e Festa, Comportamento, Computador, Sobre); cada uma abre em `/settings/<categoria>` com a seta de voltar. Comportamento ganhou o idioma (Sistema/Português/English); Sobre mostra as licenças (inclusive das fontes).
- **Tema = aparência + estrutura** (`UiPrefs.themeJson()`, `lib/data/ui_prefs.dart`); comportamento (toque na música, tela inicial) fica de fora. Migração única dos campos que ficavam nas configurações gerais (modo, cor, cor da capa, escala).
- **Editores** (`look_page.dart`, 7 áreas): cores (modo, AMOLED, capa ou fixa, cor base com seletor HSV/hex, 9 estilos de paleta do Material, contraste, cores à mão), fontes de título e texto (Nunito, Space Grotesk, JetBrains Mono, Playfair Display, Bebas Neue — OFL, embutidas), formas e tamanhos, fundo (liso, gradiente, capa desfocada, imagem própria + cor do tema por cima), tocando agora, estrutura (abas do celular 2–4 + Ajustes, abas da barra lateral, rótulos, player grudado/flutuante, botões, seções do Início) e animações. Cada escolha marca a opção original.
- **Galeria** (`theme_gallery.dart`): miniaturas desenhadas com cada tema; 8 prontos (BKmasterplayer original, AMOLED, Vinil, Neon, Papel, Terminal, Alto contraste, Automático) e os do usuário (salvar, duplicar, renomear, salvar mudanças, exportar, excluir); ✓ no tema em uso e ✱ quando foi mexido.
- **Backup** (`lib/data/theme_library.dart`): tema em `.bktheme.json` e backup completo em `.bkbackup.json` (imagens de fundo dentro, em base64), pelo seletor de arquivos do sistema; backups automáticos (os 10 últimos) antes de trocas grandes; tudo validado ao importar.
- **Garantia do visual original:** teste compara o tema padrão com o antigo campo a campo (`test/app_theme_test.dart`) e as telas no emulador ficaram iguais pixel a pixel.

### Análise no servidor: BK Analyzer (15/09)
Pedido do usuário: *"igual a análise sônica fica salva no server e o celular já vai ter a informação das músicas"*, com um painel do status e das músicas que não deram, usando a CPU do notebook (i7) como o AudioMuse.
- **Binário `bk-analyzer`** (`app/rust/src/bin/bk_analyzer/`, feature `analyzer-server`; o build do app não muda). Usa o mesmo código de análise do app.
  - `serve` (coordenador, no PC do Navidrome):
    - lê a biblioteca pela API Subsonic (`search3`, só leitura, a cada hora); a senha vira token md5 e não é guardada;
    - fila por favoritas e mais tocadas; o que um player pede vai para a frente;
    - guarda as análises em `~/.local/share/bk-analyzer/analyses/`;
    - se um trabalhador some no meio, a música volta para a fila (até 3 tentativas).
  - `worker` (trabalhador): baixa o arquivo pelo coordenador, que repassa do Navidrome e converte para MP3 o que o app também recebe convertido. Analisa com o modelo completo, várias ao mesmo tempo, com nice 15, e pausa na bateria.
  - Instalação como serviço do systemd de usuário: `dev/install_analyzer.sh`.
- **Painel** (`dashboard.html`, `http://<pc>:4540`):
  - login com a conta do Navidrome (a primeira configuração só pela rede de casa);
  - barra da biblioteca por resultado, ritmo e previsão de término, trabalhadores, o que está sendo analisado e as últimas analisadas;
  - lista por categoria com o motivo e as grades, busca e "tentar de novo";
  - "Pausar análise" (a música do momento termina) e, por trabalhador, pausar e "músicas ao mesmo tempo" (até o máximo que ele anunciou, 8 no i7). Vale na hora: é o coordenador que limita, pelo `Retry-After` da fila;
  - trabalhador reiniciado (sessão nova) devolve na hora à fila o que deixou no meio, sem contar tentativa.
- **App:**
  - `TrackSource.analysisUrl` com o login da conta, só quando o arquivo tocado é o mesmo analisado (original, ou o MP3 que o servidor converte);
  - o motor pergunta ao servidor antes de analisar, guarda num cache à parte (`<chave>|server`) e prefere essa análise à local;
  - se o servidor está analisando a música, espera até ~30 s; se estiver fora do ar, para de perguntar por 2 min;
  - se a análise do servidor chega depois de a transição estar planejada, planeja de novo (se faltar mais de 8 s);
  - no painel do AutoMix aparece "análise do servidor";
  - em Ajustes → AutoMix → Servidor de análise ficam o endereço, o teste (quantas analisadas, trabalhadores ligados) e o link do painel.
- **Regras novas de sincronia** (valem na hora de planejar, também para análises antigas; o coordenador recalcula as categorias ao abrir):
  - grade estável com poucas janelas quando todas travam e há outra prova: grade confirmada pelas duas pontas, ou erro < 6 ms (intro sem bateria, faixa curta ou lenta);
  - áudio muito travado (80% de 6+ janelas) dispensa a concordância batida a batida da rede (funk, percussão sincopada);
  - **transição no compasso** (`bar_plan` em `automix.rs`) quando não dá para sincronizar: A ecoa (ou corta) num compasso dela e B entra no 1º compasso dela, cada uma no seu tempo. Os compassos saem da grade estável ou dos downbeats regulares da rede; cada ponto sai da própria faixa (regra da patente).
- **Resultado em 100 músicas sorteadas da biblioteca do usuário** (modelo completo, no i7): antes, 56 sincronizavam e 37 ficavam na transição simples. Agora:
  - **63 sincronizam** e **20 trocam no compasso**;
  - 11 servem numa ponta só;
  - 6 ficam na transição simples (Dream Theater ao vivo, com fórmula de compasso mudando, intro sem batida, sax solo).
  - As mixagens sincronizadas continuam precisas: mediana de 6 ms (`eval_mix --cache`).
- **Celular × PC** (`dev/phone_diag.sh`, 15/09): as batidas saem idênticas (12 faixas do Mandragora, 100% a ±5 ms, diferença máxima de 0 ms, mesmo BPM, 11 de 12 confiáveis nos dois) e o tempo é parecido (~20 s por faixa). O processador ARM não era a causa da pouca batida confiável no celular: eram as regras (música tocada, poucas janelas), que as regras novas resolvem também na análise local.
- **Ferramentas:** `examples/tune.rs` roda a rede uma vez por faixa e refaz o resto a cada mudança (~20 s para 100 faixas); `eval_mix --cache` mixa com essas batidas.
- **Ritmo no i7-1355U:**
  - No perfil "Economia de energia" (~1,6 GHz): ~280 músicas/h, igual com 2 ou 3 análises ao mesmo tempo.
  - No perfil "Desempenho", com 4 ao mesmo tempo: ~480 músicas/h, a biblioteca de 5.363 em ~11 h.
  - Com 6 ao mesmo tempo, ou com a rede nas 12 threads (`RTEN_NUM_THREADS`; o padrão do rten é o número de núcleos físicos), o ritmo fica igual: o limite de energia do chip (15 W) é o teto, não a CPU parada.
  - O trabalhador usa 1 análise a cada 3 threads (até 4) e a rede em todas as threads.

### Limitações conhecidas
- **Opus:** o symphonia não decodifica. Do servidor, o app pede a conversão para MP3 sozinho; arquivos Opus do aparelho (modo sem servidor) ainda não tocam (há decodificadores Opus em Rust puro para avaliar).
- **AAC (m4a):** o silêncio de "priming" (~23 ms) não é cortado. O AutoMix mede no áudio decodificado, então as batidas continuam alinhadas.
- **Análise:** decodifica a faixa inteira na memória (~130 MB por faixa de 4 min), também no Android (fazer só nas regiões usadas ⏳).
- **Android com o app fechado** (processo encerrado): o botão da caixa/fone não abre o app; abra e toque uma vez.
- **Mixer do KDE:** mostra o stream como "cpal-pulseaudio-PID" (o nome do cliente vem do cpal).
- **Letras:** mostradas por linha; karaokê palavra por palavra (letras v2 do Navidrome 0.63) ⏳.
- **AutoMix em intro sem bumbo:** se B entra por uma intro sem bateria clara, a fase local não é medida ali; em 2 de 18 transições medidas os elementos da intro ficaram ~30–40 ms à frente dos bumbos de A.
- **Modelo completo x pequeno:** na música real, os dois têm confiabilidade parecida (cada um erra em faixas diferentes); o completo não é automaticamente melhor.
- **Análise do servidor com qualidade limitada:** se o app pede o stream convertido (limite de bitrate), o arquivo tocado difere do analisado (atraso do codificador) e o app analisa no aparelho.
- **Servidor de análise fora de casa:** o painel e a API ficam na rede local; para o celular usar na rua, é preciso expor a porta 4540 (ex.: um Funnel da Tailscale numa porta extra). Sem isso, as análises já baixadas continuam no cache do aparelho.
- **"TO MYSELF" (Louie Zong):** a grade passa nas regras, mas a mixagem medida saiu 56 ms fora; investigar.

### Próximos passos
1. **Testes com aparelhos reais:** Festa entre dois celulares (Nearby e beacon; o Bluetooth do PC ajuda), Android Auto no DHU ou no carro.
2. **Windows:** build, SMTC com a janela do Flutter, instalador (MSIX ou Inno Setup), WASAPI.
3. **Android:** análise econômica (só Wi-Fi/carregando, só as regiões usadas); Opus local.
4. **AudioMuse API direta** (precisa do token): busca por texto, Alchemy, Music Map.
5. **CarPlay** (com o Mac), **Jellyfin** como segundo provedor; karaokê palavra por palavra; editor de smart playlist; estatísticas/retrospectiva; Chromecast/DLNA.

---

## 1. Decisão de stack (recomendada)

**Flutter (UI em todas as plataformas) + núcleo de áudio em Rust** (ligados pelo `flutter_rust_bridge` v2).

Por quê:
- **Flutter**: uma base de código para Linux, Windows, Android, iOS e macOS. Portar do PC pro Android vira "adaptar layout e integração com o sistema", não reescrever. O sistema de temas facilita a customização completa.
- **Motor em Rust** (em vez de só usar mpv/media_kit): o AutoMix DJ precisa de **2 decks tocando ao mesmo tempo, time-stretch em tempo real, EQ por deck e alinhamento no nível da amostra**, e o mpv não faz isso (ele toca um arquivo por vez). Além disso o `media_kit` está em "manutenção limitada" desde nov/2025. Em Rust temos bibliotecas maduras e com licença permissiva:
  - `symphonia` (decodificação MP3/FLAC/AAC/ALAC/Vorbis/WAV), `cpal` (saída de áudio: ALSA/PipeWire, WASAPI, AAudio, CoreAudio), `rubato` (resample), `rustfft` (visualizador), `ebur128` (loudness).
  - `beat-this` (MIT, Rust puro, sem dependência de sistema): detecção de batida e downbeat, estado da arte (ISMIR 2024). Leva ~4,6 s por faixa de 4,5 min em CPU (M4).
  - `signalsmith-stretch` (MIT): time-stretch que preserva o tom, leve o bastante para rodar em celular (o Rubber Band é pesado demais pra mobile e o SoundTouch lida mal com transientes).
- Alternativas descartadas: Tauri 2 (áudio em segundo plano no mobile é frágil), Compose Multiplatform (áudio no desktop JVM é fraco), Electron (pesado, sem mobile).

**Dart/Flutter:** Riverpod (estado), go_router (rotas), drift/SQLite (cache da biblioteca, análises, configurações), dio (HTTP), window_manager, tray_manager, hotkey_manager, audio_service (mídia em segundo plano no Android/iOS).
**Rust:** motor, streaming e cache de arquivo, DSP, análise e AutoMix. Controles de mídia no desktop pelo `souvlaki` (MPRIS no Linux, SMTC no Windows, macOS).
**Licença:** MIT (trocada da GPL-3.0 em 14/09/2026, para publicar no GitHub). As dependências são MIT/Apache/BSD/MPL e são compatíveis (ver `docs/JURIDICO.md`).

---

## 2. Arquitetura

```
player-musica/
├─ docs/PLANO.md                  ← este plano
├─ app/                           ← Flutter
│  └─ lib/
│     ├─ core/        (DI, config, logs, i18n pt-BR/en)
│     ├─ domain/      (Song, Album, Artist, Playlist, Queue, ServerCapabilities)
│     ├─ data/
│     │  ├─ providers/subsonic/   (OpenSubsonic: auth, browse, search, stream URL, lyrics, playQueue, playbackReport, sonicSimilarity)
│     │  ├─ providers/audiomuse/  (API direta, opcional)
│     │  ├─ providers/jellyfin/   (futuro)
│     │  └─ db/                   (drift: cache da biblioteca, análises, settings, temas)
│     ├─ features/    (library, player, queue, search, lyrics, playlists, audiomuse, automix, settings, customization, stats)
│     └─ ui/          (theme engine, layout engine, widgets)
└─ native/                        ← crate Rust "engine"
   └─ src/
      ├─ api.rs              (funções expostas ao Flutter via FRB)
      ├─ stream.rs           (download HTTP progressivo → arquivo de cache, com range requests)
      ├─ decoder.rs          (symphonia; Opus: libopus ou transcodificação no servidor)
      ├─ deck.rs             (Deck A/B: posição, velocidade, EQ, ganho)
      ├─ mixer.rs            (soma dos decks, curvas de crossfade equal-power, limiter)
      ├─ dsp/                (EQ paramétrico biquad, ReplayGain, preamp, limiter, filtros HPF/LPF, eco)
      ├─ stretch.rs          (signalsmith-stretch)
      ├─ output.rs           (cpal, escolha de dispositivo)
      ├─ analysis/           (beats, downbeats, BPM, tom, energia, loudness, intro/outro, frases)
      └─ automix/            (planner de transição + executor)
```

**Interface de servidor (adapter):** `MusicServerProvider` com as capacidades detectadas em tempo de execução. Para OpenSubsonic, chamar `getOpenSubsonicExtensions` (não exige autenticação) no login e ligar/desligar recursos da UI conforme o que o servidor suporta: `sonicSimilarity`, `songLyrics`, `playbackReport`, `transcoding`, `apiKeyAuthentication`, `indexBasedQueue`, `formPost`.

**Fluxo de reprodução:** o Flutter manda (URL de stream + auth) → o Rust baixa pro cache enquanto toca → decodifica → deck → mixer → saída. Esse mesmo arquivo em cache alimenta a análise do AutoMix. O motor já nasce com **2 decks**, mesmo antes do AutoMix existir, pra não precisar refatorar depois.

---

## 3. Integração Navidrome + AudioMuse-AI

**Nível 1: pelo Navidrome (sem configuração extra)**
- Requisitos: Navidrome **≥ 0.62** (a versão atual é 0.64) com o plugin **AudioMuse-AI-NV-plugin** ativo.
- `getSimilarSongs2`: Instant Mix / rádio a partir de uma música.
- `getArtistInfo2`: artistas parecidos.
- Extensão `sonicSimilarity`:
  - `getSonicSimilarTracks(id, count)`: retorna `sonicMatch[] { entry, similarity 0–1 }`.
  - `findSonicPath(startSongId, endSongId, count=25)`: um "caminho sônico" entre 2 músicas (começa na primeira e termina na segunda).
  - Se a extensão não for anunciada, o servidor responde 404, então a UI esconde esses recursos.
- **Rádio infinita:** quando a fila está acabando, completa com `getSonicSimilarTracks` (sem repetir e respeitando os filtros do usuário).

**Nível 2: API direta do AudioMuse-AI (opcional, recursos avançados)**
- Configuração: URL do AudioMuse + `API_TOKEN` (header `Authorization: Bearer <token>`).
- Recursos: busca por texto/CLAP ("piano calmo", "rock energético"), Song Alchemy (somar/subtrair músicas), Music Map (mapa 2D da biblioteca), Sonic Fingerprint (playlist pelo seu gosto), busca por letra/tema.
- Tarefa da Fase 3: levantar os endpoints exatos no Swagger da sua instância (`http://<audiomuse>:8000/apidocs/`) e confirmar como os IDs do AudioMuse mapeiam para os IDs de música do Navidrome.
- O AudioMuse também guarda tempo, tom e energia por faixa. Se houver endpoint pra ler isso, usar como **dica inicial** pro AutoMix.

---

## 4. AutoMix DJ: transição automática sincronizada por BPM

**Referências:** Apple Music AutoMix (iOS 26: beatmatching + time-stretch + escolha do momento no downbeat), Auto DJ do Mixxx (intro/outro como seções), sistema de auto-DJ de Vande Veire & De Bie (batida → downbeat → segmentação → cue → transição com EQ).

### 4.1 Análise por faixa (Rust, em segundo plano, com cache no SQLite)
| Dado | Como |
|---|---|
| Batidas + downbeats | `beat-this` (modelo pequeno de 10 MB por padrão; completo de 83 MB como opção no desktop) |
| BPM + confiança, grade de batidas | derivados das batidas (mediana dos intervalos), com detecção de meio tempo/tempo dobrado |
| Frases (8/16/32 compassos) | contagem a partir dos downbeats + curva de novidade/energia por compasso |
| Tom (key) + Camelot | cromagrama + perfis Krumhansl-Schmuckler em Rust (ou tom do AudioMuse/tags como dica) |
| Loudness (LUFS) | `ebur128`, para igualar o volume dos 2 decks |
| Energia por compasso | RMS/espectro, usado pra achar intro, outro, drops e quedas |
| Primeiro/último som | detecção de silêncio (corta silêncio no começo e no fim) |

- Tabela `track_analysis`: `server_id+song_id`, `analyzer_version`, bpm, beats/downbeats (f32 comprimido), key, camelot, lufs, energy_per_bar, intro_end, outro_start, phrases, first/last_sound.
- **Quando analisar:** as próximas N músicas da fila assim que forem pré-carregadas. Opcionalmente, varredura da biblioteca quando o PC estiver ocioso. No Android, só no Wi-Fi e carregando (opção).
- Dicas grátis: o campo `bpm` do OpenSubsonic (tags) e os dados do AudioMuse.

### 4.2 Planner de transição (decide o "como" e o "quando")
1. **Ponto de saída da faixa A:** início da frase de outro (queda de energia), ou a última frase antes de um outro longo, sempre em limite de 8/16/32 compassos.
2. **Ponto de entrada da faixa B:** primeiro downbeat do intro. A duração é `min(outro A, intro B)`, arredondada pra 8/16/32 compassos.
3. **Tempo:**
   - Diferença de BPM ≤ limite (padrão **±8%**, configurável): time-stretch em B até o BPM de A durante a mixagem, depois **rampa suave** de volta ao BPM original de B em 8–16 compassos.
   - Relação 2:1 (ex.: 87 ↔ 174): mixa em meio tempo/tempo dobrado.
   - Diferença grande demais: fallback sem beatmatch (eco, filtro ou corte seco no downbeat).
4. **Harmonia (roda Camelot):**
   - Mesmo tom, ±1 número, ou troca maior/menor: blend longo.
   - Tons incompatíveis: transição curta com filtro/bass-swap pra esconder o choque.
5. **Fase:** alinhar o downbeat de B com o downbeat de A no nível da amostra. Durante a mixagem, corrigir a deriva a cada batida usando as duas grades (micro-ajuste da taxa de stretch).

### 4.3 Estilos de transição (o executor no mixer)
- **Blend com bass swap** (padrão pra música eletrônica/dançante): o grave de B começa cortado. No downbeat do meio da mixagem, troca em 1 batida (corta o grave de A e libera o de B). Volumes em curva equal-power.
- **Filter sweep:** HPF subindo em A, LPF abrindo em B.
- **Echo out:** eco/delay sincronizado ao BPM no final de A, B entra no downbeat.
- **Corte no downbeat:** troca seca e precisa.
- **Crossfade inteligente:** para gêneros sem batida clara ou quando a análise não está pronta (corta silêncio + curva equal-power).
- **Auto:** escolhe o estilo pelo ΔBPM, pela compatibilidade de tom, pela energia e pela confiança da análise.

### 4.4 Regras e UI
- **Não mixar** em álbum gapless tocado em ordem, em álbuns ao vivo, música clássica, podcast ou audiobook (detectado automaticamente e configurável).
- **Modo "DJ set" (opcional):** reordena a fila futura pra fluir em BPM/tom/energia, combinado com o AudioMuse (músicas similares e mixáveis).
- Configurações: liga/desliga, estilo, stretch máximo, tamanho preferido (8/16/32 compassos), mixagem harmônica sim/não, exceções por gênero/álbum.
- UI: indicador "Mixando…", waveform dos 2 decks com a grade de batidas (tela "nerd" opcional), BPM e tom na tela Tocando Agora.

---

## 5. Customização completa

- **Motor de temas por tokens (JSON):** cores, fontes, tamanhos, cantos, espaçamento, blur, opacidade e animações. Presets claro/escuro/AMOLED. **Cor dinâmica extraída da capa.** Importar/exportar `.json`; no futuro, uma galeria de temas da comunidade.
- **Layout:**
  - Painéis encaixáveis e reordenáveis no desktop (sidebar, fila, letra, tocando agora, visualizador).
  - Escolher quais botões aparecem na barra do player e em que ordem.
  - Presets da tela Tocando Agora: capa grande, letra ao lado, vinil, minimalista, visualizador.
  - Densidade da grade, formato da capa, escala da interface, mini player.
- **Comportamento:** atalhos de teclado remapeáveis, gestos, ação do duplo clique, tela inicial, ordem padrão de ordenação.
- **Áudio:** EQ gráfico e paramétrico com presets (perfis AutoEQ no futuro), modo ReplayGain (faixa/álbum/off), crossfade/AutoMix, dispositivo de saída.
- **Perfis:** salvar a configuração inteira como perfil, exportar e importar.

---

## 6. Outras ideias (para você aprovar; marcadas por prioridade)

**MVP** = primeira versão usável · **v1** = versão completa no PC · **Futuro**

- **Reprodução:** gapless (MVP), ReplayGain (v1), sleep timer (v1), velocidade de reprodução (v1), histórico da fila (v1), shuffle inteligente sem repetir artista seguido (v1).
- **Biblioteca:** álbuns, artistas, gêneros, anos, gravadoras e moods (MVP/v1); work/movement pra clássica (OpenSubsonic, v1); favoritos e notas (MVP); playlists com CRUD (MVP); editor de smart playlist do Navidrome (v1); busca com filtros (MVP); tocadas recentes e mais tocadas (v1).
- **Letras:** sincronizadas LRC (v1), karaokê palavra por palavra e múltiplas vozes (letras v2 do OpenSubsonic, Navidrome 0.63+, v1), tela cheia (v1).
- **Sincronização:** fila entre dispositivos via `savePlayQueue`/`getPlayQueue` ("continuar no celular", v1); `playbackReport` para scrobble e "tocando agora" (v1); vários servidores e contas (v1).
- **Offline:** cache automático e download de álbuns/playlists com limite de espaço; transcodificação diferente pra Wi-Fi e dados móveis (v1 no PC, essencial no Android).
- **Integração desktop:** MPRIS e teclas de mídia (MVP), bandeja do sistema e mini player "sempre no topo" (v1), Discord Rich Presence (v1), atalhos globais (v1), notificações (v1).
- **Capa do álbum em qualquer controle de mídia (pedido do usuário, MVP):** a capa precisa aparecer em tudo que controla o player:
  - **Linux:** MPRIS com `mpris:artUrl` apontando para um **arquivo local** (`file://…`, capa baixada num cache). É isso que KDE Connect/GSConnect enviam pro celular, e também aparece nos widgets do KDE/GNOME. Bluetooth PC→carro via BlueZ `mpris-proxy`, onde o suporte de capa depende do BlueZ/carro.
  - **Windows:** miniatura no SMTC (Phone Link, overlay de volume).
  - **Android:** `MediaSession` com o bitmap da capa, que chega ao carro via Bluetooth AVRCP 1.6 e ao Android Auto, além da tela de bloqueio e do relógio.
  - **iOS:** `MPNowPlayingInfoCenter` com artwork (CarPlay).
- **Notificação de troca de música no PC (pedido do usuário, MVP):**
  - Opção liga/desliga nas configurações; mostra título, artista e capa.
  - **Não empilha:** trocando várias vezes seguidas, fica só 1 notificação, sempre atualizada. Linux: `org.freedesktop.Notifications` com `replaces_id` da anterior. Windows: toast com a mesma tag/grupo.
- **Mobile:** tocar em segundo plano e controles na tela de bloqueio (Fase Android), Android Auto, widgets, Chromecast/DLNA (Futuro).
- **Visual:** visualizador de espectro, seekbar em forma de waveform, fundo animado com blur da capa (v1).
- **Estatísticas:** estatísticas de escuta e "Retrospectiva" anual (Futuro).
- **Controle remoto:** controlar o player do PC pelo celular na rede local (Futuro).
- **Extras:** rádios online e podcasts (endpoints Subsonic, Futuro), compartilhar via `createShare` (Futuro), arquivos locais sem servidor (Futuro), Jellyfin nativo (Futuro), acessibilidade e i18n pt-BR/en desde o início.

---

## 7. Roadmap por fases

| Fase | Entrega |
|---|---|
| **0. Setup** | Instalar Flutter, Rust e flutter_rust_bridge, mais as dependências Linux (`clang cmake ninja-build pkg-config libgtk-3-dev libasound2-dev`). `git init`, licença, CI simples. `docker-compose` de teste com Navidrome 0.64 + AudioMuse-AI + biblioteca de músicas livres (CC). Copiar este plano pra `docs/PLANO.md`. |
| **1. MVP Linux** | Login no Navidrome (token salt+md5 e extensão API key), navegar pela biblioteca, buscar, tocar pelo motor Rust (streaming + cache), fila, gapless, MPRIS e teclas de mídia, tema claro/escuro, configurações salvas. |
| **2. Player completo** | ReplayGain, EQ, crossfade simples (2 decks), letras, favoritos e notas, playlists, `playbackReport`, sincronizar fila, offline/cache, mini player, bandeja, atalhos. |
| **3. AudioMuse** | Instant Mix, músicas sonicamente similares, tela de "caminho sônico" (escolher 2 músicas), rádio infinita. Conexão direta: busca por texto (CLAP), Alchemy, Music Map. |
| **4. Customização** | Motor de temas e de layout, presets, importar/exportar, cor dinâmica, perfis. |
| **5. AutoMix DJ** | Pipeline de análise + cache, planner, estilos de transição, regras, UI. Ajuste fino com o conjunto de testes (seção 9). |
| **6. Windows** | Build, SMTC, instalador (MSIX ou Inno Setup), testes com WASAPI. |
| **7. Android** | Layouts responsivos, audio_service (serviço em primeiro plano + MediaSession), cpal/AAudio, downloads, economia de bateria na análise, Android Auto. |
| **8. iOS/macOS** | Quando tiver o Mac: build, AVAudioSession, conta Apple Developer. |

---

## 8. Riscos e cuidados

- **Análise no celular é mais lenta:** usar o modelo pequeno, analisar antes da hora, manter cache e usar dicas de BPM/tom das tags e do AudioMuse. O fallback é o crossfade inteligente.
- **Pra analisar a próxima faixa é preciso baixá-la inteira antes:** tranquilo no Wi-Fi. Em dados móveis, deixar configurável.
- **Opus não é suportado nativamente pelo symphonia:** usar binding do libopus ou pedir transcodificação ao servidor.
- **Endpoints da API direta do AudioMuse:** confirmar no Swagger antes de implementar (podem mudar entre versões).
- **iOS:** exige Mac, e a conta Apple Developer paga pra distribuir.
- **Compatibilidade:** testar também com Gonic e Ampache pra não depender de coisas específicas do Navidrome.

---

## 9. Verificação (como testar de ponta a ponta)

- **Ambiente:** `docker compose up` (Navidrome + AudioMuse). Conferir `curl '<navidrome>/rest/getOpenSubsonicExtensions?f=json'` e ver se `sonicSimilarity` aparece.
- **Rust (`cargo test`):**
  - crossfade com precisão de amostra;
  - resposta em frequência do EQ;
  - ReplayGain;
  - precisão das batidas num conjunto anotado (`beat_this_annotations` ou um subconjunto próprio);
  - regras da roda Camelot;
  - planner com casos fixos: 120→124 BPM, 87→174, tons incompatíveis, faixa sem batida.
- **Métrica objetiva do AutoMix:** erro de alinhamento de batida durante a mixagem (correlação cruzada dos onsets dos 2 decks), meta **< 10 ms**, e ausência de clipping (pico ≤ -1 dBTP).
- **Flutter (`flutter test`):** cliente Subsonic com fixtures gravadas + testes de integração contra o Navidrome local; widget tests da customização.
- **Manual (`flutter run -d linux`):**
  - login, tocar, álbum gapless sem clique entre faixas;
  - MPRIS via `playerctl status/next`;
  - Instant Mix e caminho sônico;
  - sessão de escuta de 1 h com AutoMix ligado, anotando transições ruins.

---

## 10. Fontes principais

- OpenSubsonic, extensões: https://opensubsonic.netlify.app/docs/extensions/ · findSonicPath: https://opensubsonic.netlify.app/docs/endpoints/findsonicpath/
- Navidrome, PR sonicSimilarity (0.62): https://github.com/navidrome/navidrome/pull/5419 · release 0.63: https://github.com/navidrome/navidrome/releases/tag/v0.63.0 · plugins: https://www.navidrome.org/docs/usage/features/plugins/
- AudioMuse-AI: https://github.com/NeptuneHub/AudioMuse-AI · plugin do Navidrome: https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin · autenticação: https://neptunehub.github.io/AudioMuse-AI/AUTH/ · algoritmo: https://neptunehub.github.io/AudioMuse-AI/ALGORITHM/
- AutoMix / DJ: https://musictech.com/news/gear/apple-music-automix-ai/ · https://mixxx.org/news/2020-07-09-intro-outro-sections/ · https://lenvdv.github.io/2018-03-20-autodj/
- Bibliotecas: https://github.com/danigb/beat-this-rs · https://github.com/CPJKU/beat_this · https://crates.io/crates/signalsmith-stretch · https://pub.dev/packages/audio_service · https://pub.dev/packages/media_kit
- Players de referência: Feishin https://github.com/jeffvli/feishin · Musly https://github.com/dddevid/musly · Finamp https://github.com/finamp-app/finamp · Symfonium https://docs.symfonium.app/wiki/
