
---

## Para usar, sem compilar

| sistema | arquivo | como |
|---|---|---|
| **Windows** | `.exe` | abre e segue o instalador |
| **Linux (Debian/Ubuntu)** | `.deb` | `sudo apt install ./bkmasterplayer_*.deb` |
| **Linux (qualquer)** | `.AppImage` | `chmod +x` e abre — não instala nada |
| **Android** | `.apk` | libere "instalar de fontes desconhecidas" |
| **iPhone** | `.ipa` | sem assinatura — veja [como instalar](docs/IPHONE.md) |

O `.ipa` não é assinado: o **Sideloadly** (cabo, mais rápido de começar) ou o
**SideStore** (renova sozinho no celular) assinam com o seu Apple ID na hora de
instalar — o passo a passo dos dois está em [docs/IPHONE.md](docs/IPHONE.md).
**Connect e Festa não funcionam no iPhone**: dependem de multicast, e a Apple só
libera isso para conta paga.

Quem prefere compilar: [COMPILAR.md](docs/COMPILAR.md).
