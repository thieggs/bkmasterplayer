# BKplayer: licenças, marcas, patentes e termos de serviço

Levantamento feito em 14/09/2026, antes de publicar o app no GitHub com licença MIT. É uma triagem técnica, **não é parecer jurídico**. Para lançamento comercial ou nos EUA, vale revisar com um advogado de propriedade intelectual.

## Resumo

| Tema | Situação | O que fazer |
|---|---|---|
| Direito autoral do código do app | ✅ código próprio | nada |
| Bibliotecas usadas (≈580) | ✅ todas compatíveis com MIT | incluir os avisos de licença (ver abaixo) |
| Fontes, ícones, modelo de IA | ✅ licenças livres | manter os textos das licenças (já estão no app) |
| Capas pelo iTunes | ❌ os termos da Apple proíbem esse uso | trocar por Cover Art Archive/Deezer |
| Letras pelo lyrics.ovh | ❌ ele copia letras de outros sites | tirar |
| Letras pelo Musixmatch | ⚠️ letra inteira só no plano pago, com aviso e rastreio obrigatórios | cumprir os termos ou tirar |
| Letras pelo LRCLIB | ⚠️ banco comunitário; as letras têm dono | manter (uso comum), avisar a fonte |
| Last.fm | ⚠️ não comercial ok, mas exige crédito com link | mostrar o crédito |
| Deezer (capas) | ✅ uso não comercial permitido | dar o crédito |
| Nome "Jam" | ✅ trocado por "Festa" | feito |
| Nomes "Connect", "AutoMix", "Modo DJ" | ⚠️ baixo risco | tirar comparações com Spotify/Apple do texto; talvez renomear "Connect" |
| Nome "BKplayer" | ⚠️ já existem apps "BK Player"/"BK Music Player" | pesquisar no INPI antes de divulgar |
| Patentes de transição automática (EUA) | ⚠️ há patente ativa da Spotify até 2031 | parece não coincidir; revisar antes de uso comercial nos EUA |
| Codecs (MP3, AAC-LC, FLAC, Vorbis, ALAC) | ✅ patentes vencidas ou livres | nada |

## 1. Direito autoral

**Código do app.** Escrito para o projeto, então não copia código de terceiros. Direito autoral protege o código (o texto), não a ideia: ter um AutoMix, uma Festa ou um Connect parecidos com os de outros apps não viola direito autoral.

**Bibliotecas.** O app usa código de terceiros, e todas as licenças permitem o uso num projeto MIT:

- **Motor em Rust:** 432 pacotes. Quase todos MIT/Apache/BSD/ISC/Zlib, mais o `symphonia` (decodificador, MPL-2.0) e o `webpki-roots` (CDLA-Permissive-2.0).
- **Dart/Flutter:** 150 pacotes. BSD/MIT/Apache, mais `dbus` e `nm` (MPL-2.0, só no Linux).
- **Android:** AndroidX (Apache-2.0) e `play-services-nearby` do Google (proprietário, com uso gratuito permitido nos apps).
- **MPL-2.0:** é copyleft só por arquivo. Pode ser usada num app MIT, desde que os arquivos MPL continuem MPL e com o código disponível (continuam, estão no crates.io/pub.dev sem mudanças).
- **Obrigação que falta:** MIT, Apache e BSD pedem que o texto da licença acompanhe o app. Os pacotes Dart já aparecem em Ajustes → Sobre → Licenças; faltam os do motor Rust (gerar com `cargo about`) e os do Android (plugin `oss-licenses` do Google).

**Fontes dos temas.** Nunito, Space Grotesk, JetBrains Mono, Playfair Display e Bebas Neue são SIL Open Font License: podem ir dentro do app, com o texto da licença junto (já está).

**Modelo de análise de batidas (Beat This!).** Código e pesos MIT (CPJKU/JKU Linz).

**Ícones.** Material Icons, Apache-2.0.

**Licença do próprio app.** O repositório hoje diz GPL-3.0; para publicar em MIT, é preciso trocar o `LICENSE`, o campo `license` do `app/rust/Cargo.toml` e o README. Como o autor é um só, a troca é livre. Com MIT, some a dúvida da GPL com o `play-services-nearby`, que é proprietário. Lembrete: MIT deixa qualquer pessoa usar o código, inclusive em produto fechado ou pago.

**Músicas.** O app não distribui música: toca o servidor ou os arquivos da própria pessoa.

**Arquivos na Festa.** Na Festa, o arquivo que um convidado manda vai para o celular do dono só para tocar ali. Convém que seja apagado do cache depois, para não virar cópia permanente.

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

**"Connect".** "Spotify Connect" é o nome do recurso do Spotify. "Connect" sozinho é palavra comum, e "BKplayer Connect" tem outra marca na frente, então o risco é baixo. Para evitar comparação, dá para chamar de "Tocar em outro aparelho" ou "BK Link". O README diz "como no Spotify Connect": melhor tirar.

**"AutoMix".**
- A lista oficial de marcas da Apple não tem "AutoMix" (tem "Apple Music®", "Apple CarPlay®", "iMix™").
- "Automix" é termo comum em software de DJ (VirtualDJ, rekordbox, djay Pro). Risco baixo.
- Evitar frases como "igual ao AutoMix da Apple Music" no material de divulgação.

**"Modo DJ".** "DJ" é palavra comum (o Spotify tem um "DJ", mas o termo é genérico). Risco baixo.

**Nomes de terceiros no app** (Navidrome, OpenSubsonic, AudioMuse-AI, Last.fm, Musixmatch, LRCLIB, Deezer, Android Auto, CarPlay). Citar para dizer compatibilidade é permitido ("funciona com…"), sem usar logotipos como se fossem do app nem sugerir parceria. Para Android Auto e CarPlay, seguir as diretrizes de marca do Google e da Apple.

**"BKplayer".**
- Já existem nas lojas "BK Player" (app de toques, BK Music Inc., 2023), "BK Music Player" e "BK Media Player".
- "BK" também é sigla do Burger King (outra classe de produtos).
- Antes de divulgar, pesquisar no INPI (busca de marcas, classes 9 e 41) e na Play Store. Se quiser proteger o nome, registrar no INPI.

## 4. Patentes

**No Brasil.** A Lei 9.279/1996 (art. 10, V) diz que "programas de computador em si" não são invenção. Patente de software aqui é bem limitada, e patentes de outros países não valem no Brasil.

**Nos EUA.** Existe patente de software, e ela vale mesmo contra quem escreveu o código do zero (código próprio não protege contra patente).

**Patente encontrada: US 8.280.539 B2**, "Method and apparatus for automatically segueing between audio tracks".
- Dona: Spotify (veio da Echo Nest). Prioridade em 2007; ativa até **11/03/2031**; só nos EUA.
- O que reivindica: comparar "vetores de timbre" das duas músicas por janelas deslizantes para achar os trechos mais parecidos, esticar o tempo para igualar o ritmo e fazer o crossfade nesse trecho.
- O AutoMix do BKplayer escolhe o ponto pela estrutura (intro/outro, frases, energia, batidas) e não por comparação de timbre por janelas. À primeira vista não coincide, e patente só é violada quando **todos** os elementos de uma reivindicação estão presentes.
- Não é conclusão jurídica: se um dia houver distribuição comercial nos EUA, pedir análise de um advogado de patentes.

**Apple AutoMix.** A Apple lançou o AutoMix em 2025 (iOS/macOS 26). Pedidos de patente ainda não concedidos não valem; vale acompanhar se algum for concedido nos EUA.

**Codecs.**
- MP3: patentes vencidas desde 2017.
- AAC-LC: patentes americanas vencidas; o jurídico da Red Hat confirmou em 2017 e o Fedora passou a distribuir. O `symphonia` só decodifica AAC-LC, não HE-AAC.
- FLAC, Vorbis, Opus e ALAC (liberado pela Apple em Apache-2.0): livres.

**Outros.**
- Time-stretch (Signalsmith, MIT) e detecção de batidas (Beat This!, pesquisa acadêmica, MIT): algoritmos publicados.
- ReplayGain e EBU R128: padrões abertos.

## 5. Para publicar

1. Trocar a licença do repositório para MIT (`LICENSE`, `Cargo.toml`, README).
2. Tirar o lyrics.ovh; trocar as capas do iTunes pelo Cover Art Archive + Deezer; Musixmatch: cumprir os termos (aviso + rastreio, chave comercial) ou tirar.
3. Créditos no app: "Dados do Last.fm" com link; fonte da letra (LRCLIB/Musixmatch); fonte da capa (Deezer/Cover Art Archive).
4. Gerar os avisos de licença do motor Rust (`cargo about`) e do Android e mostrar em Sobre → Licenças.
5. Tirar do README as comparações com "Spotify Connect" e "AutoMix da Apple Music".
6. Pesquisar o nome "BKplayer" no INPI (classes 9 e 41) e na Play Store.
7. Para a Play Store: política de privacidade (Bluetooth, localização/Nearby, rede local, serviços on-line) e o formulário de segurança de dados.

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
- Apps com nome parecido: https://apkcombo.com/bk-player/com.bk.player/ · https://apkcombo.com/bk-music-player/com.bkmobile.bkmusicplayer/
- Lei 9.279/1996 (propriedade industrial), art. 10: https://www.planalto.gov.br/ccivil_03/leis/l9279.htm
