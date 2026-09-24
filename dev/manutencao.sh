#!/usr/bin/env bash
# Faxina da biblioteca, tudo de uma vez — é o que o atalho da área de
# trabalho chama.
#
#   1. músicas repetidas          (movidas para uma pasta de descarte)
#   2. artistas grudados          ("Mandragora,420" vira dois artistas)
#   3. lixo do banco do AudioMuse (ligações mortas, análises repetidas)
#   4. vetores refeitos           (a recomendação offline do celular)
#
# Mostra tudo o que faria e só mexe depois do "sim". Nada é apagado de
# verdade: o descarte fica no mesmo disco e cada passo tem como voltar.
set -uo pipefail
cd "$(dirname "$0")/.."
MUSICA="${BK_MUSICA:-/media/thieggs/RAID0/Music}"
DESCARTE="${BK_DESCARTE:-/media/thieggs/RAID0/repetidas-$(date +%F)}"

azul=$'\e[1;36m'; verde=$'\e[1;32m'; amarelo=$'\e[1;33m'; vermelho=$'\e[1;31m'; off=$'\e[0m'
titulo() { echo; echo "${azul}── $* ──${off}"; }
pausar() { echo; read -rp "Pressione ENTER para fechar... " _ || true; }

quantas() { find "$MUSICA" -type f -iname '*.mp3' 2>/dev/null | wc -l; }
tamanho() { du -sh "$MUSICA" 2>/dev/null | cut -f1; }

echo "${azul}═══ Faxina da biblioteca ═══${off}"
echo
echo "Biblioteca agora: ${verde}$(quantas) músicas${off} ($(tamanho))"
echo "${amarelo}Analisando — lê a etiqueta de todas as faixas, leva alguns minutos.${off}"

# O resumo de cada ferramenta sai em stderr (vai direto para a tela, ao
# vivo) e a lista detalhada em stdout. Misturar os dois com 2>&1 embaralha a
# ordem e o resumo some no meio da lista.
detalhe=$(mktemp); trap 'rm -f "$detalhe"' EXIT

titulo "1/3  Músicas repetidas"
./dev/limpa_repetidas.py --descarte "$DESCARTE" > "$detalhe"
echo; tail -20 "$detalhe"

titulo "2/3  Artistas grudados"
./dev/separa_artistas.py > "$detalhe"
echo; tail -15 "$detalhe"

titulo "3/3  Lixo no banco do AudioMuse"
./dev/limpa_audiomuse.py > /dev/null

echo
echo "${azul}───────────────────────────────────────────${off}"
read -rp "Aplicar tudo isso? [s/N] " r
case "${r,,}" in
  s|sim|y|yes) ;;
  *) echo "${azul}Cancelado. Nada foi alterado.${off}"; pausar; exit 0 ;;
esac

titulo "Tirando as repetidas"
./dev/limpa_repetidas.py --aplicar --descarte "$DESCARTE" > /dev/null
find "$MUSICA" -type d -empty -delete 2>/dev/null

titulo "Separando os artistas"
./dev/separa_artistas.py --aplicar --tudo > /dev/null

titulo "Mandando o Navidrome reler"
if docker exec navidrome /app/navidrome scan --full --datafolder /data >/dev/null 2>&1; then
  echo "${verde}Navidrome releu a biblioteca.${off}"
else
  echo "${amarelo}Não consegui mandar reler; ele tem vigia e relê sozinho.${off}"
fi

titulo "Limpando o banco do AudioMuse"
./dev/limpa_audiomuse.py --aplicar

titulo "Refazendo os vetores para o celular"
./dev/exporta_audiomuse.py

echo
echo "${verde}Pronto.${off}  Biblioteca: ${verde}$(quantas) músicas${off} ($(tamanho))"
echo
echo "As repetidas foram para: ${azul}$DESCARTE${off}"
echo "Voltar atrás nos artistas: ${azul}./dev/separa_artistas.py --desfazer${off}"
pausar
