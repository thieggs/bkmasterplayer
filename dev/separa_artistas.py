#!/usr/bin/env python3
"""Separa os artistas que vieram grudados num campo só.

Arquivo baixado costuma trazer a etiqueta assim: `Mandragora,420` ou
`1200 Mics/Cortex/Didrapest`. O Navidrome então cria **um** artista com esse
nome inteiro, e a música some quando se procura por qualquer um deles.

O conserto é na etiqueta: gravar ARTIST/ALBUMARTIST como **vários valores**
(ID3v2.4), que é o jeito certo. O Navidrome reconhece e cria cada artista,
mostrando a música em todos eles. Não depende de configuração do servidor:
os separadores personalizados do Navidrome 0.63 não funcionam (testado).

Nada é perdido: o valor original de cada arquivo vai para um arquivo de
recuo, e `--desfazer` devolve tudo como estava.

Uso:
    ./dev/separa_artistas.py                 # só mostra o que faria
    ./dev/separa_artistas.py --aplicar
    ./dev/separa_artistas.py --desfazer
"""
import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

from mutagen.id3 import ID3, TPE1, TPE2, ID3NoHeaderError

MUSICA = Path(os.environ.get("BK_MUSICA", "/media/thieggs/RAID0/Music"))
NAVIDROME = os.environ.get("BK_NAVIDROME_DB", "/media/thieggs/RAID0/navidrome/data/navidrome.db")
RECUO = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "bk-separa-artistas.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "bk-etiquetas-artista.json"
# Nome grudado com muitas músicas costuma ser banda de verdade, com disco
# inteiro — não uma colaboração que o site de download juntou num campo só.
MUITAS_MUSICAS = 4

# Vírgula, ou barra sem espaço em volta. A barra **com** espaço (" / ") o
# Navidrome já separa sozinho, e "Axwell /\ Ingrosso" fica de fora por isso.
SEPARADOR = re.compile(r"\s*,\s*|(?<!\s)/(?!\s)")

# Nomes que levam vírgula ou barra e são de um artista só.
NAO_SEPARAR = {
    "ac/dc",
    "earth, wind & fire",
    "axwell /\\ ingrosso",
    "bala, bombom e chocolate",
    "emerson, lake & palmer",
    "crosby, stills & nash",
    "crosby, stills, nash & young",
    "blood, sweat & tears",
    "peter, paul and mary",
    "kool & the gang",
}


def partes(nome: str) -> list[str]:
    return [p.strip() for p in SEPARADOR.split(nome) if p.strip()]


def artistas_conhecidos() -> set[str]:
    """Nomes que já existem sozinhos na biblioteca (só leitura)."""
    try:
        con = sqlite3.connect(f"file:{NAVIDROME}?mode=ro", uri=True)
    except sqlite3.Error:
        return set()
    try:
        return {r[0].strip().lower() for r in con.execute("SELECT name FROM artist") if r[0]}
    finally:
        con.close()


def desfazer() -> None:
    if not RECUO.exists():
        sys.exit("não há recuo guardado")
    guardado = json.loads(RECUO.read_text())
    voltaram = 0
    for caminho, antes in guardado.items():
        try:
            t = ID3(caminho)
            for quadro, valor in antes.items():
                if valor is None:
                    t.delall(quadro)
                else:
                    t.setall(quadro, [{"TPE1": TPE1, "TPE2": TPE2}[quadro](encoding=3, text=valor)])
            t.save(caminho, v2_version=4)
            voltaram += 1
        except Exception as e:
            print(f"erro em {caminho}: {e}", file=sys.stderr)
    print(f"{voltaram} arquivos voltaram ao que eram", file=sys.stderr)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--aplicar", action="store_true", help="grava mesmo (sem isto, só mostra)")
    ap.add_argument("--desfazer", action="store_true", help="devolve as etiquetas como estavam")
    ap.add_argument("--tudo", action="store_true",
                    help="separa também os nomes que ficaram para conferir à mão")
    ap.add_argument("--reler", action="store_true", help="ignora o cache e lê tudo de novo")
    ap.add_argument("--pasta", type=Path, default=MUSICA)
    args = ap.parse_args()

    if args.desfazer:
        desfazer()
        return

    conhecidos = artistas_conhecidos()
    print(f"{len(conhecidos)} artistas conhecidos na biblioteca", file=sys.stderr)

    # Ler a etiqueta de 6 mil arquivos leva minutos; o que não mudou vem do cache.
    cache: dict[str, dict] = {}
    if CACHE.exists() and not args.reler:
        try:
            cache = json.loads(CACHE.read_text())
        except (OSError, ValueError):
            cache = {}

    arquivos = sorted(args.pasta.rglob("*.mp3"))
    faltando = []
    for c in arquivos:
        g = cache.get(str(c))
        try:
            st = c.stat()
        except OSError:
            continue
        if not g or g.get("mtime") != int(st.st_mtime) or g.get("bytes") != st.st_size:
            faltando.append(c)
    print(f"lendo a etiqueta de {len(faltando)} arquivos "
          f"({len(arquivos) - len(faltando)} já no cache)...", file=sys.stderr)
    for i, c in enumerate(faltando, 1):
        try:
            t = ID3(c)
            st = c.stat()
            cache[str(c)] = {
                "mtime": int(st.st_mtime), "bytes": st.st_size,
                "TPE1": [str(x) for x in t.getall("TPE1")[0].text] if t.getall("TPE1") else None,
                "TPE2": [str(x) for x in t.getall("TPE2")[0].text] if t.getall("TPE2") else None,
            }
        except Exception:
            cache[str(c)] = {"mtime": 0, "bytes": 0, "TPE1": None, "TPE2": None}
        if i % 1000 == 0:
            print(f"  {i}/{len(faltando)}", file=sys.stderr)
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache))
    except OSError as e:
        print(f"aviso: não deu para gravar o cache: {e}", file=sys.stderr)

    # Quantas músicas cada nome grudado tem: banda de verdade tem muitas.
    quantas: dict[str, int] = {}
    for c in arquivos:
        g = cache.get(str(c)) or {}
        v = g.get("TPE1")
        if v and len(v) == 1:
            quantas[v[0].strip().lower()] = quantas.get(v[0].strip().lower(), 0) + 1

    seguros: list[tuple[Path, dict, list[str]]] = []
    conferir: list[tuple[Path, dict, list[str], str]] = []
    for caminho in arquivos:
        g = cache.get(str(caminho)) or {}
        mudar: dict[str, list[str]] = {}
        novos: list[str] = []
        nome_inteiro = ""
        for quadro in ("TPE1", "TPE2"):
            v = g.get(quadro)
            # Já é multivalor: está certo, não mexe.
            if not v or len(v) != 1:
                continue
            nome = v[0].strip()
            if nome.lower() in NAO_SEPARAR:
                continue
            pp = partes(nome)
            if len(pp) < 2:
                continue
            mudar[quadro] = pp
            if not novos:
                novos, nome_inteiro = pp, nome
        if not mudar or not novos:
            continue
        sozinhos = [x for x in novos if x.lower() in conhecidos]
        muitas = quantas.get(nome_inteiro.lower(), 0)
        # Risco: nenhum pedaço existe sozinho E o nome grudado tem disco inteiro.
        if not sozinhos and muitas >= MUITAS_MUSICAS and not args.tudo:
            conferir.append((caminho, mudar, novos, f"{muitas} músicas com esse nome inteiro"))
        else:
            seguros.append((caminho, mudar, novos))

    # Relatório por nome, que é o que dá para conferir de olho.
    def resumo(lista, rotulo, extra=False):
        por_nome: dict[str, list] = {}
        for item in lista:
            por_nome.setdefault(" + ".join(item[2]), []).append(item)
        print(f"\n=== {rotulo}: {len(por_nome)} nomes, {len(lista)} arquivos ===")
        for nome, itens in sorted(por_nome.items()):
            nota = f"   ({itens[0][3]})" if extra else ""
            print(f"  {len(itens):3}x  {nome}{nota}")

    resumo(seguros, "SEPARAR")
    if conferir:
        resumo(conferir, "CONFERIR À MÃO (use --tudo para separar também)", extra=True)

    print(f"\n{len(seguros)} arquivos para separar, {len(conferir)} para conferir à mão",
          file=sys.stderr)

    if not args.aplicar:
        print("nada foi gravado (use --aplicar)", file=sys.stderr)
        return

    guardado = json.loads(RECUO.read_text()) if RECUO.exists() else {}
    gravados = 0
    for caminho, mudar, _ in seguros:
        try:
            t = ID3(caminho)
            antes = {}
            for quadro, partes_novas in mudar.items():
                f = t.getall(quadro)
                antes[quadro] = [str(x) for x in f[0].text] if f else None
                t.setall(quadro, [{"TPE1": TPE1, "TPE2": TPE2}[quadro](encoding=3, text=partes_novas)])
            t.save(caminho, v2_version=4)
            guardado.setdefault(str(caminho), antes)
            gravados += 1
        except Exception as e:
            print(f"erro em {caminho}: {e}", file=sys.stderr)
    RECUO.parent.mkdir(parents=True, exist_ok=True)
    RECUO.write_text(json.dumps(guardado, ensure_ascii=False, indent=1))
    print(f"{gravados} arquivos separados; recuo em {RECUO}", file=sys.stderr)


if __name__ == "__main__":
    main()
