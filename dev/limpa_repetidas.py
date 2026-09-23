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
import json
import os
import shutil
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

MUSICA = Path(os.environ.get("BK_MUSICA", "/media/thieggs/RAID0/Music"))
CONTAINER = os.environ.get("AUDIOMUSE_DB", "audiomuse-postgres")
DB = os.environ.get("AUDIOMUSE_DBNAME", "audiomusedb")
USER = os.environ.get("AUDIOMUSE_DBUSER", "audiomuse")
AUDIO = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".wma", ".aac"}
# Arquivos que acompanham a música e devem ir junto com ela.
JUNTO = {".lrc", ".txt", ".jpg", ".png"}
# Gravações com durações muito diferentes não são a mesma coisa, mesmo que
# a impressão digital bata (versão editada, faixa cortada).
TOLERANCIA_S = 3.0


def psql(sql: str) -> list[list[str]]:
    out = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", USER, "-d", DB, "-tAF\t", "-c", sql],
        capture_output=True, text=True, timeout=600)
    if out.returncode != 0:
        print(f"aviso: banco do AudioMuse indisponível ({out.stderr.strip()[:80]})", file=sys.stderr)
        return []
    return [l.split("\t") for l in out.stdout.splitlines() if l.strip()]


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
        return {
            "caminho": caminho,
            "resumo": resumo,
            "bytes": caminho.stat().st_size,
            "segundos": float(fmt.get("duration") or 0),
            "taxa": int(fmt.get("bit_rate") or 0),
            "sem_perda": som.get("codec_name") in {"flac", "alac", "pcm_s16le", "pcm_s24le"},
            "etiquetas": sum(1 for k in ("artist", "title", "album", "track", "date") if tags.get(k)),
            "titulo": tags.get("title", ""),
        }
    except Exception:
        return None


def qualidade(f: dict, por_pasta: dict[Path, int]) -> tuple:
    """Maior é melhor. Define qual cópia fica."""
    return (f["sem_perda"], f["taxa"], f["bytes"], f["etiquetas"],
            por_pasta[f["caminho"].parent], -len(str(f["caminho"])))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--aplicar", action="store_true", help="move mesmo (sem isto, só mostra)")
    ap.add_argument("--lista", type=Path, help="grava o relatório completo neste arquivo")
    ap.add_argument("--pasta", type=Path, default=MUSICA)
    ap.add_argument("--descarte", type=Path, help="para onde vão as repetidas")
    args = ap.parse_args()

    raiz = args.pasta.resolve()
    descarte = args.descarte or raiz / f".repetidas-{date.today():%Y-%m-%d}"

    arquivos = sorted(p for p in raiz.rglob("*") if p.is_file() and p.suffix.lower() in AUDIO
                      and descarte not in p.parents)
    print(f"{len(arquivos)} músicas em {raiz}", file=sys.stderr)

    por_pasta: dict[Path, int] = defaultdict(int)
    for p in arquivos:
        por_pasta[p.parent] += 1

    print("lendo os arquivos...", file=sys.stderr)
    fichas: list[dict] = []
    with ThreadPoolExecutor(max_workers=min(12, (os.cpu_count() or 4) * 2)) as pool:
        for i, f in enumerate(pool.map(examina, arquivos), 1):
            if f:
                fichas.append(f)
            if i % 500 == 0:
                print(f"  {i}/{len(arquivos)}", file=sys.stderr)
    print(f"  {len(fichas)} lidos", file=sys.stderr)

    # Impressão digital acústica que o AudioMuse já calculou, quando houver.
    digital: dict[str, str] = {}
    for linha in psql("SELECT DISTINCT file_path, item_id FROM track_server_map WHERE file_path <> ''"):
        if len(linha) == 2:
            digital[linha[0]] = linha[1]
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
        duracoes = [m["segundos"] for m in membros if m["segundos"] > 0]
        if duracoes and max(duracoes) - min(duracoes) > TOLERANCIA_S:
            conferir.append(membros)
            continue
        membros.sort(key=lambda f: qualidade(f, por_pasta), reverse=True)
        fica = membros[0]
        manter.append(fica)
        tirar += [(m, fica) for m in membros[1:]]

    relatorio: list[str] = []
    for repetida, fica in tirar:
        relatorio.append(f"TIRA  {repetida['caminho'].relative_to(raiz)}\n"
                         f"  fica {fica['caminho'].relative_to(raiz)}")
    for membros in conferir:
        relatorio.append("CONFERIR (durações diferentes):\n" + "\n".join(
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
        acompanham = [x for x in origem.parent.glob(origem.stem + ".*")
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
