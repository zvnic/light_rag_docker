#!/usr/bin/env bash
# Создаёт .env из .env.example и подставляет случайные ключи для LIGHTRAG_API_KEY и TOKEN_SECRET.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_EXAMPLE=".env.example"
ENV_FILE=".env"

if [[ ! -f "$ENV_EXAMPLE" ]]; then
  echo "Ошибка: $ENV_EXAMPLE не найден." >&2
  exit 1
fi

# Криптостойкие случайные строки (64 hex-символа = 32 байта)
LIGHTRAG_API_KEY="$(openssl rand -hex 32)"
TOKEN_SECRET="$(openssl rand -hex 32)"

# Копируем пример и подставляем ключи
sed -e "s|^LIGHTRAG_API_KEY=$|LIGHTRAG_API_KEY=${LIGHTRAG_API_KEY}|" \
    -e "s|^TOKEN_SECRET=$|TOKEN_SECRET=${TOKEN_SECRET}|" \
    "$ENV_EXAMPLE" > "$ENV_FILE"

echo "Создан $ENV_FILE с новыми LIGHTRAG_API_KEY и TOKEN_SECRET."
echo "LIGHTRAG_API_KEY: ${LIGHTRAG_API_KEY:0:8}...${LIGHTRAG_API_KEY: -8}"
echo "TOKEN_SECRET:    ${TOKEN_SECRET:0:8}...${TOKEN_SECRET: -8}"
