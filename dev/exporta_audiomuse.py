#!/usr/bin/env python3
"""Exporta os vetores do AudioMuse para um arquivo que o app lê offline.

O AudioMuse gera os vetores (a parte cara, com rede neural) e guarda no
Postgres dele. Este script só lê, empacota e grava um arquivo; nada é
alterado no AudioMuse.

O app usa isso para achar músicas parecidas sem internet e sem pesar:
comparar uma música com as outras 5 mil são poucos milissegundos.

Uso:  ./dev/exporta_audiomuse.py [saída]
      (padrão: ~/.local/share/bk-analyzer/vetores.bkvec)
"""
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

CONTAINER = os.environ.get("AUDIOMUSE_DB", "audiomuse-postgres")
DB = os.environ.get("AUDIOMUSE_DBNAME", "audiomusedb")
USER = os.environ.get("AUDIOMUSE_DBUSER", "audiomuse")

MAGIC = b"BKVEC\x02\x00\x00"
AUDIO_DIMS = 200
LYRICS_DIMS = 768
ID_LEN = 32
# Mesma ordem em que o app lê (ver `vectors.rs`).
OTHER = ["danceable", "aggressive", "happy", "party", "relaxed", "sad"]
KEYS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
# Sinônimos que o AudioMuse escreve com grafias diferentes.
KEY_ALIAS = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}


def psql(sql: str) -> list[list[str]]:
    """Roda uma consulta e devolve as linhas já separadas por tabulação."""
    out = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", USER, "-d", DB, "-tAF\t", "-c", sql],
        capture_output=True, text=True, timeout=600,
    )
    if out.returncode != 0:
        sys.exit(f"erro no banco: {out.stderr.strip()}")
    return [l.split("\t") for l in out.stdout.splitlines() if l.strip()]


def pares(texto: str) -> dict[str, float]:
    """"rock:0.5,pop:0.4" -> {"rock": 0.5, "pop": 0.4}"""
    d = {}
    for parte in (texto or "").split(","):
        nome, _, valor = parte.partition(":")
        nome = nome.strip()
        if not nome:
            continue
        try:
            d[nome] = float(valor)
        except ValueError:
            pass
    return d


def vetor(hexa: str, dims: int) -> bytes:
    """bytea em hexadecimal (\\x...) -> bytes, conferindo o tamanho."""
    if not hexa or not hexa.startswith("\\x"):
        return b"\x00" * (dims * 4)
    b = bytes.fromhex(hexa[2:])
    if len(b) != dims * 4:
        return b"\x00" * (dims * 4)
    return b


def main() -> None:
    saida = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".local/share/bk-analyzer/vetores.bkvec"

    print("lendo o vocabulário de estilos...", file=sys.stderr)
    estilos = sorted(r[0] for r in psql(
        "WITH t AS (SELECT split_part(unnest(string_to_array(mood_vector, ',')), ':', 1) AS x FROM score) "
        "SELECT DISTINCT x FROM t WHERE x <> ''"))
    idx = {e: i for i, e in enumerate(estilos)}
    print(f"  {len(estilos)} estilos", file=sys.stderr)

    print("lendo as músicas (isto demora um pouco)...", file=sys.stderr)
    linhas = psql("""
        SELECT s.item_id, s.tempo, s.key, s.scale, s.energy, s.year,
               s.mood_vector, s.other_features,
               encode(e.embedding, 'hex'), encode(l.embedding, 'hex')
        FROM score s
        JOIN embedding e ON e.item_id = s.item_id
        LEFT JOIN lyrics_embedding l ON l.item_id = s.item_id
    """)
    if not linhas:
        sys.exit("nada para exportar (o AudioMuse já analisou a biblioteca?)")
    # A mesma música costuma existir em vários arquivos (single, álbum,
    # coletânea): o vetor vai uma vez só e todos os ids apontam para ele.
    # Sem isso, "parecidas" traria a mesma faixa repetida.
    ordem = {r[0]: i for i, r in enumerate(linhas)}
    ids = [(sid, ordem[item]) for item, sid in psql(
        "SELECT item_id, provider_track_id FROM track_server_map WHERE provider_track_id <> ''")
        if item in ordem]
    print(f"  {len(linhas)} músicas distintas, {len(ids)} arquivos na biblioteca", file=sys.stderr)

    cabecalho = struct.pack(
        "<8sIIIIII", MAGIC, len(ids), len(linhas), AUDIO_DIMS, LYRICS_DIMS, len(estilos), ID_LEN)
    vocab = ("\n".join(estilos)).encode()

    tmp = Path(tempfile.mkstemp(dir=saida.parent if saida.parent.exists() else None, suffix=".tmp")[1])
    saida.parent.mkdir(parents=True, exist_ok=True)
    with open(tmp, "wb") as f:
        f.write(cabecalho)
        f.write(struct.pack("<I", len(vocab)))
        f.write(vocab)
        # Parte 1: de cada arquivo da biblioteca para o vetor dele.
        for sid, i in ids:
            f.write(sid.encode()[:ID_LEN].ljust(ID_LEN, b"\x00"))
            f.write(struct.pack("<I", i))
        # Parte 2: os vetores, um por música distinta.
        for r in linhas:
            (_item, tempo, key, scale, energy, year, mood, outras, emb, lyr) = (r + [""] * 10)[:10]
            f.write(struct.pack("<ff", float(tempo or 0), float(energy or 0)))
            f.write(struct.pack("<H", min(int(year or 0), 65535)))
            k = KEY_ALIAS.get(key, key)
            f.write(struct.pack("<BB", KEYS.index(k) if k in KEYS else 255,
                                {"major": 0, "minor": 1}.get((scale or "").lower(), 255)))
            of = pares(outras)
            f.write(bytes(round(255 * max(0.0, min(1.0, of.get(n, 0.0)))) for n in OTHER))
            est = bytearray(len(estilos))
            for nome, v in pares(mood).items():
                if nome in idx:
                    est[idx[nome]] = round(255 * max(0.0, min(1.0, v)))
            f.write(bytes(est))
            f.write(vetor("\\x" + emb if emb else "", AUDIO_DIMS))
            f.write(vetor("\\x" + lyr if lyr else "", LYRICS_DIMS))
    tmp.replace(saida)
    mb = saida.stat().st_size / 1048576
    print(f"{saida} ({mb:.1f} MB, {len(linhas)} músicas, {len(ids)} arquivos)")


if __name__ == "__main__":
    main()
