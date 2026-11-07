
---

## Para usar, sem compilar

| sistema | arquivo | como |
|---|---|---|
| **Windows** | `.exe` | abre e segue o instalador |
| **Linux (Debian/Ubuntu)** | `.deb` | `sudo apt install ./bkmasterplayer_*.deb` |
| **Linux (qualquer)** | `.AppImage` | `chmod +x` e abre — não instala nada |
| **Android** | `.apk` | libere "instalar de fontes desconhecidas" |
| **iPhone** | `.ipa` | sem assinatura — veja [como instalar](https://github.com/thieggs/bkmasterplayer/blob/main/docs/IPHONE.md) |

O `.ipa` não é assinado: o **iloader** (no Linux, Windows ou Mac, pelo cabo) ou
o **SideStore** (renova sozinho no celular) assinam com o seu Apple ID na hora
de instalar — passo a passo, Modo de Desenvolvedor e erros comuns em
[docs/IPHONE.md](https://github.com/thieggs/bkmasterplayer/blob/main/docs/IPHONE.md).
O `sidestore.json` é a fonte do SideStore: adicionada nele, as versões novas
chegam e instalam no próprio iPhone, sem computador.
No iPhone, a lista automática do **Connect** fica vazia (broadcast, que a Apple só
libera para conta paga) — adicione o aparelho pelo endereço. A **Festa** acha os outros
por Bonjour, que o iPhone libera.

Quem prefere compilar: [COMPILAR.md](https://github.com/thieggs/bkmasterplayer/blob/main/docs/COMPILAR.md).
