#!/usr/bin/env python3
"""Confere o .ipa antes de publicar: o que já fez a instalação no iPhone
falhar (ou faria) em quem instala por fora (SideStore, LiveContainer,
iloader, Sideloadly).

Uso:  ./dev/confere_ipa.py <arquivo.ipa>     (sai com erro se algo falhar)

O que olha, e por quê (ver docs/IPHONE.md):
- Um app só em Payload/, com o ID de sempre: o SideStore só atualiza o app
  que tem o mesmo ID do que está instalado e da fonte (sidestore.json).
- Nenhuma extensão (PlugIns/ ou Extensions/): Apple ID gratuito tem 10 IDs
  de app por semana e cada extensão gasta um; e em 11/2026 o SideStore
  ainda não renomeia o que fica em Extensions/ e a instalação falha com
  "Mismatched bundle IDs" (SideStore#1724).
- Ciclo de vida por cena (UIApplicationSceneManifest): compilado com o SDK
  do iOS 27 em diante, app sem cena não abre.
- Tocar com a tela apagada (UIBackgroundModes audio).
- Rede: NSAllowsArbitraryLoads, sem NSAllowsLocalNetworking (que faz o iOS
  ignorar a outra e barrar o Navidrome em http:// com nome de domínio).
"""
import plistlib
import sys
import zipfile

ID = 'io.github.playermusica.playerMusica'


def confere(caminho: str) -> list[str]:
    erros = []
    with zipfile.ZipFile(caminho) as z:
        nomes = z.namelist()
        apps = sorted({n.split('/')[1] for n in nomes if n.startswith('Payload/') and n.split('/')[1].endswith('.app')})
        if len(apps) != 1:
            return [f'Payload/ devia ter um .app só, tem {apps}']
        app = f'Payload/{apps[0]}/'
        info = plistlib.loads(z.read(app + 'Info.plist'))
        extensoes = sorted({n[len(app):].split('/')[1] for n in nomes
                            if n.startswith((app + 'PlugIns/', app + 'Extensions/')) and n.count('/') > 3})
        if extensoes:
            erros.append(f'extensões no app (gastam IDs da conta grátis; Extensions/ quebra o SideStore): {extensoes}')

    if info.get('CFBundleIdentifier') != ID:
        erros.append(f'CFBundleIdentifier é {info.get("CFBundleIdentifier")!r}, devia ser {ID!r}')
    if 'UISceneConfigurations' not in info.get('UIApplicationSceneManifest', {}):
        erros.append('sem UIApplicationSceneManifest: com o SDK do iOS 27 o app não abre')
    if 'audio' not in info.get('UIBackgroundModes', []):
        erros.append('sem UIBackgroundModes audio: a música para quando a tela apaga')
    ats = info.get('NSAppTransportSecurity', {})
    if ats.get('NSAllowsArbitraryLoads') is not True:
        erros.append('sem NSAllowsArbitraryLoads: Navidrome em http:// não conecta')
    if 'NSAllowsLocalNetworking' in ats:
        erros.append('NSAllowsLocalNetworking faz o iOS ignorar NSAllowsArbitraryLoads')
    if not info.get('NSLocalNetworkUsageDescription'):
        erros.append('sem NSLocalNetworkUsageDescription: o iOS barra o servidor da rede de casa')

    versao = (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion'))
    print(f'{apps[0]}: {ID} {versao[0]} ({versao[1]}), iOS {info.get("MinimumOSVersion")}+, '
          f'SDK {info.get("DTSDKName")}, Xcode {info.get("DTXcode")}')
    return erros


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    erros = confere(sys.argv[1])
    for e in erros:
        print(f'::error::{e}')
    sys.exit(1 if erros else 0)
