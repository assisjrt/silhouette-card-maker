#!/usr/bin/env bash
#
# generate-proxy-mtga.sh — automatiza o pipeline decklist -> PDF do silhouette-card-maker
#
# Uso:
#   ./generate-proxy-mtga.sh <decklist_path> [opções]
#
# Exemplo:
#   ./generate-proxy-mtga.sh game/decklist/test.txt
#   ./generate-proxy-mtga.sh game/decklist/test.txt --keep-mdfc-backs
#   ./generate-proxy-mtga.sh game/decklist/test.txt --format moxfield
#   ./generate-proxy-mtga.sh game/decklist/test.txt --pt
#   ./generate-proxy-mtga.sh game/decklist/test.txt --lang pt --lang sp
#   ./generate-proxy-mtga.sh game/decklist/test.txt --no-clean
#
# O formato padrão é mtga. O idioma padrão é inglês; use --pt (ou --lang <código>,
# repetível para montar uma lista de prioridade) para buscar as imagens em outro idioma.
# Cartas sem impressão no idioma pedido caem de volta para o inglês automaticamente.
#
# Antes do fetch, game/front/ e game/double_sided/ são limpos com clean_up.py para
# não misturar imagens de execuções anteriores. Use --no-clean para pular essa etapa.
#
# O venv é preparado/ativado automaticamente via ./setup_env.sh.
# Deve ser executado a partir da raiz do repo silhouette-card-maker
# (mesmo diretório onde ficam create_pdf.py, plugins/, game/).

set -euo pipefail

# ---- valores fixos do pipeline (README) ----
PAPER_SIZE="a4"
REGISTRATION="3"
REGISTRATION_ORIENTATION="landscape"
FIT="crop"
EXTEND_CORNERS="3.5mm"

# ---- idiomas aceitos pelo plugins/mtg (códigos impressos, ver plugins/mtg/common.py) ----
VALID_LANGS=("en" "sp" "fr" "de" "it" "pt" "jp" "kr" "ru" "cs" "ct" "ag" "ph")

# ---- args ----
if [[ $# -lt 1 ]]; then
    echo "Uso: $0 <decklist_path> [--format <formato>] [--lang <código>] [--pt] [--keep-mdfc-backs] [--skip <n>] [--no-clean]" >&2
    echo "Idiomas disponíveis: ${VALID_LANGS[*]}" >&2
    exit 1
fi

DECKLIST_PATH="$1"
shift

FORMAT="mtga"

KEEP_MDFC_BACKS=0
SKIP_INDEX=""
PREFER_LANGS=()
CLEAN_UP=1

is_valid_lang() {
    local candidate="$1"
    local lang
    for lang in "${VALID_LANGS[@]}"; do
        [[ "$lang" == "$candidate" ]] && return 0
    done
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --keep-mdfc-backs)
            KEEP_MDFC_BACKS=1
            shift
            ;;
        --skip)
            SKIP_INDEX="$2"
            shift 2
            ;;
        --lang)
            if [[ $# -lt 2 ]]; then
                echo "Erro: --lang exige um código de idioma. Disponíveis: ${VALID_LANGS[*]}" >&2
                exit 1
            fi
            if ! is_valid_lang "$2"; then
                echo "Erro: idioma desconhecido '$2'. Disponíveis: ${VALID_LANGS[*]}" >&2
                exit 1
            fi
            PREFER_LANGS+=("$2")
            shift 2
            ;;
        --pt|--portugues|--português)
            PREFER_LANGS+=("pt")
            shift
            ;;
        --no-clean)
            CLEAN_UP=0
            shift
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            exit 1
            ;;
    esac
done

# ---- checagens de ambiente ----
if [[ ! -f "create_pdf.py" ]]; then
    echo "Erro: create_pdf.py não encontrado. Execute este script a partir da raiz do repo silhouette-card-maker." >&2
    exit 1
fi

if [[ ! -f "$DECKLIST_PATH" ]]; then
    echo "Erro: decklist não encontrado em '$DECKLIST_PATH'." >&2
    exit 1
fi

if [[ ! -f "setup_env.sh" ]]; then
    echo "Erro: setup_env.sh não encontrado na raiz do repo." >&2
    exit 1
fi

if [[ "$CLEAN_UP" -eq 1 && ! -f "clean_up.py" ]]; then
    echo "Erro: clean_up.py não encontrado na raiz do repo (use --no-clean para pular a limpeza)." >&2
    exit 1
fi

# ---- 0. preparar e ativar o venv ----
echo "==> Preparando ambiente (setup_env.sh)..."
# shellcheck disable=SC1091
source ./setup_env.sh

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
    echo "Erro: venv não ficou ativo após rodar setup_env.sh." >&2
    exit 1
fi

# ---- 1. limpar imagens de execuções anteriores ----
if [[ "$CLEAN_UP" -eq 1 ]]; then
    echo "==> Limpando game/front/ e game/double_sided/ (clean_up.py)..."
    python clean_up.py
else
    echo "==> Pulando limpeza inicial (--no-clean)."
fi

# ---- 2. fetch das imagens ----
FETCH_ARGS=("$DECKLIST_PATH" "$FORMAT")

if [[ ${#PREFER_LANGS[@]} -gt 0 ]]; then
    for lang in "${PREFER_LANGS[@]}"; do
        FETCH_ARGS+=(--prefer_lang "$lang")
    done
    echo "==> Buscando imagens das cartas (formato: $FORMAT, idiomas: ${PREFER_LANGS[*]} -> en)..."
else
    echo "==> Buscando imagens das cartas (formato: $FORMAT)..."
fi

python plugins/mtg/fetch.py "${FETCH_ARGS[@]}"

# ---- 3. decidir --only_fronts vs manter double_sided ----
CREATE_PDF_ARGS=(
    --paper_size "$PAPER_SIZE"
    --registration "$REGISTRATION"
    --registration_orientation "$REGISTRATION_ORIENTATION"
    --fit "$FIT"
    --extend_corners "$EXTEND_CORNERS"
)

if [[ "$KEEP_MDFC_BACKS" -eq 0 ]]; then
    if compgen -G "game/double_sided/*" > /dev/null; then
        echo "==> Limpando game/double_sided/ (--keep-mdfc-backs não foi passado)..."
        rm -f game/double_sided/*
    fi
    CREATE_PDF_ARGS+=(--only_fronts)
else
    if ! compgen -G "game/double_sided/*" > /dev/null; then
        echo "Aviso: --keep-mdfc-backs foi passado mas game/double_sided/ está vazio. Gerando sem --only_fronts mesmo assim." >&2
    fi
fi

if [[ -n "$SKIP_INDEX" ]]; then
    CREATE_PDF_ARGS+=(--skip "$SKIP_INDEX")
fi

# ---- 4. gerar PDF ----
echo "==> Gerando PDF: python create_pdf.py ${CREATE_PDF_ARGS[*]}"
python create_pdf.py "${CREATE_PDF_ARGS[@]}"

echo "==> PDF gerado em game/output/game.pdf"
