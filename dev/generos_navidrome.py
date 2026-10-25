#!/usr/bin/env python3
"""Exporta as músicas do Navidrome com o gênero das tags, para a simulação do
aleatório smart (`app/test/smart_sim_test.dart`).

O gênero das tags é a régua de fora: o ouvinte de mentira da simulação gosta
de um gênero e julga cada música por ele, sem olhar os vetores que o modo usa.

Uso: python3 dev/generos_navidrome.py [navidrome.db] > generos.json
Abre o banco só para leitura; pode rodar com o Navidrome ligado.
"""
import json
import sqlite3
import sys

db = sys.argv[1] if len(sys.argv) > 1 else '/media/thieggs/RAID0/navidrome/data/navidrome.db'
con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
out = {}
for mid, title, artist, duration, tags in con.execute(
        'select id, title, artist, duration, tags from media_file where missing = 0'):
    generos = [g.get('value') for g in json.loads(tags or '{}').get('genre') or [] if isinstance(g, dict)]
    out[mid] = {'t': title, 'a': artist, 'd': duration, 'g': [g for g in generos if g]}
json.dump(out, sys.stdout, ensure_ascii=False)
