#!/bin/bash

#bash <(wget -qO- https://raw.githubusercontent.com/USER/REPO/main/install.sh) --port=443 --ip=203.0.113.10 --domain=google.com

#set -euo pipefail
#set -e

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

show_help() {
  cat <<'EOF'
Использование:
  ./script.sh [ПАРАМЕТРЫ]

Параметры:
  --port=PORT         Порт прокси. По умолчанию: 443
  --ip=IP             Внешний IP сервера. По умолчанию определяется автоматически
  --domain=DOMAIN     Домен для Fake-TLS. По умолчанию: github.com
  --help              Показать эту справку

Примеры:
  ./script.sh
  ./script.sh --port=443
  ./script.sh --ip=203.0.113.10 --domain=google.com
  ./script.sh --port=8443 --ip=203.0.113.10 --domain=google.com

Примечания:
  - Параметры можно передавать в любом порядке
  - Формат параметров: только --имя=значение
  - Если параметр передан несколько раз, будет использовано последнее значение
EOF
}

show_error() {
  echo "Ошибка: $1" >&2
  echo >&2
  show_help >&2
  exit 1
}

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y curl
fi

FAKE_DOMAIN="github.com"
#SERVER_IP="111.222.333.444"
SERVER_IP=$(curl -fsSL https://api.ipify.org || curl -fsSL https://ifconfig.me || curl -fsSL https://checkip.amazonaws.com)
PORT=443


#разбор аргументов
for arg in "$@"; do
  case "$arg" in
    --help)
      show_help
      exit 0
      ;;
    --port=*)
      PORT="${arg#*=}"
      ;;
    --ip=*)
      SERVER_IP="${arg#*=}"
      ;;
    --domain=*)
      FAKE_DOMAIN="${arg#*=}"
      ;;
    *)
      show_error "Неизвестный параметр: $arg"
      ;;
  esac
done

[[ -n "$PORT" ]] || show_error "Порт не может быть пустым"
[[ -n "$SERVER_IP" ]] || show_error "IP не может быть пустым"
[[ -n "$FAKE_DOMAIN" ]] || show_error "Домен не может быть пустым"

echo -e "\033[1;32m"
cat << "EOF"
• ▌ ▄ ·. ▄▄▄▄▄ ▄▄▄·▄▄▄        ▐▄• ▄  ▄· ▄▌
·██ ▐███▪•██  ▐█ ▄█▀▄ █·▪      █▌█▌▪▐█▪██▌
▐█ ▌▐▌▐█· ▐█.▪ ██▀·▐▀▀▄  ▄█▀▄  ·██· ▐█▌▐█▪
██ ██▌▐█▌ ▐█▌·▐█▪·•▐█•█▌▐█▌.▐▌▪▐█·█▌ ▐█▀·.
▀▀  █▪▀▀▀ ▀▀▀ .▀   .▀  ▀ ▀█▄▀▪•▀▀ ▀▀  ▀ • 
EOF
echo -e "\033[0m"

echo -e "\033[1;32mПротестировано на Debian 12 на чистом серваке\033[0m"
echo -e "\033[1;32mУстановлю докер и в нем mtprotoproxy из официального репозитория\033[0m"
echo -e "\033[1;32mУстановлю сразу все варианты прокси, выдам список в конце установки\033[0m"
echo -e "\033[1;31mЧтобы продолжить, нажмите Enter...\033[0m"
read && echo
#exit 1

wait_for_apt() {
  echo "Жду освобождения apt, он занят потому что сервер новый..."
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    sleep 3
  done
}

wait_for_apt
dpkg --configure -a

apt-get update && apt-get install -y curl xxd jq
apt-get install -y cron
systemctl enable --now cron
#curl -fsSL https://get.docker.com | sh
apt-get install -y docker.io
systemctl enable --now docker
docker --version
#apt install build-essential -y
#curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
#source $HOME/.cargo/env

#отрубаю ipv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

for iface in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
  echo 1 > "$iface"
done

CONF="/etc/sysctl.d/99-disable-ipv6.conf"

cat > "$CONF" <<EOF
# Disable IPv6 (managed by script)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl --system

#

echo "FAKE_DOMAIN=$FAKE_DOMAIN"
echo "SERVER_IP=$SERVER_IP"
echo "PORT=$PORT"

SECRET=$(head -c 16 /dev/urandom | xxd -ps -c 32 | tr -d '\n')
#SECRET=$(head -c 16 /dev/urandom | xxd -ps)
DD="dd$SECRET"
EE="ee${SECRET}$(echo -n "$FAKE_DOMAIN" | xxd -p)"
#EE="ee${SECRET}$(echo -n "$FAKE_DOMAIN" | xxd -p -c 256)"

echo "SECRET=$SECRET"
echo "DD=$DD"
echo "EE=$EE"


mkdir -p /etc/mtprotoproxy

cat > /etc/mtprotoproxy/config.py <<EOF
PORT = ${PORT}

# name -> secret (32 hex chars)
USERS = {
    "tg":  "${SECRET}",
    # "tg2": "0123456789abcdef0123456789abcdef",
}

MODES = {
    # Classic mode, easy to detect
    "classic": True,

    # Makes the proxy harder to detect
    # Can be incompatible with very old clients
    "secure": True,

    # Makes the proxy even more hard to detect
    # Can be incompatible with old clients
    "tls": True
}

# The domain for TLS mode, bad clients are proxied there
# Use random existing domain, proxy checks it on start
TLS_DOMAIN = "${FAKE_DOMAIN}"

# Tag for advertising, obtainable from @MTProxybot
# AD_TAG = "3c09c680b76ee91a4c25ad51f742267d"
EOF


#создаём временную директорию с рандомными цифрами
TEMP="/tmp/mtproxy_$(tr -dc '0-9' </dev/urandom | head -c 8)"
mkdir -p "$TEMP"


cat > "$TEMP/Dockerfile" <<'EOF'
FROM debian:12-slim

RUN apt-get update && apt-get install --no-install-recommends -y \
    python3 python3-uvloop python3-cryptography python3-socks \
    libcap2-bin ca-certificates git && \
    rm -rf /var/lib/apt/lists/*
#RUN setcap cap_net_bind_service=+ep /usr/bin/python3.12
RUN PYBIN="$(readlink -f "$(command -v python3)")" && \
    echo "$PYBIN" && \
    setcap cap_net_bind_service=+ep "$PYBIN"

#RUN useradd tgproxy -u 10000
RUN useradd -m -u 10000 tgproxy

WORKDIR /opt

RUN git clone https://github.com/alexbers/mtprotoproxy.git

RUN cp -r /opt/mtprotoproxy/mtprotoproxy.py /opt/mtprotoproxy/pyaes /home/tgproxy/ && \
    chown -R tgproxy:tgproxy /home/tgproxy

USER tgproxy
WORKDIR /home/tgproxy/

CMD ["python3", "mtprotoproxy.py"]
EOF


docker build -t mtprotoproxy "$TEMP"

docker rm -f mtprotoproxy 2>/dev/null || true

docker run -d \
  --name mtprotoproxy \
  -p 0.0.0.0:$PORT:$PORT \
  -v /etc/mtprotoproxy/config.py:/home/tgproxy/config.py:ro \
  --restart unless-stopped \
  mtprotoproxy

rm -rf "$TEMP"

echo "Ждем 10 сек"
sleep 10

docker inspect -f '{{.State.Status}}' mtprotoproxy 2>/dev/null | grep -q running \
  || show_error "Докер не запустился"


# base64 из EE
EE_B64=$(echo -n "$EE" | xxd -r -p | base64 | tr -d '\n')
EE_B64_URLSAFE=$(echo -n "$EE_B64" | tr '+/' '-_' | tr -d '=')

echo
echo "===== TG LINKS ====="
echo "Normal:"
echo "tg://proxy?server=$SERVER_IP&port=$PORT&secret=$SECRET"
echo
echo "Secure:"
echo "tg://proxy?server=$SERVER_IP&port=$PORT&secret=$DD"
echo
echo "Fake-TLS hex:"
echo "tg://proxy?server=$SERVER_IP&port=$PORT&secret=$EE"
echo
echo "Fake-TLS URL-safe base64:"
echo "tg://proxy?server=$SERVER_IP&port=$PORT&secret=$EE_B64_URLSAFE"
echo
echo "Fake-TLS base64:"
echo "tg://proxy?server=$SERVER_IP&port=$PORT&secret=$EE_B64"

echo
echo "===== HTTPS LINKS ====="
echo "Normal:"
echo "https://t.me/proxy?server=$SERVER_IP&port=$PORT&secret=$SECRET"
echo
echo "Secure:"
echo "https://t.me/proxy?server=$SERVER_IP&port=$PORT&secret=$DD"
echo
echo "Fake-TLS hex:"
echo "https://t.me/proxy?server=$SERVER_IP&port=$PORT&secret=$EE"
echo
echo "Fake-TLS URL-safe base64:"
echo "https://t.me/proxy?server=$SERVER_IP&port=$PORT&secret=$EE_B64_URLSAFE"
echo
echo "Fake-TLS base64:"
echo "https://t.me/proxy?server=$SERVER_IP&port=$PORT&secret=$EE_B64"









