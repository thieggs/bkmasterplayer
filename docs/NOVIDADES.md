# Novidades

O que mudou em cada versão. O release no GitHub traz esta seção no topo,
tirada daqui pelo `.github/workflows/release.yml`.

## v1.2.0

### Girar o disco: dá para voltar a música inteira

- **A memória do disco agora tem o tamanho da faixa**, e não 12 s fixos: do fim
  da música dá para voltar girando até o começo. Ela é guardada em 16 bits
  (metade da RAM, sem diferença audível para scratch) e tem teto de 64 MB, que
  a 48 kHz dá quase 6 minutos. Em **Personalizar → Tocando agora** dá para
  limitar (a música inteira, 3 min, 1 min ou 12 s) para quem quer poupar
  memória.
- **Soltar e pegar o disco de novo não joga a memória fora.** Soltar dá um
  seek, o seek troca o deck, e a memória ia junto — na prática só dava para
  voltar o que tinha tocado desde o último gesto. Agora ela é indexada pelo
  tempo da **música**, então atravessa os seeks; só é esquecida quando a música
  muda ou se pula para outra parte dela.
- **A memória enche mesmo sem ninguém no disco.** Antes ela só era preenchida
  durante o gesto, então pegar e voltar na hora não tocava nada: só dava som se
  você adiantasse primeiro.

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
