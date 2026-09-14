# BKmasterplayer: licenças, marcas, patentes e termos de serviço

Levantamento feito em 14/09/2026, antes de publicar o app no GitHub com licença MIT. É uma triagem técnica, **não é parecer jurídico**. Para lançamento comercial ou nos EUA, vale revisar com um advogado de propriedade intelectual.

## Resumo

| Tema | Situação | O que fazer |
|---|---|---|
| Direito autoral do código do app | ✅ código próprio | ✅ licença MIT no repositório |
| Arquivos recebidos na Festa | ✅ temporários | ✅ apagados ao abrir o app e ao começar outra Festa |
| Bibliotecas usadas (≈580) | ✅ todas compatíveis com MIT | ✅ avisos no app (Sobre → Licenças), inclusive Rust e Android |
| Fontes, ícones, modelo de IA | ✅ licenças livres | manter os textos das licenças (já estão no app) |
| Capas pela internet | ✅ iTunes retirado (os termos proibiam) | ✅ Cover Art Archive (MusicBrainz) + Deezer |
| Letras pelo lyrics.ovh | ✅ retirado (copiava de outros sites) | ✅ feito; o cache antigo é ignorado |
| Letras pelo Musixmatch | ✅ nos termos | ✅ aviso de direitos e rastreio de exibição; a letra não é guardada no disco |
| Letras pelo LRCLIB | ⚠️ banco comunitário; as letras têm dono | ✅ fonte mostrada embaixo da letra; dá para desligar |
| Last.fm | ✅ não comercial, com crédito | ✅ "Dados do Last.fm" com link (artista e Ajustes) |
| Deezer (capas) | ✅ uso não comercial permitido | dar o crédito |
| Nome "Jam" | ✅ trocado por "Festa" | feito |
| Nomes "Connect", "AutoMix", "Modo DJ" | ✅ baixo risco | ✅ comparações com Spotify/Apple tiradas do README e do plano |
| Nome "BKmasterplayer" (antes BKplayer, BKT Player, BK Music Player) | ✅ nenhum app com esse nome achado; há "MasterPlayer" sem o "BK" | pesquisar no INPI antes de divulgar |
| Patentes de transição automática | ✅ a única ativa (Spotify, EUA, até 2031) exige um passo que o app não faz; as outras venceram | regra de projeto anotada no código |
| Codecs (MP3, AAC-LC, FLAC, Vorbis, ALAC) | ✅ patentes vencidas ou livres | nada |

## 1. Direito autoral

**Código do app.** Escrito para o projeto, então não copia código de terceiros. Direito autoral protege o código (o texto), não a ideia: ter um AutoMix, uma Festa ou um Connect parecidos com os de outros apps não viola direito autoral.

**Bibliotecas.** O app usa código de terceiros, e todas as licenças permitem o uso num projeto MIT:

- **Motor em Rust:** 432 pacotes. Quase todos MIT/Apache/BSD/ISC/Zlib, mais o `symphonia` (decodificador, MPL-2.0) e o `webpki-roots` (CDLA-Permissive-2.0).
- **Dart/Flutter:** 150 pacotes. BSD/MIT/Apache, mais `dbus` e `nm` (MPL-2.0, só no Linux).
- **Android:** AndroidX (Apache-2.0) e `play-services-nearby` do Google (proprietário, com uso gratuito permitido nos apps).
- **MPL-2.0:** é copyleft só por arquivo. Pode ser usada num app MIT, desde que os arquivos MPL continuem MPL e com o código disponível (continuam, estão no crates.io/pub.dev sem mudanças).
- **Avisos de licença:** MIT, Apache e BSD pedem que o texto da licença acompanhe o app. Em Ajustes → Sobre → Licenças aparecem os pacotes Dart (o Flutter lista sozinho), os 431 do motor Rust (`app/assets/licenses/rust.json`, gerado por `dev/gen_licenses.py`) e os do Android (`android.json`).

**Fontes dos temas.** Nunito, Space Grotesk, JetBrains Mono, Playfair Display e Bebas Neue são SIL Open Font License: podem ir dentro do app, com o texto da licença junto (já está).

**Modelo de análise de batidas (Beat This!).** Código e pesos MIT (CPJKU/JKU Linz).

**Ícones.** Material Icons, Apache-2.0.

**Licença do próprio app: MIT** (trocada da GPL-3.0 em 14/09/2026: `LICENSE`, `app/rust/Cargo.toml`, README). O autor é um só, então a troca é livre. Com MIT, some a dúvida da GPL com o `play-services-nearby`, que é proprietário. Lembrete: MIT deixa qualquer pessoa usar o código, inclusive em produto fechado ou pago.

**Músicas.** O app não distribui música: toca o servidor ou os arquivos da própria pessoa.

**Arquivos na Festa.** O arquivo que um convidado manda vai para o celular do dono só para tocar ali, e é apagado quando o app abre de novo ou quando começa outra Festa: não vira cópia permanente.

## 2. Serviços on-line (termos de uso)

**iTunes Search API (capas).** Os termos da Apple só permitem usar o conteúdo (inclusive capas) em páginas que promovem o conteúdo, com o selo "Download on iTunes" levando à loja, e proíbem uso "de valor independente de entretenimento". Um player mostrando capas não se encaixa. **Trocar** pelo Cover Art Archive (MusicBrainz) e/ou Deezer.

**Deezer API (capas).** Permitida para uso **não comercial**, seguindo as diretrizes de marca da Deezer. Um app gratuito se encaixa; **dar crédito** ("Capas: Deezer") onde fizer sentido.

**lyrics.ovh.** Busca letras em paralelo no Genius, AZLyrics, Letras.mus.br etc., ou seja, copia de sites que não autorizam isso. **Tirar.**

**Musixmatch.**
- O plano gratuito entrega só ~30% da letra.
- Letra inteira exige plano comercial (licenciado).
- É obrigatório mostrar o aviso de copyright e rodar o rastreio que a API devolve.
- O app hoje usa só a letra inteira e não mostra o aviso. **Ou cumprir** (mostrar o copyright e chamar o rastreio, só com chave comercial), **ou tirar.**

**LRCLIB.**
- Banco de letras sincronizadas feito pela comunidade; o código é MIT.
- As letras em si continuam protegidas pelos autores e editoras, e o LRCLIB não as licencia.
- Vários players livres usam; o app não guarda nem republica as letras, só mostra para quem está ouvindo (com cache local).
- Risco baixo. Sugestão: mostrar a fonte ("Letra: LRCLIB") e manter a opção de desligar (já existe).

**Last.fm API.** Uso gratuito só não comercial (o app usa a chave da própria pessoa). Exige crédito com um botão/logo oficial e link para a página do artista/música no Last.fm, cache conforme os cabeçalhos HTTP e no máximo 100 MB guardados. **Mostrar "Dados do Last.fm" com link** onde as parecidas/bio aparecem.

**Google (Nearby, Android Auto).** O uso do Nearby segue os termos das APIs do Google. Para aparecer no Android Auto pela Play Store, o app passa pela revisão de distração ao volante.

## 3. Marcas (nomes)

**"Jam" (Spotify).** Já trocado por **Festa** / **Party**; no código continua `jam`, que não aparece.

**"Connect".** "Spotify Connect" é o nome do recurso do Spotify. "Connect" sozinho é palavra comum, e "BKmasterplayer Connect" tem outra marca na frente, então o risco é baixo. Para evitar comparação, dá para chamar de "Tocar em outro aparelho" ou "BK Link". O README diz "como no Spotify Connect": melhor tirar.

**"AutoMix".**
- A lista oficial de marcas da Apple não tem "AutoMix" (tem "Apple Music®", "Apple CarPlay®", "iMix™").
- "Automix" é termo comum em software de DJ (VirtualDJ, rekordbox, djay Pro). Risco baixo.
- Evitar frases como "igual ao AutoMix da Apple Music" no material de divulgação.

**"Modo DJ".** "DJ" é palavra comum (o Spotify tem um "DJ", mas o termo é genérico). Risco baixo.

**Nomes de terceiros no app** (Navidrome, OpenSubsonic, AudioMuse-AI, Last.fm, Musixmatch, LRCLIB, Deezer, Android Auto, CarPlay). Citar para dizer compatibilidade é permitido ("funciona com…"), sem usar logotipos como se fossem do app nem sugerir parceria. Para Android Auto e CarPlay, seguir as diretrizes de marca do Google e da Apple.

**"BKmasterplayer"** (nome atual, desde 14/09/2026; antes "BKplayer", "BKT Player" e "BK Music Player").
- Na busca de 14/09 não apareceu nenhum app chamado "BK Master Player" ou "BKMasterPlayer".
- Sem o "BK", existem "MasterPlayer - Music player" (`com.msd.masterplayer`, 2026) e "Master Music Player". O "BK" na frente diferencia, e "master" é palavra comum; na busca da loja, porém, aparecem perto.
- Os nomes anteriores batiam com apps existentes: "Bkt Player" (IPTV), "BK Music Player", "BK Music", "BK Player", "BK Media Player".
- "BK" também é sigla do Burger King (outra classe de produtos).
- Antes de divulgar, pesquisar no INPI (busca de marcas, classes 9 e 41) e na Play Store. Se quiser proteger o nome, registrar no INPI. Trocar o nome no app é rápido (título, rótulo do Android, atalho do Linux e textos).

## 4. Patentes

**No Brasil.** A Lei 9.279/1996 (art. 10, V) diz que "programas de computador em si" não são invenção. Patente de software aqui é bem limitada, e patentes de outros países não valem no Brasil.

**Nos EUA.** Existe patente de software, e ela vale mesmo contra quem escreveu o código do zero (código próprio não protege contra patente).

**Patentes encontradas e situação** (busca no Google Patents, 14/09/2026):

| Patente | Dona | Situação | O que reivindica | BKmasterplayer |
|---|---|---|---|---|
| US 8.280.539 B2, "automatically segueing between audio tracks" | Spotify (ex-Echo Nest) | ativa até 11/03/2031, só EUA | ver abaixo | não pratica a reivindicação |
| US 8.680.388 B2 (US 2010/0011941), "automatic recognition and matching of tempo and phase… interactive music player" | pessoa física (prioridade 2001) | **vencida em 2022** | sincronizar tempo e fase entre faixas | livre |
| EP 2.845.188 B1, "evaluation of downbeats" | Nokia | **caducada** em todos os países | downbeat por mudança de acorde + dois tipos de acento | livre (e o app usa rede neural, outro método) |
| US 7.842.874 B2, "creating music by concatenative synthesis" | MIT | ativa até 01/2029 | compor música nova juntando pedaços de outras | não se aplica (o app não compõe) |

**A patente da Spotify, reivindicação por reivindicação.** A reivindicação 1 (a 15 é a mesma, em mídia) exige **todos** estes passos:
1. reamostrar descritores de áudio da faixa 1 no ritmo dela;
2. reamostrar descritores de áudio da faixa 2 no ritmo dela;
3. **comparar, por janela deslizante, os descritores das duas faixas para achar a janela de transição preferida**;
4. fazer a transição nessa janela.

O AutoMix do BKmasterplayer não faz o passo 3: o ponto de saída de A vem da estrutura de A (começo da outro, ou N compassos antes do fim musical) e o de entrada de B é o primeiro compasso com som de B, cada um calculado sozinho. Entre as duas faixas só se comparam BPM (velocidade) e tom (roda Camelot), nunca trechos. Sem o passo 3, a reivindicação não é praticada. Essa regra está escrita no código (`app/rust/src/engine/automix.rs`) para ninguém mudar o planejador nessa direção até 2031. O Modo DJ escolhe **qual** música vem depois (parecença, BPM, tom), não **onde** emendar, o que também fica fora da reivindicação.

**Apple AutoMix.** A Apple lançou o AutoMix em 2025 (iOS/macOS 26). Pedidos de patente ainda não concedidos não valem; vale acompanhar se algum for concedido nos EUA.

**Codecs.**
- MP3: patentes vencidas desde 2017.
- AAC-LC: patentes americanas vencidas; o jurídico da Red Hat confirmou em 2017 e o Fedora passou a distribuir. O `symphonia` só decodifica AAC-LC, não HE-AAC.
- FLAC, Vorbis, Opus e ALAC (liberado pela Apple em Apache-2.0): livres.

**Outros.**
- Time-stretch (Signalsmith, MIT) e detecção de batidas (Beat This!, pesquisa acadêmica, MIT): algoritmos publicados.
- ReplayGain e EBU R128: padrões abertos.

## 5. Para publicar

Já feito em 14/09/2026:
- licença MIT;
- nome BKmasterplayer;
- fontes on-line nos termos: Cover Art Archive + Deezer para capas, LRCLIB + Musixmatch para letras, sem iTunes e sem lyrics.ovh;
- créditos (fonte da letra, aviso da Musixmatch, "Dados do Last.fm");
- avisos de licença de tudo no app;
- arquivos da Festa temporários;
- regra de projeto contra a patente da Spotify;
- README e plano sem comparações com marcas de terceiros.

Falta, fora do código:
1. Pesquisar o nome "BKmasterplayer" no INPI (classes 9 e 41) e decidir se registra.
2. Para a Play Store: política de privacidade (Bluetooth, localização/Nearby, rede local, serviços on-line) e o formulário de segurança de dados.
3. Se um dia for vendido ou tiver versão paga: Deezer e Last.fm pedem acordo comercial; e vale uma análise de patentes por advogado nos EUA.

## Fontes

- iTunes Search API, termos: https://performance-partners.apple.com/search-api
- Deezer API, termos de uso: https://developers.deezer.com/termsofuse
- Last.fm API, termos: https://www.last.fm/api/tos
- Musixmatch (planos e limites): https://freeapihub.com/apis/musixmatch · https://publicapis.io/musixmatch-api
- lyrics.ovh (fontes das letras): https://github.com/NTag/lyrics.ovh · https://metacpan.org/pod/LyricFinder::ApiLyricsOvh
- LRCLIB: https://github.com/tranxuanthang/lrclib
- Lista de marcas da Apple: https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html
- Automix em software de DJ: https://help.algoriddim.com/user-manual/djay-pro-windows/mixing-basics/using-automix · https://dj.studio/blog/best-ai-dj-software-live-sets
- Marcas da Spotify nos EUA: https://trademarks.justia.com/owners/spotify-ab-2086897
- Patente US 8.280.539 B2: https://patents.google.com/patent/US8280539B2/en
- AutoMix da Apple: https://musictech.com/news/gear/apple-music-automix-ai/
- AAC-LC e patentes (Fedora): https://fedoraproject.org/wiki/Licensing/FDK-AAC · https://en.wikipedia.org/wiki/Fraunhofer_FDK_AAC
- Apps com nome parecido: https://apkcombo.com/masterplayer-music-player/com.msd.masterplayer/ · https://m.apkpure.com/master-music-player-%E2%80%93-mp3-songs-audio-player/com.master.musicplayer · https://apkcombo.com/bk-music-player/com.bkmobile.bkmusicplayer/ · https://play.google.com/store/apps/details?id=com.bkmusic.app · https://play.google.com/store/apps/details?id=com.bkt.player
- Patentes vencidas/caducadas: https://patents.google.com/patent/US20100011941A1/en · https://patents.google.com/patent/EP2845188B1/en · https://patents.google.com/patent/US7842874
- Lei 9.279/1996 (propriedade industrial), art. 10: https://www.planalto.gov.br/ccivil_03/leis/l9279.htm
