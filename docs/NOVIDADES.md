# Novidades

O que mudou em cada versão. O release no GitHub traz esta seção no topo,
tirada daqui pelo `.github/workflows/release.yml`.

## v1.4.0

### Todos os formatos de música

- **Opus agora toca**, em `.opus`, `.webm` (o áudio do YouTube), `.mka` e
  `.mp4`. Ele é decodificado no próprio app, com a biblioteca de referência
  (libopus). Antes, música em Opus dava "formato não suportado".
- **Formatos de audiófilo, sem perda nenhuma:**
  - DSD (`.dsf` e `.dff`, o formato do SACD), convertido para PCM de 88,2 kHz;
  - Monkey's Audio (`.ape`);
  - WavPack (`.wv`).
  E MP2/MP1.
- **Formatos que o app não lê** (WMA, Musepack, TTA, AC-3, DTS, HE-AAC, AAC
  5.1…) o Navidrome converte na hora. Agora isso também acontece sozinho
  quando o problema só aparece ao abrir o arquivo, como um `.m4a` com HE-AAC:
  o app troca para a conversão em vez de dar erro.
- **No computador**, músicas do aparelho nesses formatos tocam pelo ffmpeg do
  sistema, se houver um. O pacote `.deb` já recomenda instalar.
- **Músicas do aparelho:** a biblioteca local passa a achar esses formatos e
  a ler as tags e a duração deles.

### Seek no ponto exato

- **Pular para um ponto da música cai exatamente lá**, em todos os formatos.
  Antes, o Vorbis caía 23 ms adiantado e o Opus em WebM 5 ms, e o MP3 e o AAC
  davam um estalinho logo depois do pulo. As transições do AutoMix que
  começam no meio da música também ficam alinhadas na batida.

### BK Analyzer

- **Analisa os formatos novos.** Se o original não abrir, ele analisa a mesma
  conversão que o app toca nesse caso. Para valer, atualize o coordenador e os
  trabalhadores.

## v1.3.0

### Atualização automática

- **O app procura versão nova sozinho.** Ao abrir, pergunta ao GitHub qual é o
  último release; se for mais novo, avisa com as novidades e atualiza: no
  Android abre o instalador do sistema, no AppImage troca o arquivo, no `.deb`
  pede a senha, instalado pelo `install_linux.sh` troca a pasta e no Windows
  roda o instalador quieto — e o app volta a abrir já na versão nova. No
  iPhone só avisa, com o link.
- **Pode baixar em segundo plano** (nunca nos dados móveis) e só perguntar na
  hora de instalar. O arquivo é conferido com o SHA-256 que o GitHub publica.
- Opções em Ajustes → Sobre → Atualizações, com o botão "Procurar agora".

### Festa

- **Festa por Bluetooth consertada e sem depender do Google.** Em celular novo
  a Festa não achava ninguém por Bluetooth (faltava a permissão de localização
  que o Google exige). E agora tem a chave "Bluetooth sem Google Play
  Services": funciona em LineageOS, Huawei e afins, achando sozinho ou
  escolhendo um celular pareado. Música mandada por Bluetooth tem progresso de
  verdade e não trava mais.
- Depois de uma recusa ou de a conexão cair, o convidado volta a procurar
  sozinho, e o mesmo dono não aparece duas vezes na lista.

### Rádio

- **A rádio não se perde mais.** Ela guarda a música de onde começou e a
  vizinhança dela, em vez de ir pulando de parecida em parecida até virar
  outro estilo. Música recém-adicionada que o AudioMuse ainda não conhece
  começa a rádio pela música anterior, em vez de cair em sugestões genéricas.
- **Artista repetido:** escolha entre variar (nada do mesmo artista nas
  últimas 5), só não repetir em seguida, ou à vontade. Na folha da rádio e
  nos ajustes de recomendação.
- **"Mesmo estilo musical" ficou mais certeiro:** usa o modelo de áudio e
  texto do AudioMuse (CLAP), que entende estilos que os rótulos de gênero não
  cobrem (o latino e o brasileiro, por exemplo).
- Com a recomendação no aparelho ligada, os vetores não carregavam ao abrir o
  app, e todos os métodos davam as mesmas músicas. Escolher um método contado
  no aparelho agora já liga a análise guardada.

### AutoMix

- **O eco não corta mais o final da música.** A troca com eco saía até ~8 s
  antes do fim e jogava fora compassos que ainda tinham música. Agora a música
  toca até o último compasso com som, e a cauda do eco segue depois do fim do
  arquivo.

### Mais leve

- A análise do AutoMix usa metade da memória e devolve ao sistema o que usou.
- Música pausada não acorda mais o processador o tempo todo (no Android isso
  ajudava o sistema a fechar o app em segundo plano).
- A posição da fila é gravada à parte: regravar a fila inteira a cada 15 s
  dava um engasgo de tempos em tempos.
- Mini player, disco de vinil e fundo desfocado redesenham só o que mudou.

### Corrigido

- **O app travava (ANR) quando a capa demorava a baixar** com a notificação de
  música aberta: a tela esperava a capa. Agora a capa carrega por fora, e
  sem rede a música só fica sem capa.
- Quando a consulta do tipo de rede falhava, sobrava um erro solto no registro
  de diagnóstico.

### Carro

- **A capa aparecia cinza no carro.** Ela ia como `file://` apontando para o
  cache privado do app: a notificação do celular lê, porque é o próprio app, o
  Android Auto não, porque é outro app. E com ela sumia a cor — o carro tira o
  destaque da tela da cor dominante da capa. Agora vai pelo provedor
  `content://`, que os dois leem.
- **A tela do carro era uma lista corrida.** Agora o Início vem em blocos com
  título, o que não tem capa não reserva mais um quadrado grande e vazio, e
  entraram artistas e gêneros.
- **As abas do carro saem das que você escolheu no app**, na mesma ordem,
  tirando o que não serve dirigindo.
- **O app passou a funcionar em carro com Android de fábrica** (Automotive OS —
  Volvo, Polestar, Renault, GM novos). Ele declarava só o Android Auto, e o
  carro nativo procura outro aviso, no serviço: sem ele o app nem aparecia na
  lista de fontes de música.

## v1.2.0

Tudo nesta versão é do **disco de vinil** (modo de capa Vinil, em
Personalizar → Tocando agora).

### Mudou

- **O disco tem rolamento.** Soltar o dedo não para mais o disco: **larga** ele.
  Ele segue no embalo e vai perdendo velocidade até voltar ao normal, então o
  ponto de chegada depende do giro e não de onde você soltou. Vale nos dois
  sentidos, e soltar com ele quase parado faz ganhar rotação, como um prato.
  Pegar o disco no meio do deslize continua de onde ele estava.
  - Novo ajuste **Rolamento do disco** (0 = para na hora, como antes) e **forma
    da desaceleração**: rolamento (constante), vinil (freia forte e vai
    encostando) ou freio no fim.
- **A memória do disco agora tem o tamanho da faixa**, e não 12 s fixos: do fim
  da música dá para voltar girando até o começo. É guardada em 16 bits (metade
  da RAM, sem diferença audível) com teto de 64 MB — quase 6 minutos a 48 kHz.
  - Novo ajuste **Quanto dá para voltar girando**: a música inteira, 3 min,
    1 min ou 12 s, para quem quer poupar memória.
- **A memória passa a encher desde que a tela do vinil abre**, e não só durante
  o gesto.

### Corrigido

- **Voltar o disco não tocava nada.** A memória chegava junto com a mão — ou
  seja, nascia vazia justo no instante do gesto. Só dava som o que a própria mão
  tivesse adiantado antes de virar. Para frente funcionava porque ali quem serve
  é o decodificador, não a memória.
- **Voltar só alcançava uns 2 segundos.** Soltar o disco dá um seek, o seek
  troca o deck, e a memória era indexada pelo contador do deck: cada gesto
  começava do zero. Agora o índice é o tempo da música e atravessa os seeks.
- **O deslize tinha duração fixa**: jogar o disco com força ou de leve levava os
  mesmos 0,6 s, o que não é rolamento nenhum. Agora o ajuste fixa a
  desaceleração e o tempo sai da força do arremesso.

### Limite que continua valendo

O que dá para voltar é o que **já tocou** desde que a tela do vinil abriu. Pular
para o fim de uma música que não rodou não deixa passado atrás dela.

## v1.1.0

### Girar o disco de vinil

No modo de capa **Vinil**, a capa virou o controle: gire com o dedo (ou o
mouse) para procurar o ponto da música, para frente e para trás.

- **O som acompanha o giro.** A agulha lê o áudio num índice fracionário, com
  interpolação: acelerar sobe o tom, desacelerar desce e girar ao contrário
  toca de trás para frente. É o som de um disco de verdade — e é por isso que o
  time-stretch do AutoMix não servia aqui, já que ele *segura* o tom.
- **12 s do que já tocou ficam guardados**, e o disco vai guardando mesmo sem
  ninguém na mão: pegar e voltar na hora já toca.
- **Disco parado na mão não faz som**, e ao soltar a música volta de onde a
  agulha ficou.
- **Calar é sempre temporário:** chegando mais áudio decodificado, saindo da
  parede da memória ou voltando para baixo do limite, a agulha volta a tocar
  sozinha.
- A **fila de progresso acompanha** o disco, e o tempo de destino aparece sobre
  ele com o quanto andou.

Tudo isso em **Personalizar → Tocando agora**, e tudo desligável:

| ajuste | o que faz |
|---|---|
| **Girar o disco para procurar** | a mecânica inteira; desligado, fica só a capa redonda |
| **Som do disco girando** | o som acompanha o giro; desligado, a música só emudece enquanto se procura |
| **Música por volta do disco** | de 0,1 s a 4 s. O padrão, 1,8 s, é a volta de um LP de 33⅓ RPM: girando no ritmo de um disco de verdade, o tom sai certo |
| **Até onde a agulha aguenta** | de 2× a 16× a velocidade normal; acima disso ela levanta |
| **Sem limite** | a agulha nunca levanta: o giro inteiro sai no som |

### Festa

- **Controlar de dentro do player**, sem ir na aba: uma faixa aparece enquanto
  há Festa e some quando você sai. O dono vê quantos estão na sala e encerra
  dali; o convidado vê de quem é a Festa e sai dali. A fila do player mostra a
  fila da Festa quando você é convidado.
- **Entrar pelo QR code lido pela câmera do próprio celular** — nada de
  scanner dentro do app.
- **Entrar digitando o endereço**, para quando a descoberta automática não
  alcança.
- **Achar os outros por Bonjour**, além do broadcast: é o que faz o iPhone
  aparecer para o PC e vice-versa.

### Consertos

- Tema escrito à mão com texto onde devia ter número (`"radius": "999"`)
  **derrubava o app** em vez de cair no padrão.
- No iPhone, o motor de áudio não ligava: os frameworks que ele precisa
  (`AudioToolbox`, `AVFoundation`, `CoreAudio`) passaram a ser declarados no
  podspec, porque na hora de juntar tudo quem manda é o Xcode.

## v1.0.0

Primeira versão publicada, com os programas prontos para Windows, Linux
(`.deb` e `.AppImage`), Android e iPhone.
