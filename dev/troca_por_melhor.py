#!/usr/bin/env python3
"""Troca as músicas da biblioteca pelas versões melhores de outra pasta.

A mesma música baixada de novo em qualidade maior é **outro arquivo**: outro
tamanho, outro resumo, muitas vezes outro nome. O que casa as duas é a
**impressão digital do áudio** (chromaprint): ela descreve o som, não os bytes,
então sobrevive a recodificar, a mudar de MP3 para FLAC e a etiquetas trocadas.

Comparar a impressão não é "igual ou diferente": são dois vetores de números, e
o que vale é quantos bits diferem entre eles ([ERRO_MAXIMO]). Por isso a
duração entra como guarda — impressão parecida com duração diferente é outra
gravação (ao vivo, remix, versão estendida).

Só troca quando o **som** é melhor: sem perda ganha de com perda; entre duas
com perda, a taxa tem que ser bem maior; entre duas sem perda, quem decide é
a resolução (bits e amostragem) — a taxa de um FLAC só diz o quanto ele foi
comprimido, não o quanto ele soa melhor.

Com `--adicionar`, o que a biblioteca não tem entra nela, em
`Artista/Álbum/NN - Título`. Com `--playlists`, cada pasta da nova que vem com
um `.m3u` do lado (é assim que o downloader entrega uma playlist) vira um
`.m3u` em `Playlists/` dentro da biblioteca, apontando para as músicas de lá —
o Navidrome importa sozinho na próxima leitura. A ordem é a do número no
começo do nome do arquivo, porque o `.m3u` do downloader costuma vir pela
metade.

NADA É APAGADO. O que sai vai para uma pasta de lixo com um registro em JSON
que permite desfazer. E sem `--aplicar` o programa só mostra o que faria.

Uso:
    ./dev/troca_por_melhor.py NOVA                      # só mostra
    ./dev/troca_por_melhor.py NOVA --aplicar
    ./dev/troca_por_melhor.py NOVA --adicionar --playlists --aplicar
    ./dev/troca_por_melhor.py NOVA --biblioteca PASTA   # outra biblioteca
    ./dev/troca_por_melhor.py --desfazer
    ./dev/troca_por_melhor.py --migrar-navidrome        # depois que o Navidrome releu

Quando a extensão muda (MP3 virou FLAC), para o Navidrome é outro arquivo, com
outro id: estrela, plays e lugar nas playlists ficariam no antigo, que agora
consta como sumido. `--migrar-navidrome` passa tudo isso para o novo. Ele para
o container por alguns segundos, porque mexer no banco com o servidor
escrevendo nele é pedir para corromper.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from limpa_repetidas import examina, qualidade  # noqa: E402  (mesma régua de qualidade)

BIBLIOTECA = Path(os.environ.get("BK_MUSICA", "/media/thieggs/RAID0/Music"))
LIXO = Path.home() / "musicas-trocadas"
NAVIDROME_DB = Path(os.environ.get("BK_NAVIDROME_DB", "/media/thieggs/RAID0/navidrome/data/navidrome.db"))
NAVIDROME_CONTAINER = os.environ.get("BK_NAVIDROME_CONTAINER", "navidrome")
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "bk-impressoes.json"
# .webm entra porque o downloader às vezes entrega um; na biblioteca ele vira
# .opus (mesmo áudio, só trocando a caixa), que todo player entende.
EXTENSOES = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".wma", ".aac", ".alac", ".aiff", ".webm"}
PLAYLISTS = "Playlists"
POSICAO = re.compile(r"^(\d+) - ")
PROIBIDO = re.compile(r'[/\\:*?"<>|\x00-\x1f]')

# Quantos bits podem diferir entre duas impressões para ainda ser a mesma
# gravação. O chromaprint devolve 32 bits por quadro (~0,12 s); recodificar
# mexe em alguns. Acima disto é outra música.
ERRO_MAXIMO = 0.18

# Outra masterização da mesma música (remaster, versão de álbum x single)
# difere bem mais que uma recodificação, mas ainda fica longe dos ~45% de duas
# músicas sem relação. Nessa faixa só casa se o título também bater.
ERRO_COM_MESMO_NOME = 0.42

# Impressão parecida mas duração diferente = outra gravação.
SEGUNDOS_DE_FOLGA = 5.0

# Com o mesmo título, a folga é maior: a mesma faixa costuma vir com outro
# fade-out ou com segundos de silêncio a mais no começo. O deslocamento
# testado também cresce (48 quadros ≈ 6 s).
SEGUNDOS_DE_FOLGA_MESMO_NOME = 15.0
DESLOCAMENTO_MESMO_NOME = 48


def impressao(caminho: Path) -> tuple[list[int], float] | None:
    """Impressão digital do áudio e a duração, pelo fpcalc."""
    try:
        p = subprocess.run(
            ["fpcalc", "-raw", "-json", "-length", "180", str(caminho)],
            capture_output=True, text=True, timeout=180)
        # Com um pedaço estragado no fim do arquivo o fpcalc sai com erro, mas
        # a impressão do que conseguiu ler vem inteira e serve.
        d = json.loads(p.stdout)
        if not d.get("fingerprint"):
            return None
        return [int(x) for x in d["fingerprint"]], float(d["duration"])
    except Exception:
        return None


def diferenca(a: np.ndarray, b: np.ndarray, alcance: int = 8) -> float:
    """Fração de bits diferentes entre duas impressões (0 = idêntica).

    Compara o trecho em que as duas se sobrepõem. Um corte de silêncio no
    começo desalinharia tudo, então tenta alguns deslocamentos e fica com o
    melhor — é barato e salva os arquivos com introduções cortadas.
    """
    melhor = 1.0
    for desloc in range(-alcance, alcance + 1):
        x = a[max(0, -desloc):]
        y = b[max(0, desloc):]
        n = min(len(x), len(y))
        if n < 40:  # pouco trecho em comum: não dá para afirmar nada
            continue
        bits = int(np.bitwise_count(x[:n] ^ y[:n]).sum())
        melhor = min(melhor, bits / (n * 32))
    return melhor


SEM_IMPORTANCIA = re.compile(
    r"\b(\d{4} )?(digital(ly)? )?remaster(ed)?( version)?( \d{4})?\b|[(\[]?\b(feat|ft)\b\.?[^)\]]*[)\]]?")


def titulos(caminho: Path) -> set[str]:
    """Formas comparáveis do título que está no nome do arquivo.

    Tira número da faixa, "Remastered 2009", "feat. Fulano", acento e
    pontuação. Na biblioteca muita música é "Artista - Título", então a parte
    depois do primeiro " - " também vale.
    """
    nome = POSICAO.sub("", re.sub(r"^\d+-\d+ - ", "", caminho.stem))
    formas = {nome}
    if " - " in nome:
        formas.add(nome.split(" - ", 1)[1])
    out = set()
    for f in formas:
        f = unicodedata.normalize("NFKD", f.lower())
        f = "".join(c for c in f if not unicodedata.combining(c))
        f = re.sub(r"[^a-z0-9]", "", SEM_IMPORTANCIA.sub("", f))
        if f:
            out.add(f)
    return out


def resolucao(caminho: Path) -> tuple[int, int]:
    """(bits, amostragem) do primeiro fluxo de áudio."""
    try:
        p = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
             "stream=bits_per_raw_sample,bits_per_sample,sample_rate", "-of", "json", str(caminho)],
            capture_output=True, text=True, timeout=60)
        s = json.loads(p.stdout)["streams"][0]
        bits = int(s.get("bits_per_raw_sample") or 0) or int(s.get("bits_per_sample") or 0)
        return bits, int(s.get("sample_rate") or 0)
    except Exception:
        return 0, 0


def soa_melhor(nova: dict, velha: dict) -> bool:
    """A nova soa melhor que a velha? Só compara o som, nunca nome ou etiqueta."""
    if nova["sem_perda"] != velha["sem_perda"]:
        return nova["sem_perda"]
    if not nova["sem_perda"]:
        # Variação de taxa variável não é melhora: precisa ser 10% maior.
        return nova["taxa"] > velha["taxa"] * 1.1
    return resolucao(nova["caminho"]) > resolucao(velha["caminho"])


def etiquetas(caminho: Path) -> dict[str, str]:
    try:
        p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags", "-of", "json", str(caminho)],
                           capture_output=True, text=True, timeout=60)
        return {k.lower(): v for k, v in (json.loads(p.stdout).get("format", {}).get("tags") or {}).items()}
    except Exception:
        return {}


def limpo(nome: str) -> str:
    return PROIBIDO.sub("_", nome).strip(" .")[:120] or "_"


def lugar_na_biblioteca(caminho: Path, biblioteca: Path) -> Path:
    """Artista/Álbum/NN - Título.ext, pelas etiquetas; sem elas, o nome que veio."""
    t = etiquetas(caminho)
    artista = t.get("album_artist") or t.get("albumartist") or t.get("artist") or "Desconhecido"
    album = t.get("album")
    faixa = (t.get("track") or "").split("/")[0]
    titulo = t.get("title") or POSICAO.sub("", caminho.stem)
    nome = f"{int(faixa):02d} - {titulo}" if faixa.isdigit() and album else titulo
    ext = ".opus" if caminho.suffix.lower() == ".webm" else caminho.suffix.lower()
    pasta = biblioteca / limpo(artista) / (limpo(album) if album else "")
    destino = pasta / (limpo(nome) + ext)
    n = 2
    while destino.exists():
        destino = pasta / f"{limpo(nome)} ({n}){ext}"
        n += 1
    return destino


def copia(origem: Path, destino: Path) -> None:
    destino.parent.mkdir(parents=True, exist_ok=True)
    if origem.suffix.lower() == ".webm" and destino.suffix == ".opus":
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(origem), "-map", "0:a:0", "-c", "copy",
                        "-map_metadata", "0", str(destino)], check=True)
    else:
        shutil.copy2(str(origem), str(destino))


def playlists_da(pasta: Path) -> dict[str, list[Path]]:
    """Pasta com um .m3u do lado = playlist, na ordem do número do arquivo."""
    out = {}
    for m3u in sorted(pasta.glob("*.m3u")):
        dentro = pasta / m3u.stem
        if not dentro.is_dir():
            continue
        faixas = [p for p in dentro.iterdir() if p.is_file() and p.suffix.lower() in EXTENSOES]
        faixas.sort(key=lambda p: (int(m.group(1)) if (m := POSICAO.match(p.name)) else 10**9, p.name))
        out[m3u.stem] = faixas
    return out


def musicas(pasta: Path) -> list[Path]:
    return sorted(p for p in pasta.rglob("*") if p.is_file() and p.suffix.lower() in EXTENSOES)


def compacta(fp: list[int]) -> str:
    """Impressão em base64: como lista de números, o cache da biblioteca
    inteira passava de 1 GB na memória e chegou a travar o PC."""
    return base64.b64encode(np.array(fp, dtype=np.uint32).tobytes()).decode()


def carrega_cache() -> dict:
    try:
        c = json.loads(CACHE.read_text())
    except Exception:
        return {}
    for d in c.values():  # cache do formato antigo
        if isinstance(d.get("fp"), list):
            d["fp"] = compacta(d["fp"])
    return c


def salva_cache(c: dict) -> None:
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(c))


def ficha(caminho: Path, cache: dict) -> dict | None:
    """Impressão + dados de qualidade, guardados por caminho+tamanho+data."""
    st = caminho.stat()
    chave = f"{caminho}|{st.st_size}|{int(st.st_mtime)}"
    if chave in cache:
        d = dict(cache[chave])
        d["caminho"] = caminho
        return d
    fp = impressao(caminho)
    info = examina(caminho)
    if fp is None or info is None:
        return None
    d = {**info, "fp": compacta(fp[0]), "fp_segundos": fp[1]}
    d.pop("caminho", None)
    cache[chave] = d
    d = dict(d)
    d["caminho"] = caminho
    return d


def fichas(arquivos: list[Path], cache: dict, rotulo: str) -> list[dict]:
    out: list[dict] = []
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        for i, d in enumerate(pool.map(lambda p: ficha(p, cache), arquivos), 1):
            if d:
                d["fpa"] = np.frombuffer(base64.b64decode(d.pop("fp")), dtype=np.uint32)
                out.append(d)
            if i % 200 == 0 or i == len(arquivos):
                print(f"  {rotulo}: {i}/{len(arquivos)}", end="\r", flush=True)
    print()
    return out


def desfazer() -> None:
    registro = LIXO / "trocas.json"
    if not registro.exists():
        print("nada para desfazer")
        return
    trocas = json.loads(registro.read_text())
    voltou = tirou = 0
    for t in trocas:
        if "adicionada" in t or "playlist" in t:
            arq = Path(t.get("adicionada") or t["playlist"])
            if arq.exists():
                arq.unlink()
                tirou += 1
            # As pastas de artista e álbum que a adição criou saem junto.
            for pasta in (arq.parent, arq.parent.parent):
                try:
                    pasta.rmdir()
                except OSError:
                    break
            continue
        guardada, lugar = Path(t["guardada"]), Path(t["lugar"])
        novo = Path(t["novo"])
        if not guardada.exists():
            continue
        if novo.exists() and novo != lugar:
            novo.unlink()
        elif lugar.exists():
            lugar.unlink()
        lugar.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(guardada), str(lugar))
        voltou += 1
    registro.unlink()
    print(f"voltaram {voltou} músicas para o lugar · saíram {tirou} que tinham sido adicionadas")


def migrar_navidrome(biblioteca: Path) -> None:
    registro = LIXO / "trocas.json"
    if not registro.exists():
        print("nenhuma troca registrada")
        return
    todas = json.loads(registro.read_text())
    # "migrada" marca o que já passou: rodar de novo não pode somar os plays outra vez.
    trocas = [t for t in todas if "lugar" in t and t["lugar"] != t["novo"] and not t.get("migrada")]
    print(f"{len(trocas)} trocas mudaram de extensão; parando o {NAVIDROME_CONTAINER}…")
    subprocess.run(["docker", "stop", NAVIDROME_CONTAINER], check=True, capture_output=True)
    passou = sem_novo = ja_era = 0
    try:
        con = sqlite3.connect(NAVIDROME_DB)
        with con:
            def id_de(caminho: str, missing: int) -> str | None:
                rel = str(Path(caminho).relative_to(biblioteca))
                r = con.execute("SELECT id FROM media_file WHERE path = ? ORDER BY missing = ? DESC",
                                (rel, missing)).fetchone()
                return r[0] if r else None
            for t in trocas:
                velho, novo = id_de(t["lugar"], 1), id_de(t["novo"], 0)
                if novo is None or velho is None:
                    sem_novo += 1
                    continue
                t["migrada"] = True
                if velho == novo:  # o próprio Navidrome viu que era a mesma
                    ja_era += 1
                    continue
                con.execute("""
                    INSERT INTO annotation (user_id, item_id, item_type, play_count, play_date,
                                            rating, starred, starred_at, rated_at)
                    SELECT user_id, ?, item_type, play_count, play_date, rating, starred, starred_at, rated_at
                    FROM annotation WHERE item_id = ? AND item_type = 'media_file'
                    ON CONFLICT (user_id, item_id, item_type) DO UPDATE SET
                        play_count = play_count + excluded.play_count,
                        play_date = max(coalesce(play_date, ''), coalesce(excluded.play_date, '')),
                        rating = max(rating, excluded.rating),
                        starred = max(starred, excluded.starred),
                        starred_at = coalesce(starred_at, excluded.starred_at),
                        rated_at = coalesce(rated_at, excluded.rated_at)""", (novo, velho))
                con.execute("UPDATE playlist_tracks SET media_file_id = ? WHERE media_file_id = ?", (novo, velho))
                con.execute("UPDATE scrobbles SET media_file_id = ? WHERE media_file_id = ?", (novo, velho))
                con.execute("UPDATE OR IGNORE bookmark SET item_id = ? WHERE item_id = ? AND item_type = 'media_file'",
                            (novo, velho))
                passou += 1
        con.close()
        registro.write_text(json.dumps(todas, indent=1, ensure_ascii=False))
    finally:
        subprocess.run(["docker", "start", NAVIDROME_CONTAINER], check=True, capture_output=True)
    print(f"passadas {passou} · {ja_era} o Navidrome já tinha reconhecido · "
          f"{sem_novo} ainda não lidas pelo Navidrome (rode de novo depois da leitura)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("nova", nargs="?", type=Path, help="pasta com os downloads novos")
    ap.add_argument("--biblioteca", type=Path, default=BIBLIOTECA)
    ap.add_argument("--aplicar", action="store_true", help="trocar de verdade (sem isto, só mostra)")
    ap.add_argument("--adicionar", action="store_true", help="pôr na biblioteca o que ela não tem")
    ap.add_argument("--playlists", action="store_true", help="criar as playlists da nova na biblioteca")
    ap.add_argument("--migrar-navidrome", action="store_true",
                    help="passar estrela, plays e playlists das antigas para as novas no Navidrome")
    ap.add_argument("--lista", type=Path, help="gravar todos os pares (e quem ficou sem par) neste arquivo")
    ap.add_argument("--desfazer", action="store_true", help="devolver tudo o que a última rodada trocou")
    a = ap.parse_args()

    if a.desfazer:
        desfazer()
        return
    if a.migrar_navidrome:
        migrar_navidrome(a.biblioteca)
        return
    if not a.nova or not a.nova.is_dir():
        ap.error("diga a pasta com os downloads novos")
    if not a.biblioteca.is_dir():
        ap.error(f"biblioteca não encontrada: {a.biblioteca}")

    cache = carrega_cache()
    print(f"biblioteca: {a.biblioteca}")
    print(f"novas:      {a.nova}\n")
    velhas_arq, novas_arq = musicas(a.biblioteca), musicas(a.nova)
    print(f"lendo {len(velhas_arq)} da biblioteca e {len(novas_arq)} novas (a primeira vez demora)")
    velhas = fichas(velhas_arq, cache, "biblioteca")
    novas = fichas(novas_arq, cache, "novas")
    salva_cache(cache)

    # Agrupar por duração arredondada evita comparar todas contra todas: só
    # faz sentido comparar o que dura quase o mesmo.
    def agrupa(fs: list[dict]) -> dict[int, list[dict]]:
        g: dict[int, list[dict]] = {}
        for f in fs:
            g.setdefault(round(f["fp_segundos"]), []).append(f)
        return g

    def par_em(n: dict, grupos: dict[int, list[dict]]) -> tuple[dict | None, float]:
        alvo = round(n["fp_segundos"])
        perto = []
        for d in range(alvo - int(SEGUNDOS_DE_FOLGA), alvo + int(SEGUNDOS_DE_FOLGA) + 1):
            for v in grupos.get(d, []):
                e = diferenca(n["fpa"], v["fpa"])
                if e <= ERRO_COM_MESMO_NOME:
                    perto.append((e, v))
        perto.sort(key=lambda t: t[0])
        nome = titulos(n["caminho"])
        for e, v in perto:
            if e <= ERRO_MAXIMO or nome & titulos_de(v):
                return v, e
        # Segunda chance, só para quem tem o mesmo título.
        folga = int(SEGUNDOS_DE_FOLGA_MESMO_NOME)
        melhor, erro = None, 1.0
        for d in range(alvo - folga, alvo + folga + 1):
            for v in grupos.get(d, []):
                if nome & titulos_de(v):
                    e = diferenca(n["fpa"], v["fpa"], DESLOCAMENTO_MESMO_NOME)
                    if e < erro:
                        melhor, erro = v, e
        return (melhor, erro) if erro <= ERRO_COM_MESMO_NOME else (None, 1.0)

    def titulos_de(v: dict) -> set[str]:
        if "titulos" not in v:
            v["titulos"] = titulos(v["caminho"])
        return v["titulos"]

    por_duracao = agrupa(velhas)
    melhor_para: dict[Path, tuple[dict, dict, float]] = {}
    par_da: dict[Path, dict] = {}
    sem_par: list[dict] = []
    for n in novas:
        par, erro = par_em(n, por_duracao)
        if par is None:
            sem_par.append(n)
            continue
        par_da[n["caminho"]] = par
        if soa_melhor(n, par):
            # Duas baixadas podem casar com o mesmo arquivo (o 320k e o FLAC
            # da mesma música). Só a melhor delas entra: senão a segunda
            # tentaria trocar um arquivo que a primeira já tirou do lugar.
            antes = melhor_para.get(par["caminho"])
            if antes is None or soa_melhor(n, antes[1]):
                melhor_para[par["caminho"]] = (par, n, erro)
    iguais = len({v["caminho"] for v in par_da.values()} - set(melhor_para))

    trocas = sorted(melhor_para.values(), key=lambda t: str(t[0]["caminho"]))
    reservados: set[Path] = set()

    def sem_colisao(destino: Path) -> Path:
        n, base = 2, destino
        while destino.exists() or destino in reservados:
            destino = base.with_name(f"{base.stem} ({n}){base.suffix}")
            n += 1
        reservados.add(destino)
        return destino

    # A nova entra no lugar exato da antiga, só trocando a extensão: assim o
    # Navidrome mantém o álbum.
    destino_da_troca: dict[Path, Path] = {}
    for velha, nova, _ in trocas:
        ext = ".opus" if nova["caminho"].suffix.lower() == ".webm" else nova["caminho"].suffix.lower()
        destino = velha["caminho"].with_suffix(ext)
        # Nome com acento decomposto (NFD) não casa com a linha da playlist:
        # o Navidrome normaliza a linha e não acha o arquivo.
        destino = destino.with_name(unicodedata.normalize("NFC", destino.name))
        destino_da_troca[velha["caminho"]] = destino if destino == velha["caminho"] else sem_colisao(destino)

    # O que não tem par na biblioteca pode estar repetido entre as próprias
    # novas (a mesma música em duas playlists): vira um arquivo só, o melhor.
    entrar: list[list[dict]] = []
    for n in sem_par:
        achou = None
        for g in entrar:
            if abs(g[0]["fp_segundos"] - n["fp_segundos"]) <= SEGUNDOS_DE_FOLGA \
                    and diferenca(n["fpa"], g[0]["fpa"]) <= ERRO_MAXIMO:
                achou = g
                break
        if achou is None:
            entrar.append([n])
        elif soa_melhor(n, achou[0]):
            achou.insert(0, n)  # a primeira de cada grupo é a melhor
        else:
            achou.append(n)

    lugar_da: dict[Path, Path] = {}  # arquivo novo -> onde ele fica na biblioteca
    for n_caminho, par in par_da.items():
        lugar_da[n_caminho] = destino_da_troca.get(par["caminho"], par["caminho"])
    adicoes: list[tuple[Path, Path]] = []
    if a.adicionar:
        for g in entrar:
            destino = sem_colisao(lugar_na_biblioteca(g[0]["caminho"], a.biblioteca))
            adicoes.append((g[0]["caminho"], destino))
            for n in g:
                lugar_da[n["caminho"]] = destino

    listas = playlists_da(a.nova) if a.playlists else {}

    def resumo(f: dict) -> str:
        tipo = "sem perda" if f["sem_perda"] else f"{f['taxa']}k"
        return f"{tipo}, {f['bytes']/1e6:.1f} MB"

    print(f"\n{len(trocas)} para trocar · {iguais} já estão iguais ou melhores na biblioteca · "
          f"{len(entrar)} que a biblioteca não tem ({len(sem_par)} arquivos)\n")
    for velha, nova, erro in trocas[:40]:
        print(f"  {velha['caminho'].relative_to(a.biblioteca)}")
        print(f"    {resumo(velha)}  ->  {resumo(nova)}   (diferença {erro:.1%})")
    if len(trocas) > 40:
        print(f"  … e mais {len(trocas) - 40}")
    if adicoes:
        print(f"\nentram na biblioteca: {len(adicoes)}")
        for _, destino in adicoes[:15]:
            print(f"  {destino.relative_to(a.biblioteca)}")
        if len(adicoes) > 15:
            print(f"  … e mais {len(adicoes) - 15}")
    elif entrar:
        print("\n(para pôr na biblioteca as que faltam: --adicionar)")
    for nome, faixas in listas.items():
        fora = sum(1 for f in faixas if f not in lugar_da)
        print(f"\nplaylist {nome}: {len(faixas) - fora} músicas" + (f" ({fora} sem lugar na biblioteca)" if fora else ""))

    if a.lista:
        with a.lista.open("w") as f:
            for velha, nova, erro in trocas:
                f.write(f"troca\t{erro:.3f}\t{velha['fp_segundos']:.0f}s\t{nova['fp_segundos']:.0f}s\t"
                        f"{velha['caminho']}\t{nova['caminho']}\n")
            for origem, destino in adicoes:
                f.write(f"entra\t\t\t\t{destino}\t{origem}\n")
            lidos = {n["caminho"] for n in novas}
            for nome, faixas in listas.items():
                for x in faixas:
                    if x not in lugar_da:
                        f.write(f"fora\t{'sem leitura' if x not in lidos else ''}\t\t\t{nome}\t{x}\n")
        print(f"\nlista completa em {a.lista}")

    if not a.aplicar:
        print("\nsimulação. Para fazer de verdade: --aplicar")
        return

    LIXO.mkdir(parents=True, exist_ok=True)
    arq_registro = LIXO / "trocas.json"
    # Acumula: rodar de novo não pode apagar o caminho de volta da rodada anterior.
    registro = json.loads(arq_registro.read_text()) if arq_registro.exists() else []

    def grava() -> None:
        arq_registro.write_text(json.dumps(registro, indent=1, ensure_ascii=False))

    for velha, nova, _ in trocas:
        origem = velha["caminho"]
        # Guarda a antiga com a estrutura de pastas, para o --desfazer achar.
        guardada = LIXO / origem.relative_to(a.biblioteca)
        guardada.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(origem), str(guardada))
        destino = destino_da_troca[origem]
        copia(nova["caminho"], destino)
        registro.append({"guardada": str(guardada), "lugar": str(origem), "novo": str(destino)})
    grava()
    for origem, destino in adicoes:
        copia(origem, destino)
        registro.append({"adicionada": str(destino)})
    grava()

    pasta_listas = a.biblioteca / PLAYLISTS
    for nome, faixas in listas.items():
        pasta_listas.mkdir(exist_ok=True)
        m3u = pasta_listas / f"{limpo(nome)}.m3u"
        if not m3u.exists():
            registro.append({"playlist": str(m3u)})
        linhas = ["#EXTM3U", f"#PLAYLIST:{nome}"]
        # A mesma música curtida duas vezes (single e álbum) vira um arquivo
        # só na biblioteca; na playlist ela fica uma vez, na primeira posição.
        linhas += dict.fromkeys(os.path.relpath(lugar_da[f], pasta_listas) for f in faixas if f in lugar_da)
        m3u.write_text("\n".join(linhas) + "\n", encoding="utf-8")
    grava()

    print(f"\ntrocadas {len(trocas)}, adicionadas {len(adicoes)}, playlists {len(listas)}.")
    print(f"As antigas estão em {LIXO}")
    print("conferiu e gostou? pode apagar essa pasta. Não gostou: ./dev/troca_por_melhor.py --desfazer")
    print("depois, mande o Navidrome reler a biblioteca")


if __name__ == "__main__":
    main()
