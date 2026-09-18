#!/bin/bash 

set -e

# Colors
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RESET='\033[0m'
GREEN='\033[0;32m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Error: ${RESET} This script must be run with the root user！\n" && exit 1

get_script() {
	if [[ -f /usr/bin/xmp ]]; then
	  rm -rf /usr/bin/xmp 
	fi
	 
	curl -o /usr/bin/xmp -Ls https://raw.githubusercontent.com/XMPlusDev/XMPanel/scripts/xmp.sh
	chmod +x /usr/bin/xmp

	echo -e ""
	echo "XMPlus Panel Management usage method: "
	echo "------------------------------------------"
	echo "xmp                    - Show menu"
	echo "xmp start              - Start Panel"
	echo "xmp stop               - Stop Panel"
	echo "xmp restart            - Restart Panel"
	echo "xmp status             - View Panel status"
	echo "xmp enable             - Enable Panel auto-start"
	echo "xmp disable            - Disable Panel auto-start"
	echo "xmp log                - View Panel logs"
	echo "xmp update             - Update Panel"
	echo "xmp config             - Show configuration content"
	echo "xmp install            - Install Panel"
	echo "xmp uninstall          - Uninstall Panel"
	echo "--------------------------------------------"
	echo "xmp api                - View panel api docker logs"
	echo "xmp ui                 - View panel ui docker logs"
	echo "xmp redis              - View redis docker logs"
	echo "xmp mariadb            - View mariadb docker logs"
	echo "------------------------------------------"
}

echo -e "${GREEN}==> Updating packages and installing dependencies...${RESET}"
apt-get update -y 2>/dev/null
apt-get install -y wget bash zip curl unzip git ca-certificates openssl 2>/dev/null

echo -e "${GREEN}==> Checking for existing Docker installation...${RESET}"
if command -v docker &>/dev/null; then
    echo -e "${GREEN}==> Docker already installed: $(docker --version). Skipping...${RESET}"
else
    echo -e "${GREEN}==> Installing Docker...${RESET}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh

    echo -e "${GREEN}==> Enabling Docker on boot...${RESET}"
    systemctl enable docker
    systemctl start docker
fi

echo -e "${GREEN}==> Checking for existing Docker Compose installation...${RESET}"
if docker compose version &>/dev/null 2>&1 || command -v docker-compose &>/dev/null; then
    echo -e "${GREEN}==> Docker Compose already installed: $(docker compose version 2>/dev/null || docker-compose --version). Skipping...${RESET}"
else
    echo -e "${GREEN}==> Installing Docker Compose...${RESET}"
    curl -L "https://github.com/docker/compose/releases/download/v5.1.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

docker --version
docker compose version 2>/dev/null || docker-compose --version

echo -e "${GREEN}==> Checking for existing XMPlus-Panel installation...${RESET}"
if [ -d "/home/XMPanel" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Directory /home/XMPanel already exists.${RESET}"
    read -p "$(echo -e ${CYAN}Do you want to delete it and reinstall? [y/N]: ${RESET})" confirm
    echo ""
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}==> Stopping XMPanel service if running...${RESET}"
        systemctl stop XMP.service 2>/dev/null || true
        echo -e "${RED}==> Deleting /home/XMPanel...${RESET}"
        rm -rf /home/XMPanel
		
		if [ -e "/usr/bin/XMPanel" ] ; then
			rm -rf /usr/bin/XMPanel -f
		fi
		
		mkdir -p /home/XMPanel
		mkdir -p /home/XMPanel/vhost
    else
        echo -e "${RED}⏭️  Installation cancelled. Existing directory kept.${RESET}"
        exit 0
    fi
else
    mkdir -p /home/XMPanel
	mkdir -p /home/XMPanel/vhost
fi

echo -e "${GREEN}==> Configuring .env file...${RESET}"

# Generate all random keys
APP_KEY="base64:$(openssl rand -base64 32)"
DEBUG_PASSWORD=$(openssl rand -hex 12)
#DB_ROOT_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)
REVERB_APP_KEY=$(openssl rand -hex 12)
REVERB_APP_SECRET=$(openssl rand -hex 12)

# Prompt user for inputs with defaults
echo ""
echo -e "${GREEN}📝 Provide database and redis info (press Enter to use default):${RESET}"
echo ""

read -p "$(echo -e "${CYAN}Enter a database name${RESET}    [${YELLOW}(Default: xmplus)${RESET}]:        ")" DB_DATABASE
DB_DATABASE=${DB_DATABASE:-xmplus}

read -p "$(echo -e "${CYAN}Enter a database username${RESET}    [${YELLOW}(Default: xmplus)${RESET}]:        ")" DB_USERNAME
DB_USERNAME=${DB_USERNAME:-xmplus}

read -sp "$(echo -e "${CYAN}Enter a database password for the username${RESET}    [${YELLOW}(Default: auto-generate)${RESET}]:  ")" DB_PASSWORD
echo ""
DB_PASSWORD=${DB_PASSWORD:-$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)}

read -p "$(echo -e "${CYAN}Enter a database port${RESET}        [${YELLOW}(Default: 3306)${RESET}]:          ")" DB_PORT
DB_PORT=${DB_PORT:-3306}

read -sp "$(echo -e "${CYAN}Enter a redis password${RESET} [${YELLOW}(Default: auto-generate)${RESET}]:  ")" REDIS_PASSWORD
echo ""
REDIS_PASSWORD=${REDIS_PASSWORD:-$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)}

read -p "$(echo -e "${CYAN}Enter a redis port${RESET}     [${YELLOW}(Default: 6379)${RESET}]:          ")" REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}

REDIS_MAX_MEMORY="512mb"

read -p "$(echo -e "${CYAN}Enter a panel api host address to use without http:// or https:// ${RESET}       [${YELLOW}(Example: api.tld.com)${RESET}]:   ")" API_HOST
API_HOST=${API_HOST:-api.tld.com}

read -p "$(echo -e "${CYAN}Enter a panel ui address to use without http:// or https:// ${RESET}       [${YELLOW}(Example: www.tld.com)${RESET}]:   ")" UI_HOST
UI_HOST=${UI_HOST:-www.tld.com}

if [ ${UI_HOST} == "" ||  ${API_HOST} == "" ]; then
	echo -e "${RED}⏭️  Installation cancelled. Missing API oe UI address.${RESET}"
	exit 0;
fi

echo ""
echo -e "${GREEN}==> Writing .env file to /home/XMPanel/.env...${RESET}"
cat > /home/XMPanel/.env <<EOF
APP_NAME=XMPlus
APP_ENV=production
APP_PORT=9001
API_HOST=${API_HOST}
UI_HOST=${UI_HOST}
APP_KEY=${APP_KEY}
APP_URL="https://\${API_HOST}"
APP_LOCALE=en
DEBUG_PASSWORD=${DEBUG_PASSWORD}

# DB_CONNECTION=mysql (default) or sqlite. When sqlite, DB_DATABASE is a
# file path (e.g. storage/app/xmplus.sqlite)
# DB_HOST/DB_PORT/DB_USERNAME/DB_PASSWORD are ignored.
DB_CONNECTION=mysql
DB_HOST=xmplus_mariadb
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_DATABASE}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_PASSWORD}
DB_PREFIX=

#legacy database.(For migration only)
OLD_DB_HOST=xmplus_mariadb
OLD_DB_PORT=${DB_PORT}
OLD_DB_DATABASE=old_xmplus
OLD_DB_USERNAME=root
OLD_DB_PASSWORD=${DB_PASSWORD}

#Leave blank to disable a redis and use memory cache
REDIS_HOST=xmplus_redis
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=${REDIS_PORT}
REDIS_MAX_MEMORY=${REDIS_MAX_MEMORY}

REVERB_APP_ID=10000
REVERB_APP_KEY=${REVERB_APP_KEY}
REVERB_APP_SECRET=${REVERB_APP_SECRET}

REVERB_HOST=${API_HOST}
REVERB_PORT=443
REVERB_SCHEME=https

# Leave blank to disable a provider; the redirect URLs default to
# http://localhost:3000/auth/callback?type=<provider> if unset.
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_CLIENT_REDIRECT=

GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
GITHUB_CLIENT_REDIRECT=

XMPLUS_LOG_DIR=storage/app/logs
XMPLUS_I18N_DIR=storage/app/i18n
XMPLUS_LANG_DIR=storage/app/lang
XMPLUS_STORAGE_DIR=storage/app/public
XMPLUS_PUBLIC_STORAGE_DIR=storage/app/public
XMPLUS_CLIENTS_STORAGE_DIR=storage/app/public/clients
XMPLUS_PROFILES_DIR=storage/app/profiles
IP2LOCATION_DB_PATH=storage/app/ip2location/IP2LOCATION-LITE-DB5.IPV6.BIN
EOF

echo -e "${GREEN}==> Writing ecosystem.config.cjs to /home/XMPanel/ecosystem.config.cjs${RESET}"
cat > /home/XMPanel/ecosystem.config.cjs <<EOF
module.exports = {
  apps: [
    {
      name: 'XMPlus',
      script: '.output/server/index.mjs',
      instances: 'max',
      exec_mode: 'cluster',
      watch: false,
      env: {
        API_URL: 'https://${API_HOST}',
        PORT: 3000,
        DEBUG: false,
        SESSION_HTTPONLY: true,
        SESSION_SECURE: true,
        SESSION_SAME_SITE: 'lax'
      }
    }
  ]
}
EOF

echo -e "${GREEN}==> Writing docker-compose.yml to /home/XMPanel/docker-compose.yml${RESET}"
cat > /home/XMPanel/docker-compose.yml <<EOF
services:
  nginx-proxy:
    image: nginxproxy/nginx-proxy:latest
    container_name: nginx-proxy
    labels:
      - "com.github.nginx-proxy.nginx"
    ports:
      - "80:80"
      - "443:443"
    environment:
      - HTTPS_METHOD=redirect
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./certs:/etc/nginx/certs:ro
      - ./vhost:/etc/nginx/vhost.d:rw
      - html:/usr/share/nginx/html:rw 
    depends_on:
      xmplus_api:
        condition: service_healthy
    networks:
      - app_network
    restart: always

  xmplus_nginx-proxy-acme:
    image: nginxproxy/acme-companion:latest
    container_name: xmplus_nginx-proxy-acme
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/etc/nginx/certs:rw
      - ./vhost:/etc/nginx/vhost.d:rw
      - html:/usr/share/nginx/html:rw 
    environment:
      - DEFAULT_EMAIL=admin@xmplus.dev
      - NGINX_PROXY_CONTAINER=nginx-proxy
    networks:
      - app_network
    depends_on:
      - nginx-proxy
    restart: always

  xmplus_api:
    container_name: xmplus_api
    image: xmplusdev/xmplus-go:latest
    expose:
      - "9001"
    env_file: .env
    environment:
      - VIRTUAL_HOST=\${API_HOST}
      - LETSENCRYPT_HOST=\${API_HOST}
    networks:
      - app_network
    volumes:
      - ./storage:/app/storage
    depends_on:
      xmplus_mariadb:
        condition: service_healthy
      xmplus_redis:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://127.0.0.1:9001/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  xmplus_ui:
    container_name: xmplus_ui
    image: xmplusdev/xmplus-ui:latest
    expose:
      - "3000"
    environment:
      - VIRTUAL_HOST=\${UI_HOST}
      - LETSENCRYPT_HOST=\${UI_HOST}
    volumes:
      - ./ecosystem.config.cjs:/app/ecosystem.config.cjs
    networks:
      - app_network
    depends_on:
      xmplus_api:
        condition: service_healthy
    restart: unless-stopped

  xmplus_mariadb:
    container_name: xmplus_mariadb
    image: mariadb:12.2
    environment:
      MYSQL_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: \${DB_DATABASE}
      MYSQL_USER: \${DB_USERNAME}
      MYSQL_PASSWORD: \${DB_PASSWORD}
      MYSQL_TCP_PORT: \${DB_PORT:-3306}
    networks:
      - app_network
    volumes:
      - mariadb_data:/var/lib/mysql
    restart: unless-stopped
    ports:
      - "127.0.0.1:\${DB_PORT:-3306}:\${DB_PORT:-3306}"
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 15s
      timeout: 15s
      retries: 10
      start_period: 30s

  xmplus_phpmyadmin:
    container_name: xmplus_phpmyadmin
    image: phpmyadmin:latest
    environment:
      PMA_HOST: xmplus_mariadb
      PMA_PORT: \${DB_PORT:-3306}
      MYSQL_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
      PMA_ARBITRARY: 0
      UPLOAD_LIMIT: 128M
    ports:
      - '8085:80'
    networks:
      - app_network
    depends_on:
      xmplus_mariadb:
        condition: service_healthy
    restart: unless-stopped

  xmplus_redis:
    container_name: xmplus_redis
    image: redis:8.6-alpine
    command: >
      redis-server 
      --requirepass \${REDIS_PASSWORD} 
      --port ${REDIS_PORT:-6379} 
      --maxmemory \${REDIS_MAX_MEMORY:-512mb} 
      --maxmemory-policy allkeys-lru 
      --appendonly yes 
      --appendfsync everysec 
      --save 60 1 
      --save 300 100 
      --bind 0.0.0.0 
      --protected-mode no
    networks:
      - app_network
    ports:
      - "\${REDIS_PORT:-6379}:\${REDIS_PORT:-6379}"
    volumes:
      - redis_data:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -p \${REDIS_PORT:-6379} -a \${REDIS_PASSWORD} ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

volumes:
  html:
  mariadb_data:
  redis_data:

networks:
  app_network:
    driver: bridge
EOF


echo -e "${GREEN}==> Writing ${API_HOST}_location to /home/XMPanel/vhost${RESET}"
cat > /home/XMPanel/vhost/${API_HOST}_location <<EOF
client_max_body_size 25m; 

#add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
#add_header Content-Security-Policy "default-src 'self'; script-src 'self' https: 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline' https:; img-src 'self' data: https:; font-src 'self' https: data:; connect-src 'self' https: wss:; frame-src 'self' https://challenges.cloudflare.com https://js.stripe.com https://hooks.stripe.com https://www.paypal.com https://www.sandbox.paypal.com https://openapi.alipay.com/gateway.do https://www.coinpayments.net https://api-m.paypal.com https://api-m.sandbox.paypal.com https://api.plisio.net/api/v1 https://api.zarinpal.com/pg/v4/payment https://embed.tawk.to; object-src 'none'; base-uri 'self'; frame-ancestors 'self'" always;

location /api/health {
    access_log off;
    proxy_pass http://xmplus_api:9001;    
    proxy_set_header Host \$host;
}

location /api/reverb/ {    
    access_log off;
    proxy_pass http://xmplus_api:9001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;

    proxy_cache_bypass \$http_upgrade;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    proxy_connect_timeout 5s;

    proxy_buffering off;
    proxy_request_buffering off;
}

location /app {
    access_log off;
    proxy_pass http://xmplus_api:9001;
    proxy_http_version 1.1;    
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;

    proxy_cache_bypass \$http_upgrade;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    proxy_connect_timeout 5s;

    proxy_buffering off;
    proxy_request_buffering off;
}

location ~* ^/api/.*\.(?:jpg|jpeg|gif|png|ico|svg|webp|woff|woff2|ttf|eot|otf)$ {
    access_log off;
    proxy_pass http://xmplus_api:9001;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header Connection "";

    expires 1y;
    access_log off;
    add_header Cache-Control "public, immutable";
}

location / {
    access_log off;
    proxy_pass http://xmplus_api:9001;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;

    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_request_buffering off;

    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    proxy_buffer_size 16k;
    proxy_buffers 4 16k;
    proxy_busy_buffers_size 32k;
}

location ~ /\.ht {
    deny all;
    return 404;
}
EOF


echo -e "${GREEN}==> Writing ${UI_HOST}_location to /home/XMPanel/vhost${RESET}"
cat > /home/XMPanel/vhost/${UI_HOST}_location <<EOF
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' https: 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline' https:; img-src 'self' data: https:; font-src 'self' https: data:; connect-src 'self' https: wss:; frame-src 'self' https://challenges.cloudflare.com https://js.stripe.com https://hooks.stripe.com https://www.paypal.com https://www.sandbox.paypal.com https://openapi.alipay.com/gateway.do https://www.coinpayments.net https://api-m.paypal.com https://api-m.sandbox.paypal.com https://api.plisio.net/api/v1 https://api.zarinpal.com/pg/v4/payment https://embed.tawk.to; object-src 'none'; base-uri 'self'; frame-ancestors 'self'" always;

location / {
    access_log off;
    proxy_pass http://xmplus_ui:3000;
    proxy_http_version 1.1;
        
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
        
    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_request_buffering off;

    proxy_buffer_size 16k;
    proxy_buffers 4 16k;
    proxy_busy_buffers_size 32k;
}
EOF

echo ""
echo "   ┌──────────────────────────────────────────────────────┐"
echo "   │              Configuration Summary                   │"
echo "   ├──────────────────────────────────────────────────────┤"
printf  "   │  DB_DATABASE:      %-34s│\n" "${DB_DATABASE}"
printf  "   │  DB_USERNAME:      %-34s│\n" "${DB_USERNAME}"
printf  "   │  DB_PASSWORD:      %-34s│\n" "${DB_PASSWORD}"
printf  "   │  DB_ROOT_PASSWORD: %-34s│\n" "${DB_ROOT_PASSWORD}"
printf  "   │  DB_PORT:          %-34s│\n" "${DB_PORT}"
printf  "   │  REDIS_PASSWORD:   %-34s│\n" "${REDIS_PASSWORD}"
printf  "   │  REDIS_PORT:       %-34s│\n" "${REDIS_PORT}"
printf  "   │  API_HOST:         %-34s│\n" "${API_HOST}"
printf  "   │  UI_HOST:          %-34s│\n" "${UI_HOST}"
echo "   └──────────────────────────────────────────────────────┘"
echo ""

if systemctl is-active --quiet XMP.service 2>/dev/null; then
    systemctl stop XMP.service
fi
if systemctl is-enabled --quiet XMP.service 2>/dev/null; then
    systemctl disable XMP.service
fi
if [ -f "/etc/systemd/system/XMP.service" ]; then
    rm -f /etc/systemd/system/XMP.service
fi
systemctl daemon-reload

cat > /etc/systemd/system/XMP.service <<EOF
[Unit]
Description=XMP
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/XMPanel
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}==> Enabling and starting XMPanel service...${RESET}"
systemctl daemon-reload
systemctl enable XMP.service
systemctl start XMP.service

echo -e "${GREEN}==> Waiting for API service to become healthy...${RESET}"
MAX_WAIT=120
WAITED=0
INTERVAL=5

get_script

cd /home/XMPanel

while true; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' xmplus_api 2>/dev/null || echo "not_found")

    if [ "$STATUS" = "healthy" ]; then
        echo -e "${GREEN}✅ API service is healthy.${RESET}"
        break
    elif [ "$STATUS" = "unhealthy" ]; then
        echo -e "${RED}❌ API service is unhealthy. Aborting migration.${RESET}"
        docker logs xmplus_api --tail 50
        exit 1
    fi

    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo -e "${RED}❌ Timed out waiting for API service after ${MAX_WAIT}s. Aborting.${RESET}"
        docker logs xmplus_api --tail 50
        exit 1
    fi

    echo -e "${YELLOW}⏳ API status: ${STATUS}. Waiting... (${WAITED}s/${MAX_WAIT}s)${RESET}"
    sleep $INTERVAL
    WAITED=$((WAITED + INTERVAL))
done

echo ""
echo -e "${GREEN}✅ Done! XMPlus Panel is fully installed and running.{RESET}"
echo -e "${CYAN}Browse via:   http://${UI_HOST}"
echo ""
echo "Use 'systemctl status xmp' to check the service status."
echo "Use 'systemctl stop xmp' to stop the service."
echo "Use 'systemctl start xmp' to start the service."
echo ""
