#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти от root: sudo $0"
  exit 1
fi

if ! grep -qi ubuntu /etc/os-release; then
  echo "Скрипт рассчитан на Ubuntu"
  exit 1
fi

need_cmd() { command -v "$1" >/dev/null 2>&1; }

prompt() {
  local var_name="$1" msg="$2" default="${3:-}"
  local value=""
  if [[ -n "$default" ]]; then
    read -r -p "$msg [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$msg: " value
  fi
  [[ -z "$value" ]] && { echo "Пустое значение недопустимо"; exit 1; }
  printf -v "$var_name" "%s" "$value"
}

prompt_yes_no() {
  local var_name="$1" msg="$2" default="${3:-y}"
  read -r -p "$msg (y/n) [$default]: " value
  value="${value:-$default}"
  case "$value" in
    y|Y) printf -v "$var_name" "y" ;;
    n|N) printf -v "$var_name" "n" ;;
    *) echo "Введи y или n"; exit 1 ;;
  esac
}

echo "== Nginx + SSL + UFW + Docker React =="

prompt DOMAIN "Домен (например app.example.com)"
prompt EMAIL "Email для Let's Encrypt"
prompt APP_PORT "Порт React-приложения на хосте" "3000"
prompt_yes_no USE_WWW "Добавить www-домен?" "n"

if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || (( APP_PORT < 1 || APP_PORT > 65535 )); then
  echo "Некорректный порт: $APP_PORT"
  exit 1
fi

DOMAIN_WWW="www.${DOMAIN}"

echo
echo "Установка nginx + certbot..."
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx curl ufw

# =========================
# 🔥 UFW
# =========================
echo
echo "Проверка UFW..."

if need_cmd ufw; then
  UFW_STATUS="$(ufw status | head -n1 || true)"

  if echo "$UFW_STATUS" | grep -qi "active"; then
    echo "UFW активен — открываем порты 80 и 443"
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw reload
  else
    echo "UFW установлен, но не активен — пропускаем настройку"
  fi
else
  echo "UFW не установлен — пропускаем"
fi

# =========================
# Проверка приложения
# =========================
echo
echo "Проверка http://127.0.0.1:${APP_PORT} ..."
if ! curl -fsS "http://127.0.0.1:${APP_PORT}/" >/dev/null 2>&1; then
  echo "⚠️ Приложение не отвечает — проверь docker publish порта"
fi

# =========================
# NGINX
# =========================
NGINX_AVAIL="/etc/nginx/sites-available/${DOMAIN}.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}.conf"

cat >"$NGINX_AVAIL" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${DOMAIN}$( [[ "$USE_WWW" == "y" ]] && echo " ${DOMAIN_WWW}" );

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log  /var/log/nginx/${DOMAIN}.error.log;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 60s;
    }
}
EOF

ln -sf "$NGINX_AVAIL" "$NGINX_ENABLED"
rm -f /etc/nginx/sites-enabled/default || true

nginx -t
systemctl enable nginx
systemctl reload nginx

# =========================
# SSL
# =========================
echo
echo "Выпуск SSL сертификата..."
CERT_ARGS=(-n --nginx --agree-tos --email "$EMAIL" --redirect -d "$DOMAIN")
[[ "$USE_WWW" == "y" ]] && CERT_ARGS+=(-d "$DOMAIN_WWW")

certbot "${CERT_ARGS[@]}"

nginx -t
systemctl reload nginx

echo
echo "✅ Готово:"
echo "https://${DOMAIN}"
[[ "$USE_WWW" == "y" ]] && echo "https://${DOMAIN_WWW}"
