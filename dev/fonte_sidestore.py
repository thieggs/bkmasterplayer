#!/usr/bin/env python3
"""Gera a fonte do SideStore (sidestore.json) a partir do .ipa de um release.

Com a fonte adicionada, o SideStore avisa da versão nova e instala no próprio
iPhone, sem computador. O release.yml roda isto e sobe o arquivo junto com os
programas; o endereço fixo é o do último release:

    https://github.com/thieggs/bkmasterplayer/releases/latest/download/sidestore.json

O SideStore confere o .ipa baixado contra a fonte e recusa se não bater: ID,
versão, build, tamanho, SHA-256 e permissões (as chaves *UsageDescription do
Info.plist e os entitlements). Por isso tudo sai do próprio .ipa, nada à mão.

Uso:  ./dev/fonte_sidestore.py <arquivo.ipa> <tag> > sidestore.json
      (a tag, ex. v1.6.0, dá o link de download e as novidades)
"""
import datetime
import hashlib
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path

REPO = 'thieggs/bkmasterplayer'
RAIZ = Path(__file__).resolve().parent.parent
ICONE = f'https://raw.githubusercontent.com/{REPO}/main/app/assets/icon/icon_256.png'
COR = '7C4DFF'  # a cor padrão do app (ui_prefs.dart)

# Magia do bloco de entitlements dentro da assinatura de um Mach-O.
_ENTITLEMENTS = b'\xfa\xde\x71\x71'
# Estes dois todo app tem; o SideStore não pede que a fonte declare.
_IGNORADOS = {'application-identifier', 'com.apple.developer.team-identifier'}


def novidades(tag: str) -> str:
    """A seção da tag em docs/NOVIDADES.md, em texto puro (o SideStore não
    entende Markdown)."""
    linhas, dentro = [], False
    for linha in (RAIZ / 'docs/NOVIDADES.md').read_text(encoding='utf-8').splitlines():
        if linha == f'## {tag}':
            dentro = True
        elif dentro and linha.startswith('## '):
            break
        elif dentro:
            linhas.append(linha)
    # Desfaz a quebra em 80 colunas: o celular quebra sozinho, e a linha
    # cortada no meio da frase fica feia lá.
    juntas = []
    for linha in linhas:
        if juntas and juntas[-1].strip() and linha.strip() and not re.match(r'\s*([-*]|\d+\.|#)\s', linha):
            juntas[-1] += ' ' + linha.strip()
        else:
            juntas.append(linha.rstrip())
    texto = '\n'.join(juntas).strip()
    texto = re.sub(r'^#+\s*', '', texto, flags=re.M)
    texto = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', texto)
    return texto.replace('**', '').replace('`', '')


def entitlements(binario: bytes) -> set[str]:
    """Os entitlements embutidos na assinatura (nenhum no .ipa sem assinatura
    que o release gera, mas se um dia vier assinado a fonte acompanha)."""
    achados, i = set(), binario.find(_ENTITLEMENTS)
    while i >= 0:
        tam = int.from_bytes(binario[i + 4:i + 8], 'big')
        try:
            achados |= set(plistlib.loads(binario[i + 8:i + tam]))
        except Exception:
            pass  # a sequência apareceu por acaso, fora de uma assinatura
        i = binario.find(_ENTITLEMENTS, i + 4)
    return achados - _IGNORADOS


def fonte(ipa: Path, tag: str) -> dict:
    with zipfile.ZipFile(ipa) as z:
        nomes = z.namelist()
        app = next(n for n in nomes if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n))
        pasta = app[:-len('Info.plist')]
        info = plistlib.loads(z.read(app))
        # O app e as extensões dele: é o que o SideStore confere.
        extensoes = [n for n in nomes if re.fullmatch(re.escape(pasta) + r'(PlugIns|Extensions)/[^/]+\.appex/Info\.plist', n)]
        privacidade, ents = {}, set()
        for plist in [app, *extensoes]:
            p = info if plist == app else plistlib.loads(z.read(plist))
            privacidade |= {k: v for k, v in p.items() if 'UsageDescription' in k}
            exe = plist[:-len('Info.plist')] + p['CFBundleExecutable']
            ents |= entitlements(z.read(exe))
        # A data do release é a do build: a hora em que o Info.plist entrou no zip.
        data = datetime.datetime(*z.getinfo(app).date_time, tzinfo=datetime.timezone.utc)

    conteudo = ipa.read_bytes()
    versao = info['CFBundleShortVersionString']
    nome = info.get('CFBundleDisplayName') or info['CFBundleName']
    descricao = (
        'Player para o seu servidor Navidrome/Subsonic que emenda as músicas como '
        'um DJ: acha as batidas e o tom e casa a transição sem mudar a afinação. '
        'Com AudioMuse, recomendação sem internet e aleatório que aprende.'
    )
    return {
        'version': 2,
        'name': nome,
        'subtitle': 'O player que mixa a sua biblioteca.',
        'description': descricao,
        'iconURL': ICONE,
        'website': f'https://github.com/{REPO}',
        'sourceURL': f'https://github.com/{REPO}/releases/latest/download/sidestore.json',
        'tintColor': COR,
        'apps': [{
            'name': nome,
            'bundleIdentifier': info['CFBundleIdentifier'],
            'developerName': 'thieggs',
            'subtitle': 'O player que mixa a sua biblioteca.',
            'localizedDescription': descricao,
            'iconURL': ICONE,
            'tintColor': COR,
            'category': 'entertainment',
            'versions': [{
                'version': versao,
                'buildVersion': info['CFBundleVersion'],
                'date': data.isoformat().replace('+00:00', 'Z'),
                'localizedDescription': novidades(tag) or f'Versão {versao}.',
                'downloadURL': f'https://github.com/{REPO}/releases/download/{tag}/{ipa.name}',
                'size': len(conteudo),
                'sha256': hashlib.sha256(conteudo).hexdigest(),
                'minOSVersion': info.get('MinimumOSVersion', '14.0'),
            }],
            'appPermissions': {
                'entitlements': sorted(ents),
                'privacy': privacidade,
            },
        }],
        'news': [],
    }


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    json.dump(fonte(Path(sys.argv[1]), sys.argv[2]), sys.stdout, ensure_ascii=False, indent=2)
    print()
