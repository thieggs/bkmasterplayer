#!/usr/bin/env python3
"""Gera os avisos de licença dos pacotes Rust do motor para o app
(Ajustes → Sobre → Licenças): app/assets/licenses/rust.json.

Uso: ./dev/gen_licenses.py   (rodar de novo quando mudar o Cargo.lock)

Cada entrada junta os pacotes que têm exatamente o mesmo texto de licença,
para o arquivo ficar pequeno. Os pacotes Dart já entram sozinhos pelo
Flutter; os do Android estão em app/assets/licenses/android.json.
"""
import glob
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUST = os.path.join(ROOT, 'app', 'rust')
OUT = os.path.join(ROOT, 'app', 'assets', 'licenses', 'rust.json')
REGISTRY = glob.glob(os.path.expanduser('~/.cargo/registry/src/*/'))

meta = json.loads(subprocess.run(['cargo', 'metadata', '--format-version', '1', '--locked'],
                                 cwd=RUST, check=True, capture_output=True, text=True).stdout)
nodes = {n['id']: n for n in meta['resolve']['nodes']}
pkgs = {p['id']: p for p in meta['packages']}
root = meta['resolve']['root']

# Só o que vai para o app: dependências normais e de build, de todos os alvos.
seen, stack = set(), [root]
while stack:
    i = stack.pop()
    if i in seen:
        continue
    seen.add(i)
    for dep in nodes[i]['deps']:
        if any(k.get('kind') in (None, 'build') for k in dep['dep_kinds']):
            stack.append(dep['pkg'])
seen.discard(root)


APACHE_REF = '[Apache License 2.0: texto completo na entrada "Apache License 2.0" desta lista]'
MIT_TEMPLATE = """Copyright (c) {authors}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""
apache_full = None


def is_apache(text):
    return 'Apache License' in text and 'Version 2.0' in text and 'TERMS AND CONDITIONS' in text


def license_texts(p):
    """Textos de licença do pacote; a Apache 2.0 vira referência (vai uma vez só)."""
    global apache_full
    base = os.path.dirname(p['manifest_path'])
    files = sorted(f for f in os.listdir(base)
                   if re.match(r'(?i)^(licen[cs]e|copying|notice)', f) and os.path.isfile(os.path.join(base, f)))
    if p.get('license_file') and not files:
        files = [p['license_file']]
    texts = []
    for f in files:
        with open(os.path.join(base, f), errors='replace') as fh:
            t = fh.read().strip()
        if is_apache(t):
            if apache_full is None or len(t) > len(apache_full):
                apache_full = t
            t = APACHE_REF
        texts.append(t)
    if not texts:
        # Sem arquivo no pacote: o texto padrão com os autores do Cargo.toml.
        spdx = p.get('license') or ''
        authors = ', '.join(a.split('<')[0].strip() for a in p.get('authors') or []) or f"os autores de {p['name']}"
        if 'MIT' in spdx:
            texts.append(MIT_TEMPLATE.format(authors=authors))
        if 'Apache-2.0' in spdx:
            texts.append(APACHE_REF)
        if not texts:
            texts.append(f'Licença: {spdx or "?"} (texto em https://spdx.org/licenses/)')
    return '\n\n'.join(texts)


groups = {}
missing = []
for i in sorted(seen, key=lambda x: pkgs[x]['name']):
    p = pkgs[i]
    text = license_texts(p)
    if text.startswith('Licença:'):
        missing.append(p['name'])
    key = re.sub(r'\s+', ' ', text)
    groups.setdefault(key, {'packages': [], 'text': text})['packages'].append(f"{p['name']} {p['version']}")

entries = sorted(groups.values(), key=lambda e: e['packages'][0])
if apache_full:
    entries.insert(0, {'packages': ['Apache License 2.0'], 'text': apache_full})
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w') as fh:
    json.dump(entries, fh, ensure_ascii=False, separators=(',', ':'))
print(f'{len(seen)} pacotes em {len(entries)} textos → {os.path.relpath(OUT, ROOT)} ({os.path.getsize(OUT) // 1024} KB)')
if missing:
    print('sem arquivo de licença (usado o SPDX):', ', '.join(missing), file=sys.stderr)
