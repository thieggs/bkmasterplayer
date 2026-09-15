# Segurança e bugs: auditoria de 15/09/2026

Checkup completo do BKmasterplayer: o app (Flutter e motor em Rust), o BK
Analyzer (coordenador e trabalhador) e o Android. Tudo o que foi achado está
corrigido e coberto por teste; o que fica como risco aceito está no fim.

Para rodar de novo: `./dev/auditoria.sh` (tudo, uns 10 min) ou
`./dev/auditoria.sh --rapido`.

## Como foi feito

Os métodos seguem o que se usa em auditoria profissional de app móvel e de
Rust: OWASP MASVS/MASTG para o app, a cadeia RustSec para as dependências e
fuzzing para o que lê arquivo de fora.

| Método | Ferramenta | O que procura |
|---|---|---|
| Dependências com vulnerabilidade conhecida | cargo-audit (RustSec), osv-scanner (Google, Dart e Rust) | CVEs e avisos nas bibliotecas |
| Licenças | cargo-deny, política em `app/rust/deny.toml` | licença incompatível com o MIT |
| Segredos | gitleaks, no histórico inteiro do git | senha, chave, token commitados |
| Análise estática | clippy com regras de segurança (pânico, índice, conta, `unsafe`), `flutter analyze`, Semgrep (Rust, Kotlin, segredos) | padrões perigosos no código |
| Revisão manual | modelo de ameaças por superfície exposta à rede | falhas de lógica que ferramenta não vê |
| Teste de invasão | coordenador de teste (porta 4549) com o Navidrome de teste | autenticação, CSRF, path traversal, força bruta, corpo gigante |
| XSS no painel | Chrome sem janela (protocolo DevTools) e música com título malicioso | script injetado pelo título, artista, álbum ou nome de trabalhador |
| Fuzzing | `examples/fuzz_decode.rs`, no PC e no notebook | pânico ou travamento com arquivo de áudio corrompido |
| Fuzzing de propriedade | teste com milhares de análises aleatórias | pânico ou `NaN` no planejador do AutoMix |
| Acessibilidade | diretrizes do Flutter (`meetsGuideline`) | botão sem nome, área de toque < 48 dp, contraste |

## Superfícies de ataque

- **Rede local, sem login:** anúncios do Connect por UDP (47801), servidor do
  Connect/Festa (TCP 47800), Festa por Bluetooth (Nearby).
- **Coordenador do BK Analyzer** (porta 4540, rede de casa e Tailscale):
  painel com login do Navidrome, API dos players, API dos trabalhadores.
- **Dados que vêm de fora:** arquivos de áudio (servidor, aparelho, convidado
  da Festa), análises do servidor, temas importados.
- **Android:** componentes exportados (tela, serviço de mídia, botão de mídia,
  capas do Android Auto), backup.

## Achados e correções

| Gravidade | Onde | O problema | Correção |
|---|---|---|---|
| **Crítica** | Festa | Um convidado aceito pedia a "capa" com um caminho (`/home/.../.ssh/id_rsa`) e recebia **qualquer arquivo de até 40 KB** do aparelho do dono: chave SSH, o `config.json` do BK Analyzer (token do Navidrome), preferências | Só sai capa de música que o dono mostrou (fila ou buscas), e só se os bytes forem de imagem. Música adicionada por convidado perde capa que aponte para arquivo |
| **Alta** | Connect | Para ver o que outro aparelho tocava, o app mandava **o token do Navidrome (u/t/s)** a qualquer aparelho que se anunciasse na rede, por HTTP. Um aparelho falso numa Wi-Fi pública colhia um login que vale para sempre | Desafio e resposta (HMAC-SHA256) com uma chave derivada da senha no login (PBKDF2, 100 mil rodadas), com prova dos dois lados. Pedido de status com hora e desafio novos (não dá para repetir). Conta antiga ativa com a senha uma vez, conferida pelo token guardado |
| Média | Festa | "Aceitar sempre" confiava no id que o convidado declara, o mesmo que o Connect anuncia na rede | Quem é aceito sempre recebe um passe secreto; o id sozinho não basta |
| Média | Festa | Upload sem oferta aceita, sem cota: um convidado enchia o disco | Upload só do arquivo oferecido e aceito, até o tamanho anunciado; 200 MB por música, 2 GB por Festa; arquivo sem oferta é apagado |
| Média | Coordenador | O login de player (u/t/s) não tinha limite de erro: dava para chutar senhas do Navidrome através dele | 20 erros por endereço em 5 min e ele para de perguntar ao Navidrome |
| Média | Coordenador | A gravação do timer e a da saída usavam o mesmo arquivo temporário: juntas, podiam corromper o `songs.json` (e a biblioteca voltaria a ser analisada do zero) | Uma gravação por vez |
| Média | Motor | A análise que vem do servidor ou do cache era usada sem conferência: valor absurdo (compasso de 0 tempos, `NaN`) podia derrubar o planejador | `TrackAnalysis::is_sane()` na entrada (servidor, cache, trabalhador); aceita as 5.448 análises reais da biblioteca e recusa as adulteradas |
| Média | Motor | Pânico ao decodificar calava o deck para sempre; na análise, parava as análises da sessão inteira | Pânico vira erro daquela música (o player pula; a análise segue); planejador protegido |
| Média | Dependências | `rustls` 0.23.44 com a RUSTSEC-2026-0285 (publicada em 14/09); `tokio`, `anyhow` com avisos de "unsound"; `futures-util` retirado | Atualizados |
| Média | Qualidade do streaming | O menu oferecia Opus, que o motor não decodifica: escolher Opus quebrava a reprodução | Só MP3; quem tinha Opus salvo foi migrado para MP3 no mesmo bitrate |
| Baixa | Coordenador | Uma thread por pedido, sem teto | 256 pedidos ao mesmo tempo; acima disso, 503 |
| Baixa | Android | O backup do Google levava as credenciais cifradas; restauradas noutro aparelho (sem a chave do Keystore), davam erro | Ficam fora do backup |
| Baixa | Tema importado | Nome de imagem aceitava `..` e arquivo oculto | Só nome simples, sem ponto no começo, até 80 caracteres |
| Baixa | Motor | `Instant::now() - 60 s` entra em pânico no Windows se o computador ligou há menos de um minuto | `checked_sub` |
| Baixa | Acessibilidade | Botões sem nome para o leitor de tela (favoritar, tocar/pausar e próxima no mini player, fechar); área de toque menor que 48 dp (tocar/pausar da barra, − e + dos downloads) | Nomes e áreas de toque corrigidos |
| Baixa | Layout | A barra do player do computador tinha altura fixa: no tablet (densidade padrão) os controles cortavam 12 px | Cresce com o conteúdo, no mínimo 84 dp |

Também: `clippy` zerado, blocos `unsafe` com a justificativa escrita, pasta
temporária do trabalhador fora do `/tmp`, e dois testes de render que
acusavam cortes falsos no build de debug passaram a um ritmo de 8× o tempo
real.

## O que foi verificado e está certo

- **Nenhum segredo no git** (todo o histórico; o único alerta é falso positivo, em `.gitleaksignore`). A chave de assinatura do Android está fora do git, com permissão 600.
- **Nenhuma vulnerabilidade** nas dependências Dart; licenças todas permissivas (a MPL-2.0 do symphonia vale só para os arquivos dele).
- **Credenciais:** o app nunca guarda a senha, só o token md5(senha + salt), no chaveiro do sistema (Keystore no Android, libsecret no Linux). TLS sempre conferido (nenhum desvio de certificado).
- **Coordenador:**
  - Senha nunca trafega nem é gravada; o token do Navidrome fica em `config.json` com permissão 600, numa pasta 700.
  - Sessões com 192 bits de `/dev/urandom`; cookie `HttpOnly` e `SameSite=Strict`; `POST` só com JSON, então formulário de outro site não passa.
  - Token dos trabalhadores comparado em tempo constante.
  - O `id` da música vira nome de arquivo higienizado: path traversal testado, dá 404.
  - Corpo limitado (1 MB, e 32 MB para o resultado da análise).
  - Na invasão de teste, deu 401 sem login ou com cookie inventado, 415 para formulário de outro site e 429 na 9ª senha errada.
- **Painel sem XSS:** título, artista, álbum e nome de trabalhador com `<script>`, `<img onerror>` e `<svg onload>` aparecem como texto; zero elementos injetados no DOM.
- **Decodificador robusto:** ~623 mil arquivos corrompidos (mp3, flac, ogg, opus, m4a) sem pânico nem travamento; o planejador passou em milhares de análises aleatórias sem pânico nem `NaN`.
- **Android:** o provedor de capas exportado só aceita chave hexadecimal e abre só para leitura (sem path traversal); o Nearby grava arquivo com nome numérico; nada com `debuggable`.

## Checkup final (depois das correções e das funções novas)

`./dev/auditoria.sh` com fuzzing no PC e no notebook, todo verde:

- cargo-audit e osv-scanner: nenhuma vulnerabilidade (3 avisos de manutenção em dependências indiretas);
- cargo-deny: licenças dentro da política; gitleaks: nenhum segredo;
- clippy: zero avisos; `flutter analyze`: nenhum problema; Semgrep: só os 7 achados já revisados;
- 40 testes Rust e 97 Flutter passando (eram 57 no Flutter antes da auditoria);
- fuzzing: 439 mil arquivos de áudio corrompidos em 3 min, sem pânico nem travamento;
- as 5.448 análises reais da biblioteca aceitas pela validação;
- Android: sem `debuggable`, backup sem as credenciais.

## Riscos que ficam (aceitos)

- **Rede local sem criptografia.** Connect e Festa falam HTTP e WebSocket
  puros. Com o desafio e resposta, quem escuta a rede não leva a senha nem o
  token, mas numa rede hostil alguém no meio do caminho ainda pode ver a fila e
  mandar comandos de reprodução durante uma sessão aberta. O mesmo vale para o
  Navidrome acessado por `http://` na rede de casa (limitação do próprio
  protocolo Subsonic, que leva o token na URL). Fora de casa, use a Tailscale
  (WireGuard) ou HTTPS.
- **Servidor de análise recebe o token do player.** O app manda o u/t/s para o
  coordenador conferir no Navidrome: configure só o seu próprio coordenador.
- **Passe da Festa em texto** na rede local e no Bluetooth: quem capturar a
  entrada de um convidado pode se passar por ele naquele dono (o estrago é pôr
  música na fila; os arquivos do aparelho não saem mais).
- **Força bruta offline:** quem capturar uma prova do Connect pode tentar
  adivinhar a senha fora do ar (o PBKDF2 deixa cada tentativa ~0,5 s). Senha
  forte resolve; é o mesmo risco do token md5 do Subsonic.
- **Avisos de manutenção** em dependências indiretas (`adler`, `derivative`,
  `instant`, via flutter_rust_bridge e souvlaki): não são vulnerabilidades;
  saem quando essas bibliotecas atualizarem.
- **Painel do coordenador sem checagem de `Host`** (DNS rebinding): o cookie é
  preso ao endereço e `SameSite=Strict`, então um site de fora não usa a sua
  sessão; só a primeira configuração (antes de qualquer login) ficaria exposta.

## Fontes

- [OWASP MASVS](https://mas.owasp.org/MASVS/) e [MASTG: MobSF](https://mas.owasp.org/MASTG/tools/generic/MASTG-TOOL-0035/)
- [Checklist de segurança Flutter (Ostorlab)](https://docs.ostorlab.co/security/flutter_app_security_checklist.html)
- [Checklist de APK Android (HackTricks)](https://hacktricks.wiki/en/mobile-pentesting/android-checklist.html)
- [Rust: auditoria de dependências (Rust Project Primer)](https://rustprojectprimer.com/checks/audit.html) e [cargo-audit](https://crates.io/crates/cargo-audit)
- [Boas práticas de segurança em Rust 2026 (Corgea)](https://corgea.com/learn/rust-security-best-practices)
- [OSV-Scanner](https://github.com/google/osv-scanner) e [OSV-Scanner com Dart/Flutter](https://medium.com/@yshean/scan-your-dart-and-flutter-dependencies-for-vulnerabilities-with-osv-scanner-7f58b08c46f1)
- [Semgrep: Rust GA](https://semgrep.dev/products/product-updates/rust-ga-support-and-swift-beta-support/)
- [flutter_secure_storage: backup do Android](https://github.com/juliansteenbakker/flutter_secure_storage#disabling-auto-backup)
