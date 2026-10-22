#!/usr/bin/env bash
# Faxina da biblioteca, tudo de uma vez — é o que o atalho da área de
# trabalho chama.
#
#   1. versão melhor              (o que foi baixado em ~/Music em alta
#                                  fidelidade substitui a da biblioteca, o
#                                  que falta entra, e as playlists de lá
#                                  viram playlists no Navidrome)
#   2. músicas repetidas          (movidas para uma pasta de descarte)
#   3. artistas grudados          ("Mandragora,420" vira dois artistas)
#   4. lixo do banco do AudioMuse (ligações mortas, análises repetidas)
#   5. vetores refeitos           (a recomendação offline do celular)
#
# Mostra tudo o que faria e só mexe depois do "sim". Nada é apagado de
# verdade: o descarte fica no mesmo disco e cada passo tem como voltar.
set -uo pipefail
cd "$(dirname "$0")/.."
MUSICA="${BK_MUSICA:-/media/thieggs/RAID0/Music}"
DESCARTE="${BK_DESCARTE:-/media/thieggs/RAID0/repetidas-$(date +%F)}"
NOVAS="${BK_NOVAS:-$HOME/Music}"

azul=$'\e[1;36m'; verde=$'\e[1;32m'; amarelo=$'\e[1;33m'; vermelho=$'\e[1;31m'; off=$'\e[0m'
titulo() { echo; echo "${azul}── $* ──${off}"; }
pausar() { echo; read -rp "Pressione ENTER para fechar... " _ || true; }

quantas() {
  find "$MUSICA" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.ogg' \
    -o -iname '*.opus' -o -iname '*.wav' -o -iname '*.wma' -o -iname '*.aac' \) 2>/dev/null | wc -l
}
tamanho() { du -sh "$MUSICA" 2>/dev/null | cut -f1; }

echo "${azul}═══ Faxina da biblioteca ═══${off}"
echo
echo "Biblioteca agora: ${verde}$(quantas) músicas${off} ($(tamanho))"
echo "${amarelo}Analisando — lê a etiqueta de todas as faixas, leva alguns minutos.${off}"

# O resumo de cada ferramenta sai em stderr (vai direto para a tela, ao
# vivo) e a lista detalhada em stdout. Misturar os dois com 2>&1 embaralha a
# ordem e o resumo some no meio da lista.
detalhe=$(mktemp); trap 'rm -f "$detalhe"' EXIT

# A troca vem antes das repetidas: a cópia em alta fidelidade já entra no
# lugar da antiga, e a limpeza não precisa escolher entre as duas.
troca=0
if [ -d "$NOVAS" ] && [ -n "$(find "$NOVAS" -type f \( -iname '*.flac' -o -iname '*.m4a' -o -iname '*.mp3' \) -print -quit)" ]; then
  troca=1
  titulo "1/4  Versão melhor (de $NOVAS)"
  echo "${amarelo}A primeira vez com músicas novas demora: lê a impressão digital de cada uma.${off}"
  ./dev/troca_por_melhor.py "$NOVAS" --adicionar --playlists
else
  titulo "1/4  Versão melhor"
  echo "Nada em $NOVAS — pulando."
fi

titulo "2/4  Músicas repetidas"
./dev/limpa_repetidas.py --descarte "$DESCARTE" > "$detalhe"
echo; tail -20 "$detalhe"

titulo "3/4  Artistas grudados"
./dev/separa_artistas.py > "$detalhe"
echo; tail -15 "$detalhe"

titulo "4/4  Lixo no banco do AudioMuse"
./dev/limpa_audiomuse.py > /dev/null

echo
echo "${azul}───────────────────────────────────────────${off}"
read -rp "Aplicar tudo isso? [s/N] " r
case "${r,,}" in
  s|sim|y|yes) ;;
  *) echo "${azul}Cancelado. Nada foi alterado.${off}"; pausar; exit 0 ;;
esac

if [ "$troca" = 1 ]; then
  titulo "Trocando pela versão melhor e criando as playlists"
  ./dev/troca_por_melhor.py "$NOVAS" --adicionar --playlists --aplicar | tail -4
fi

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

if [ "$troca" = 1 ]; then
  # MP3 que virou FLAC é outro arquivo para o Navidrome: estrela, plays e
  # lugar nas playlists passam para o novo. Só depois da releitura.
  titulo "Levando estrelas e plays para as músicas trocadas"
  ./dev/troca_por_melhor.py --migrar-navidrome
fi

titulo "Limpando o banco do AudioMuse"
./dev/limpa_audiomuse.py --aplicar

titulo "Refazendo os vetores para o celular"
./dev/exporta_audiomuse.py

echo
echo "${verde}Pronto.${off}  Biblioteca: ${verde}$(quantas) músicas${off} ($(tamanho))"
echo
echo "As repetidas foram para: ${azul}$DESCARTE${off}"
[ "$troca" = 1 ] && echo "As versões antigas foram para: ${azul}$HOME/musicas-trocadas${off}  (voltar: ${azul}./dev/troca_por_melhor.py --desfazer${off})"
echo "Voltar atrás nos artistas: ${azul}./dev/separa_artistas.py --desfazer${off}"
pausar
