#!/usr/bin/env python3
"""Acha e tira as músicas repetidas da biblioteca.

Duas músicas são a mesma quando:

  1. o **áudio é idêntico byte a byte** (só as etiquetas mudam), ou
  2. o **AudioMuse deu a mesma impressão digital acústica** para as duas —
     é a mesma gravação, mesmo em qualidades diferentes.

Nada é apagado de verdade: as repetidas vão para uma pasta de descarte no
mesmo disco (mover é instantâneo e dá para voltar atrás). A letra `.lrc` e
a capa ao lado do arquivo vão junto.

Uso:
    ./dev/limpa_repetidas.py                 # só mostra o que faria
    ./dev/limpa_repetidas.py --aplicar       # move as repetidas
    ./dev/limpa_repetidas.py --lista saida.txt
"""
import argparse
import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

MUSICA = Path(os.environ.get("BK_MUSICA", "/media/thieggs/RAID0/Music"))
NAVIDROME = os.environ.get("BK_NAVIDROME_DB", "/media/thieggs/RAID0/navidrome/data/navidrome.db")
CONTAINER = os.environ.get("AUDIOMUSE_DB", "audiomuse-postgres")
DB = os.environ.get("AUDIOMUSE_DBNAME", "audiomusedb")
USER = os.environ.get("AUDIOMUSE_DBUSER", "audiomuse")
AUDIO = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".wma", ".aac"}
# A letra acompanha a música. Imagem não: costuma ser a capa do álbum.
JUNTO = {".lrc", ".txt"}
# Gravações com durações muito diferentes não são a mesma coisa, mesmo que
# a impressão digital bata (versão editada, faixa cortada).
TOLERANCIA_S = 3.0
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "bk-limpa-repetidas.json"
# "01 - Nome.mp3", "01-05 - Nome.mp3": arquivo vindo de um álbum inteiro.
DE_ALBUM = re.compile(r"^\d{1,2}(-\d{1,2})? - ")
# "Nome (2).mp3": cópia que o navegador numerou ao baixar de novo.
COPIA = re.compile(r" \(\d+\)$")


def psql(sql: str) -> list[list[str]]:
    out = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", USER, "-d", DB, "-tAF\t", "-c", sql],
        capture_output=True, text=True, timeout=600)
    if out.returncode != 0:
        print(f"aviso: banco do AudioMuse indisponível ({out.stderr.strip()[:80]})", file=sys.stderr)
        return []
    return [l.split("\t") for l in out.stdout.splitlines() if l.strip()]


def impressoes() -> dict[str, str]:
    """Caminho de hoje -> impressão digital acústica, para cada música.

    O AudioMuse também guarda um caminho, mas é uma foto de quando a análise
    rodou: quem reorganiza a biblioteca deixa aquilo todo errado. Quem sabe
    onde a música está agora é o Navidrome, e a ligação entre os dois é o id
    que o AudioMuse anotou.
    """
    try:
        con = sqlite3.connect(f"file:{NAVIDROME}?mode=ro", uri=True)
    except sqlite3.Error as e:
        print(f"aviso: não deu para ler o banco do Navidrome ({e})", file=sys.stderr)
        return {}
    try:
        caminho_de = {r[0]: r[1] for r in con.execute("SELECT id, path FROM media_file WHERE missing = 0")}
    finally:
        con.close()
    return {caminho_de[i]: fp for fp, i in
            (l for l in psql("SELECT item_id, provider_track_id FROM track_server_map") if len(l) == 2)
            if i in caminho_de}


def examina(caminho: Path) -> dict | None:
    """Lê duração, qualidade, etiquetas e o resumo do áudio de um arquivo."""
    try:
        p = subprocess.run(
            ["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", str(caminho)],
            capture_output=True, text=True, timeout=120)
        if p.returncode != 0:
            return None
        dados = json.loads(p.stdout)
        fmt = dados.get("format", {})
        som = next((s for s in dados.get("streams", []) if s.get("codec_type") == "audio"), {})
        # -c copy não decodifica: o resumo é do áudio guardado, sem as etiquetas.
        m = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(caminho), "-map", "0:a:0", "-c", "copy", "-f", "md5", "-"],
            capture_output=True, text=True, timeout=300)
        resumo = m.stdout.strip().removeprefix("MD5=") if m.returncode == 0 else ""
        tags = {k.lower(): v for k, v in (fmt.get("tags") or {}).items()}
        st = caminho.stat()
        # A taxa do arquivo inteiro conta capa e etiquetas; a do fluxo, não.
        # Arredondar absorve a variação de quem gravou em taxa variável.
        taxa = int(som.get("bit_rate") or fmt.get("bit_rate") or 0)
        return {
            "resumo": resumo,
            "bytes": st.st_size,
            "mtime": int(st.st_mtime),
            "segundos": float(fmt.get("duration") or 0),
            "taxa": round(taxa / 8000) * 8,
            "sem_perda": som.get("codec_name") in {"flac", "alac", "pcm_s16le", "pcm_s24le"},
            "etiquetas": sum(1 for k in ("artist", "title", "album", "track", "date") if tags.get(k)),
            "de_album": bool(tags.get("album") and tags.get("track")),
        }
    except Exception:
        return None


def qualidade(f: dict) -> tuple:
    """Maior é melhor. Define qual cópia fica.

    Qualidade do som primeiro. Empatou — e empata sempre que o áudio é o
    mesmo —, fica a cópia que pertence a um álbum, para não abrir buraco
    num disco inteiro por causa de um avulso baixado duas vezes.
    """
    caminho = f["caminho"]
    return (
        f["sem_perda"],
        f["taxa"],
        # Quem foi copiado para fora do álbum leva as etiquetas junto, então
        # o que separa os dois é o nome: "01 - Astro.mp3" veio do disco
        # inteiro, "Astro.mp3" é a avulsa. Fica a do disco.
        bool(DE_ALBUM.match(caminho.name)),
        f["de_album"],
        f["etiquetas"],
        not COPIA.search(caminho.stem),
        -len(str(caminho)),
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--aplicar", action="store_true", help="move mesmo (sem isto, só mostra)")
    ap.add_argument("--lista", type=Path, help="grava o relatório completo neste arquivo")
    ap.add_argument("--pasta", type=Path, default=MUSICA)
    ap.add_argument("--cache", type=Path, default=CACHE, help="o que já foi lido de cada arquivo")
    ap.add_argument("--descarte", type=Path, help="para onde vão as repetidas")
    args = ap.parse_args()

    raiz = args.pasta.resolve()
    descarte = args.descarte or raiz / f".repetidas-{date.today():%Y-%m-%d}"

    arquivos = sorted(p for p in raiz.rglob("*") if p.is_file() and p.suffix.lower() in AUDIO
                      and descarte not in p.parents)
    print(f"{len(arquivos)} músicas em {raiz}", file=sys.stderr)

    # Ler 6 mil arquivos leva minutos; o que não mudou vem do cache.
    cache: dict[str, dict] = {}
    if args.cache.exists():
        try:
            cache = json.loads(args.cache.read_text())
        except (OSError, ValueError):
            cache = {}

    def da_cache(p: Path) -> dict | None:
        c = cache.get(str(p))
        if not c:
            return None
        try:
            st = p.stat()
        except OSError:
            return None
        return c if c.get("bytes") == st.st_size and c.get("mtime") == int(st.st_mtime) else None

    faltando = [p for p in arquivos if da_cache(p) is None]
    print(f"lendo {len(faltando)} arquivos ({len(arquivos) - len(faltando)} já no cache)...", file=sys.stderr)
    with ThreadPoolExecutor(max_workers=min(12, (os.cpu_count() or 4) * 2)) as pool:
        for i, (p, f) in enumerate(zip(faltando, pool.map(examina, faltando)), 1):
            if f:
                cache[str(p)] = f
            if i % 500 == 0:
                print(f"  {i}/{len(faltando)}", file=sys.stderr)
    try:
        args.cache.parent.mkdir(parents=True, exist_ok=True)
        args.cache.write_text(json.dumps(cache))
    except OSError as e:
        print(f"aviso: não deu para gravar o cache: {e}", file=sys.stderr)

    fichas = [dict(cache[str(p)], caminho=p) for p in arquivos if str(p) in cache]
    print(f"  {len(fichas)} lidos", file=sys.stderr)

    digital = impressoes()
    print(f"{len(digital)} impressões digitais do AudioMuse", file=sys.stderr)

    # Junta o que é a mesma música: primeiro o áudio idêntico, depois a
    # impressão digital. Um arquivo pode ligar dois grupos, então usamos
    # conjuntos disjuntos.
    pai: dict[int, int] = {}

    def acha(x: int) -> int:
        while pai.setdefault(x, x) != x:
            pai[x] = pai[pai[x]]
            x = pai[x]
        return x

    def une(a: int, b: int) -> None:
        ra, rb = acha(a), acha(b)
        if ra != rb:
            pai[ra] = rb

    for chave in ("resumo", "digital"):
        cesto: dict[str, list[int]] = defaultdict(list)
        for i, f in enumerate(fichas):
            v = f["resumo"] if chave == "resumo" else digital.get(str(f["caminho"].relative_to(raiz)), "")
            if v:
                cesto[v].append(i)
        for indices in cesto.values():
            for j in indices[1:]:
                une(indices[0], j)

    grupos: dict[int, list[dict]] = defaultdict(list)
    for i, f in enumerate(fichas):
        grupos[acha(i)].append(f)

    manter: list[dict] = []
    tirar: list[tuple[dict, dict]] = []   # (repetida, a que fica)
    conferir: list[list[dict]] = []
    for membros in grupos.values():
        if len(membros) < 2:
            continue
        # A impressão digital reconhece a gravação, não a edição: o mesmo
        # show pode estar cortado em pontos diferentes. Então o grupo é
        # separado por duração, e cada pedaço é resolvido por conta.
        membros.sort(key=lambda m: m["segundos"])
        pedacos: list[list[dict]] = []
        for m in membros:
            if pedacos and m["segundos"] - pedacos[-1][0]["segundos"] <= TOLERANCIA_S:
                pedacos[-1].append(m)
            else:
                pedacos.append([m])
        if len(pedacos) > 1:
            conferir.append(membros)
        for pedaco in pedacos:
            if len(pedaco) < 2:
                continue
            pedaco.sort(key=qualidade, reverse=True)
            fica = pedaco[0]
            manter.append(fica)
            tirar += [(m, fica) for m in pedaco[1:]]

    relatorio: list[str] = []
    for repetida, fica in tirar:
        relatorio.append(f"TIRA  {repetida['caminho'].relative_to(raiz)}\n"
                         f"  fica {fica['caminho'].relative_to(raiz)}")
    for membros in conferir:
        relatorio.append("CONFERIR (mesma gravação em durações diferentes; só as de duração "
                         "igual foram tratadas):\n" + "\n".join(
            f"  {m['segundos']:7.1f}s  {m['caminho'].relative_to(raiz)}" for m in membros))

    texto = "\n".join(relatorio)
    if args.lista:
        args.lista.write_text(texto + "\n", encoding="utf-8")
    else:
        print(texto)

    ganho = sum(r["bytes"] for r, _ in tirar) / 1048576
    print(f"\n{len(tirar)} repetidas ({ganho:.0f} MB), {len(manter)} músicas ficam com cópia única, "
          f"{len(conferir)} grupos para conferir à mão", file=sys.stderr)

    if not args.aplicar:
        print("nada foi movido (use --aplicar)", file=sys.stderr)
        return

    descarte.mkdir(parents=True, exist_ok=True)
    movidos = 0
    for repetida, _ in tirar:
        origem = repetida["caminho"]
        destino = descarte / origem.relative_to(raiz)
        destino.parent.mkdir(parents=True, exist_ok=True)
        acompanham = [x for x in origem.parent.glob(glob.escape(origem.stem) + ".*")
                      if x.suffix.lower() in JUNTO]
        for x in [origem] + acompanham:
            alvo = destino.parent / x.name
            try:
                shutil.move(str(x), str(alvo))
            except OSError as e:
                print(f"erro ao mover {x}: {e}", file=sys.stderr)
        movidos += 1
    print(f"{movidos} movidas para {descarte}", file=sys.stderr)


if __name__ == "__main__":
    main()
