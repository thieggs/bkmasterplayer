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

Quem fica é decidido pela mesma régua da limpeza de repetidas: sem perda ganha
de com perda, taxa maior ganha de menor, e empate vai para a que está num
álbum completo.

NADA É APAGADO. O que sai vai para uma pasta de lixo com um registro em JSON
que permite desfazer. E sem `--aplicar` o programa só mostra o que faria.

Uso:
    ./dev/troca_por_melhor.py NOVA                      # só mostra
    ./dev/troca_por_melhor.py NOVA --aplicar
    ./dev/troca_por_melhor.py NOVA --biblioteca PASTA   # outra biblioteca
    ./dev/troca_por_melhor.py --desfazer
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from limpa_repetidas import examina, qualidade  # noqa: E402  (mesma régua de qualidade)

BIBLIOTECA = Path(os.environ.get("BK_MUSICA", "/media/thieggs/RAID0/Music"))
LIXO = Path.home() / "musicas-trocadas"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "bk-impressoes.json"
EXTENSOES = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".wma", ".aac", ".alac", ".aiff"}

# Quantos bits podem diferir entre duas impressões para ainda ser a mesma
# gravação. O chromaprint devolve 32 bits por quadro (~0,12 s); recodificar
# mexe em alguns. Acima disto é outra música.
ERRO_MAXIMO = 0.18

# Impressão parecida mas duração diferente = outra gravação.
SEGUNDOS_DE_FOLGA = 5.0


def impressao(caminho: Path) -> tuple[list[int], float] | None:
    """Impressão digital do áudio e a duração, pelo fpcalc."""
    try:
        p = subprocess.run(
            ["fpcalc", "-raw", "-json", "-length", "180", str(caminho)],
            capture_output=True, text=True, timeout=180)
        if p.returncode != 0:
            return None
        d = json.loads(p.stdout)
        return [int(x) for x in d["fingerprint"]], float(d["duration"])
    except Exception:
        return None


def diferenca(a: list[int], b: list[int]) -> float:
    """Fração de bits diferentes entre duas impressões (0 = idêntica).

    Compara o trecho em que as duas se sobrepõem. Um corte de silêncio no
    começo desalinharia tudo, então tenta alguns deslocamentos e fica com o
    melhor — é barato e salva os arquivos com introduções cortadas.
    """
    if not a or not b:
        return 1.0
    melhor = 1.0
    for desloc in range(-8, 9):
        x = a[max(0, -desloc):]
        y = b[max(0, desloc):]
        n = min(len(x), len(y))
        if n < 40:  # pouco trecho em comum: não dá para afirmar nada
            continue
        bits = sum(bin(x[i] ^ y[i]).count("1") for i in range(n))
        melhor = min(melhor, bits / (n * 32))
    return melhor


def musicas(pasta: Path) -> list[Path]:
    return sorted(p for p in pasta.rglob("*") if p.is_file() and p.suffix.lower() in EXTENSOES)


def carrega_cache() -> dict:
    try:
        return json.loads(CACHE.read_text())
    except Exception:
        return {}


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
    d = {**info, "fp": fp[0], "fp_segundos": fp[1]}
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
    voltou = 0
    for t in trocas:
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
    print(f"voltaram {voltou} músicas para o lugar")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("nova", nargs="?", type=Path, help="pasta com os downloads novos")
    ap.add_argument("--biblioteca", type=Path, default=BIBLIOTECA)
    ap.add_argument("--aplicar", action="store_true", help="trocar de verdade (sem isto, só mostra)")
    ap.add_argument("--desfazer", action="store_true", help="devolver tudo o que a última rodada trocou")
    a = ap.parse_args()

    if a.desfazer:
        desfazer()
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
    por_duracao: dict[int, list[dict]] = {}
    for v in velhas:
        por_duracao.setdefault(round(v["fp_segundos"]), []).append(v)

    melhor_para: dict[Path, tuple[dict, dict, float]] = {}
    iguais, sem_par = 0, 0
    for n in novas:
        alvo = round(n["fp_segundos"])
        candidatas = [v for d in range(alvo - int(SEGUNDOS_DE_FOLGA), alvo + int(SEGUNDOS_DE_FOLGA) + 1)
                      for v in por_duracao.get(d, [])]
        par, erro = None, 1.0
        for v in candidatas:
            e = diferenca(n["fp"], v["fp"])
            if e < erro:
                par, erro = v, e
        if par is None or erro > ERRO_MAXIMO:
            sem_par += 1
            continue
        if qualidade(n) > qualidade(par):
            # Duas baixadas podem casar com o mesmo arquivo (o 320k e o FLAC
            # da mesma música). Só a melhor delas entra: senão a segunda
            # tentaria trocar um arquivo que a primeira já tirou do lugar.
            antes = melhor_para.get(par["caminho"])
            if antes is None or qualidade(n) > qualidade(antes[1]):
                melhor_para[par["caminho"]] = (par, n, erro)
        else:
            iguais += 1

    trocas = sorted(melhor_para.values(), key=lambda t: str(t[0]["caminho"]))

    def resumo(f: dict) -> str:
        tipo = "sem perda" if f["sem_perda"] else f"{f['taxa']}k"
        return f"{tipo}, {f['bytes']/1e6:.1f} MB"

    print(f"\n{len(trocas)} para trocar · {iguais} já estão iguais ou melhores · {sem_par} sem par na biblioteca\n")
    for velha, nova, erro in trocas[:40]:
        print(f"  {velha['caminho'].relative_to(a.biblioteca)}")
        print(f"    {resumo(velha)}  ->  {resumo(nova)}   (diferença {erro:.1%})")
    if len(trocas) > 40:
        print(f"  … e mais {len(trocas) - 40}")

    if not a.aplicar:
        print("\nsimulação. Para trocar de verdade: --aplicar")
        return

    LIXO.mkdir(parents=True, exist_ok=True)
    registro = []
    for velha, nova, _ in trocas:
        origem = velha["caminho"]
        # Guarda a antiga com a estrutura de pastas, para o --desfazer achar.
        guardada = LIXO / origem.relative_to(a.biblioteca)
        guardada.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(origem), str(guardada))
        # A nova entra no lugar exato da antiga, só trocando a extensão: assim
        # o Navidrome mantém o álbum e as playlists não quebram.
        destino = origem.with_suffix(nova["caminho"].suffix)
        shutil.copy2(str(nova["caminho"]), str(destino))
        registro.append({"guardada": str(guardada), "lugar": str(origem), "novo": str(destino)})
    (LIXO / "trocas.json").write_text(json.dumps(registro, indent=1, ensure_ascii=False))
    print(f"\ntrocadas {len(registro)}. As antigas estão em {LIXO}")
    print("conferiu e gostou? pode apagar essa pasta. Não gostou: ./dev/troca_por_melhor.py --desfazer")
    print("depois, mande o Navidrome reler a biblioteca")


if __name__ == "__main__":
    main()
