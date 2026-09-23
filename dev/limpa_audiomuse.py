#!/usr/bin/env python3
"""Tira o lixo do banco do AudioMuse.

Com o tempo o banco junta três tipos de sujeira:

1. **Ligações mortas** — a cada releitura o Navidrome dá um id novo para a
   mesma música, e o AudioMuse guarda os dois. Aqui há arquivo apontado por
   até cinco ids, sendo que só um existe.
2. **Análises repetidas** — a mesma gravação analisada duas vezes, com
   vetores idênticos e impressões digitais diferentes.
3. **Análises órfãs** — sobraram de música que não está mais na biblioteca.
   Estas ficam, a não ser com `--orfas`: o `item_id` é a própria impressão
   digital do som, então uma análise sem dono é reencontrada se o arquivo
   voltar — apagar só obrigaria a rede neural a refazer o trabalho.

O que existe hoje no Navidrome é a verdade: o banco dele é lido **sem
escrever nada**. O AudioMuse só perde o que não aponta mais para lugar
nenhum; nenhuma análise de música viva é apagada.

Uso:
    ./dev/limpa_audiomuse.py               # só mostra o que faria
    ./dev/limpa_audiomuse.py --aplicar
"""
import argparse
import csv
import io
import os
import sqlite3
import subprocess
import sys

CONTAINER = os.environ.get("AUDIOMUSE_DB", "audiomuse-postgres")
DB = os.environ.get("AUDIOMUSE_DBNAME", "audiomusedb")
USER = os.environ.get("AUDIOMUSE_DBUSER", "audiomuse")
NAVIDROME = os.environ.get("BK_NAVIDROME_DB", "/media/thieggs/RAID0/navidrome/data/navidrome.db")


def psql(sql: str) -> list[list[str]]:
    out = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", USER, "-d", DB, "-v", "ON_ERROR_STOP=1",
         "-tAF\t", "-c", sql],
        capture_output=True, text=True, timeout=900)
    if out.returncode != 0:
        sys.exit(f"erro no banco do AudioMuse: {out.stderr.strip()}")
    return [l.split("\t") for l in out.stdout.splitlines() if l.strip()]


def um(sql: str) -> int:
    r = psql(sql)
    return int(r[0][0]) if r else 0


def vivos() -> set[str]:
    """Ids das músicas que o Navidrome tem agora (só leitura)."""
    con = sqlite3.connect(f"file:{NAVIDROME}?mode=ro", uri=True)
    try:
        return {r[0] for r in con.execute("SELECT id FROM media_file WHERE missing = 0")}
    finally:
        con.close()


def envia(tabela: str, coluna: str, valores: set[str]) -> None:
    """Põe uma lista numa tabela de apoio, em vez de um SQL gigante.

    CSV porque nome de arquivo tem de tudo — barra invertida, aspas, tabulação.
    """
    psql(f'DROP TABLE IF EXISTS {tabela}; CREATE TABLE {tabela} ({coluna} text PRIMARY KEY);')
    buf = io.StringIO()
    escritor = csv.writer(buf)
    for v in valores:
        escritor.writerow([v])
    out = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", USER, "-d", DB, "-v", "ON_ERROR_STOP=1",
         "-c", f"COPY {tabela} FROM STDIN WITH (FORMAT csv)"],
        input=buf.getvalue(), capture_output=True, text=True, timeout=300)
    if out.returncode != 0:
        sys.exit(f"erro ao enviar a lista {tabela}: {out.stderr.strip()}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--aplicar", action="store_true", help="apaga mesmo (sem isto, só mostra)")
    ap.add_argument("--orfas", action="store_true",
                    help="apaga também as análises sem música (obriga a reanalisar se o arquivo voltar)")
    args = ap.parse_args()

    ids = vivos()
    print(f"Navidrome: {len(ids)} músicas na biblioteca", file=sys.stderr)
    if not ids:
        sys.exit("o Navidrome não devolveu nenhuma música — não vou apagar nada")

    envia("bk_vivos", "provider_track_id", ids)

    antes = {t: um(f"SELECT count(*) FROM {t}") for t in
             ("score", "embedding", "track_server_map", "chromaprint")}

    mortas = um("SELECT count(*) FROM track_server_map m WHERE NOT EXISTS "
                "(SELECT 1 FROM bk_vivos v WHERE v.provider_track_id = m.provider_track_id)")
    fp_mortas = um("SELECT count(*) FROM chromaprint c WHERE NOT EXISTS "
                   "(SELECT 1 FROM bk_vivos v WHERE v.provider_track_id = c.provider_track_id)")
    # Análises com vetores idênticos: uma fica, as outras somem.
    repetidas = um("""
        WITH g AS (SELECT md5(embedding::text) h, count(*) n FROM embedding GROUP BY 1 HAVING count(*) > 1)
        SELECT coalesce(sum(n) - count(*), 0) FROM g""")
    print(f"\nligações mortas no mapa: {mortas}\n"
          f"impressões digitais de música que saiu: {fp_mortas}\n"
          f"análises com vetor repetido: {repetidas}", file=sys.stderr)

    orfas = um("""
        SELECT count(*) FROM score s WHERE NOT EXISTS (
          SELECT 1 FROM track_server_map m
          JOIN bk_vivos v ON v.provider_track_id = m.provider_track_id
          WHERE m.item_id = s.item_id)""")
    print(f"análises sem nenhuma música: {orfas}" + ("" if args.orfas else " (ficam; use --orfas)"),
          file=sys.stderr)

    if not args.aplicar:
        print("\nnada foi apagado (use --aplicar)", file=sys.stderr)
        psql("DROP TABLE IF EXISTS bk_vivos;")
        return

    # Tudo de uma vez: ou limpa inteiro, ou não mexe.
    psql("""
    BEGIN;
    -- 1. As repetidas passam a ser uma só: o mapa aponta para a que fica.
    CREATE TEMP TABLE bk_fica AS
      SELECT md5(embedding::text) AS h, min(item_id) AS fica FROM embedding GROUP BY 1 HAVING count(*) > 1;
    CREATE TEMP TABLE bk_some AS
      SELECT e.item_id AS sai, f.fica FROM embedding e JOIN bk_fica f ON f.h = md5(e.embedding::text)
      WHERE e.item_id <> f.fica;
    UPDATE track_server_map m SET item_id = s.fica FROM bk_some s WHERE m.item_id = s.sai;
    DELETE FROM score WHERE item_id IN (SELECT sai FROM bk_some);

    -- 2. Ligações para música que não existe mais no Navidrome.
    DELETE FROM track_server_map m WHERE NOT EXISTS
      (SELECT 1 FROM bk_vivos v WHERE v.provider_track_id = m.provider_track_id);
    DELETE FROM chromaprint c WHERE NOT EXISTS
      (SELECT 1 FROM bk_vivos v WHERE v.provider_track_id = c.provider_track_id);

    COMMIT;
    """)
    if args.orfas:
        # Apaga a análise e, por cascata, os vetores dela.
        psql("DELETE FROM score s WHERE NOT EXISTS "
             "(SELECT 1 FROM track_server_map m WHERE m.item_id = s.item_id);")
    psql("DROP TABLE IF EXISTS bk_vivos;")
    psql("VACUUM (ANALYZE) score, embedding, clap_embedding, lyrics_embedding, track_server_map, chromaprint;")

    depois = {t: um(f"SELECT count(*) FROM {t}") for t in antes}
    print("", file=sys.stderr)
    for t in antes:
        print(f"{t:20} {antes[t]:6} -> {depois[t]:6}  ({depois[t] - antes[t]:+d})", file=sys.stderr)
    print("\nO índice de busca (ivf_*) é refeito pelo próprio AudioMuse na próxima análise.",
          file=sys.stderr)


if __name__ == "__main__":
    main()
