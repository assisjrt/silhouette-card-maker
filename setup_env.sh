#!/usr/bin/env bash
#
# setup_env.sh — cria o venv (se não existir) e instala/atualiza requirements.txt
#
# Uso:
#   ./setup_env.sh
#
# Deve ser executado a partir da raiz do repo silhouette-card-maker.
# Depois de rodar, ative o venv manualmente antes de usar generate_proxies.sh:
#   source venv/bin/activate

set -euo pipefail

if [[ ! -f "requirements.txt" ]]; then
    echo "Erro: requirements.txt não encontrado. Execute este script a partir da raiz do repo silhouette-card-maker." >&2
    exit 1
fi

if [[ ! -f "venv/bin/activate" ]]; then
    echo "==> Criando venv..."
    python3 -m venv venv
else
    echo "==> venv já existe em ./venv, reaproveitando."
fi

echo "==> Ativando venv..."
# shellcheck disable=SC1091
source venv/bin/activate

echo "==> Instalando dependências (requirements.txt)..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

echo "==> Ativando ambiente..."
deactivate
source venv/bin/activate

echo "==> Ambiente pronto"
