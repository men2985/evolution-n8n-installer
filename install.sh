#!/bin/bash
set -e

# Banner de inicio
echo "=============================================================="
echo "  INSTALACIÓN AUTOMATIZADA DE N8N, EVOLUTION API Y REDIS"
echo "=============================================================="
echo ""
echo "Este script instalará y configurará:"
echo "  • n8n - Plataforma de automatización de flujos de trabajo"
echo "  • Evolution API - API para integración con WhatsApp"
echo "  • Redis - Base de datos en memoria para caché"
echo ""
echo "Requisitos:"
echo "  • Ubuntu/Debian"
echo "  • Acceso root"
echo "  • Dominio con DNS configurado apuntando a este servidor"
echo ""

# Verificar que se ejecuta como root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root o con sudo"
    exit 1
fi

# Verificar sistema operativo
if ! grep -qiE 'debian|ubuntu' /etc/os-release; then
    echo "Este script está diseñado para sistemas Debian/Ubuntu"
    echo "Se detectó: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"
    echo "¿Desea continuar de todos modos? (s/n)"
    read continue_anyway
    if [[ "$continue_anyway" != "s" ]]; then
        echo "Instalación cancelada"
        exit 1
    fi
fi

# Solicitar información al usuario
read -p "Ingrese su dominio principal (ejemplo.com): " DOMAIN
read -p "Ingrese su correo electrónico para SSL y notificaciones: " EMAIL
echo -n "Ingrese su contraseña de aplicación de Google (para envío de correos): "
stty -echo
read GMAIL_APP_PASSWORD
stty echo
echo ""

# Validar formato del dominio (básico)
if ! echo "$DOMAIN" | grep -qP '(?=^.{4,253}$)(^(?:[a-zA-Z0-9](?:(?:[a-zA-Z0-9\-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$)'; then
    echo "El formato del dominio ingresado no parece ser válido"
    echo "Por favor ingrese un dominio válido (ej: ejemplo.com)"
    exit 1
fi

# Validar formato del email (básico)
if ! echo "$EMAIL" | grep -qP '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    echo "El formato del correo electrónico no es válido"
    exit 1
fi

# Definir subdominios y directorios
N8N_SUBDOMAIN="n8n.${DOMAIN}"
EVOLUTION_SUBDOMAIN="evoapi.${DOMAIN}"
CHATWOOT_SUBDOMAIN="chat.${DOMAIN}"
N8N_DIR="/home/docker/n8n"
EVOLUTION_DIR="/home/docker/evolution"
CHATWOOT_DIR="/home/docker/chatwoot"
REDIS_DIR="/opt/redis"
BACKUP_DIR="/opt/backups"
LOG_DIR="/var/log/autoinstall"

# Crear directorios para las aplicaciones y respaldos
mkdir -p $N8N_DIR/db $N8N_DIR/data $N8N_DIR/local-files \
         $EVOLUTION_DIR/evolution_instances $EVOLUTION_DIR/evolution_redis \
         $EVOLUTION_DIR/evolution_postgres_data $EVOLUTION_DIR/rabbitmq_data \
         $CHATWOOT_DIR $REDIS_DIR $BACKUP_DIR $LOG_DIR

# Generar contraseñas y claves seguras
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-20)
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
REDIS_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-20)
CHATWOOT_SECRET_KEY_BASE=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
CHATWOOT_POSTGRES_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-20)

# Guardar credenciales en un archivo seguro
CREDENTIALS_FILE="$BACKUP_DIR/credentials.txt"
touch $CREDENTIALS_FILE
chmod 600 $CREDENTIALS_FILE

cat <<EOF > $CREDENTIALS_FILE
# Credenciales generadas el $(date)
# IMPORTANTE: Guarde este archivo en un lugar seguro

DOMINIO_PRINCIPAL=$DOMAIN
EMAIL=$EMAIL

# n8n
N8N_URL=https://$N8N_SUBDOMAIN
N8N_DB_USER=n8n_user
N8N_DB_PASSWORD=$DB_PASSWORD
N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY

# Evolution API
EVOLUTION_URL=https://$EVOLUTION_SUBDOMAIN
EVOLUTION_DB_USER=evolution_user
EVOLUTION_DB_PASSWORD=$DB_PASSWORD
EVOLUTION_API_KEY=$ENCRYPTION_KEY

# Redis
REDIS_PASSWORD=$REDIS_PASSWORD

# RabbitMQ
RABBITMQ_USER=evo-rabbit
RABBITMQ_PASSWORD=$REDIS_PASSWORD

# Chatwoot
CHATWOOT_URL=https://$CHATWOOT_SUBDOMAIN
CHATWOOT_SECRET_KEY_BASE=$CHATWOOT_SECRET_KEY_BASE
CHATWOOT_DB_PASSWORD=$CHATWOOT_POSTGRES_PASSWORD

# Directorios
N8N_DIR=$N8N_DIR
EVOLUTION_DIR=$EVOLUTION_DIR
CHATWOOT_DIR=$CHATWOOT_DIR
BACKUP_DIR=$BACKUP_DIR
EOF

# Función para registrar progreso
log_progress() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_DIR/install.log"
    echo "$1"
}

log_progress "Iniciando instalación..."
log_progress "Dominio principal: $DOMAIN"
log_progress "Subdominio n8n: $N8N_SUBDOMAIN"
log_progress "Subdominio Evolution API: $EVOLUTION_SUBDOMAIN"

# Instalar dependencias
log_progress "Actualizando e instalando dependencias..."
apt update -y
apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx \
    curl wget git ufw fail2ban htop jq net-tools rkhunter chkrootkit -q

# Iniciar y habilitar Docker
log_progress "Configurando Docker..."
systemctl start docker
systemctl enable docker

# Configurar rkhunter
log_progress "Configurando rkhunter..."
sed -i 's/UPDATE_MIRRORS=0/UPDATE_MIRRORS=1/' /etc/rkhunter.conf
sed -i 's/MIRRORS_MODE=1/MIRRORS_MODE=0/' /etc/rkhunter.conf
sed -i 's/WEB_CMD=".*"/WEB_CMD=""/' /etc/rkhunter.conf
# Agregar rutas de Docker a whitelist para evitar falsos positivos
echo "ALLOWHIDDENDIR=/var/lib/docker" >> /etc/rkhunter.conf
echo "ALLOWHIDDENDIR=/var/lib/docker/containers" >> /etc/rkhunter.conf
echo "ALLOWHIDDENDIR=/var/lib/docker/overlay2" >> /etc/rkhunter.conf
# Actualizar rkhunter
log_progress "Actualizando rkhunter..."
rkhunter --update --skip-keypress

# Configurar firewall
log_progress "Configurando firewall..."
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# Crear redes de Docker compartidas
log_progress "Creando redes Docker..."
docker network create frontend --driver bridge 2>/dev/null || true
docker network create backend --driver bridge 2>/dev/null || true

# Configurar n8n
log_progress "Configurando n8n..."

# Crear archivo .env para n8n
cat <<EOF > $N8N_DIR/.env
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=n8n
POSTGRES_NON_ROOT_USER=n8n_user
POSTGRES_NON_ROOT_PASSWORD=${DB_PASSWORD}
EOF

# Crear archivo docker-compose.yml para n8n
cat <<EOF > $N8N_DIR/docker-compose.yml
version: '3.8'
volumes:
  db_storage:
  n8n_storage:
services:
  'n8n-db':
    container_name: app_n8n_db
    restart: always
    user: root
    environment:
      - POSTGRESQL_USERNAME=n8n_user
      - POSTGRESQL_DATABASE=n8n
      - POSTGRESQL_PASSWORD=${DB_PASSWORD}
    networks:
      - backend
    volumes:
      - "${N8N_DIR}/db:/bitnami/postgresql"
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "n8n_user", "-d", "n8n"]
      interval: 30s
      timeout: 10s
      retries: 3
  n8n:
    container_name: app_n8n_service
    image: docker.n8n.io/n8nio/n8n
    restart: always
    user: root
    environment:
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=app_n8n_db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n_user
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_PROTOCOL=https
      - N8N_HOST=${N8N_SUBDOMAIN}
      - WEBHOOK_URL=https://${N8N_SUBDOMAIN}
      - NODE_ENV=production
      - GENERIC_TIMEZONE=America/Bogota
    ports:
      - "127.0.0.1:5678:5678"
    links:
      - n8n-db
    networks:
      - frontend
      - backend
    volumes:
      - ${N8N_DIR}/data:/home/node/.n8n
      - ${N8N_DIR}/local-files:/files
    depends_on:
      - 'n8n-db'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
networks:
    frontend:
      driver: bridge
      external: true
    backend:
      driver: bridge
      external: true
EOF

# Configurar Evolution API
log_progress "Configurando Evolution API..."

# Crear archivo .env para Evolution API
cat <<EOF > $EVOLUTION_DIR/.env
SERVER_TYPE=http
SERVER_PORT=8080
# Server URL - Set your application url
SERVER_URL=https://${EVOLUTION_SUBDOMAIN}

SENTRY_DSN=

# Cors - * for all or set separate by commas -  ex.: 'yourdomain1.com, yourdomain2.com'
CORS_ORIGIN=*
CORS_METHODS=GET,POST,PUT,DELETE
CORS_CREDENTIALS=true

# Determine the logs to be displayed
LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE,DARK,WEBHOOKS,WEBSOCKET
LOG_COLOR=true
# Log Baileys - "fatal" | "error" | "warn" | "info" | "debug" | "trace"
LOG_BAILEYS=error

# Set the maximum number of listeners that can be registered for an event
EVENT_EMITTER_MAX_LISTENERS=50

# Determine how long the instance should be deleted from memory in case of no connection.
# Default time: 5 minutes
# If you don't even want an expiration, enter the value false
DEL_INSTANCE=false

# Provider: postgresql | mysql
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://evolution_user:${DB_PASSWORD}@app_evo_postgres_service:5432/evolution2?schema=public
# Client name for the database connection
# It is used to separate an API installation from another that uses the same database.
DATABASE_CONNECTION_CLIENT_NAME=evolution_client

# Choose the data you want to save in the application's database
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=true
DATABASE_SAVE_MESSAGE_UPDATE=true
DATABASE_SAVE_DATA_CONTACTS=true
DATABASE_SAVE_DATA_CHATS=true
DATABASE_SAVE_DATA_LABELS=true
DATABASE_SAVE_DATA_HISTORIC=true
DATABASE_SAVE_IS_ON_WHATSAPP=true
DATABASE_SAVE_IS_ON_WHATSAPP_DAYS=7
DATABASE_DELETE_MESSAGE=true

# RabbitMQ - Environment variables
RABBITMQ_ENABLED=true
RABBITMQ_URI=amqp://evo-rabbit:${REDIS_PASSWORD}@app_evo_rabbitmq_service:5672/default
RABBITMQ_EXCHANGE_NAME=evolution
RABBITMQ_ERLANG_COOKIE=${REDIS_PASSWORD}
RABBITMQ_DEFAULT_VHOST=default
RABBITMQ_DEFAULT_USER=evo-rabbit
RABBITMQ_DEFAULT_PASS=${REDIS_PASSWORD}
# Global events - By enabling this variable, events from all instances are sent in the same event queue.
RABBITMQ_GLOBAL_ENABLED=false
# Choose the events you want to send to RabbitMQ
RABBITMQ_EVENTS_APPLICATION_STARTUP=false
RABBITMQ_EVENTS_INSTANCE_CREATE=false
RABBITMQ_EVENTS_INSTANCE_DELETE=false
RABBITMQ_EVENTS_QRCODE_UPDATED=false
RABBITMQ_EVENTS_MESSAGES_SET=false
RABBITMQ_EVENTS_MESSAGES_UPSERT=false
RABBITMQ_EVENTS_MESSAGES_EDITED=false
RABBITMQ_EVENTS_MESSAGES_UPDATE=false
RABBITMQ_EVENTS_MESSAGES_DELETE=false
RABBITMQ_EVENTS_SEND_MESSAGE=false
RABBITMQ_EVENTS_CONTACTS_SET=false
RABBITMQ_EVENTS_CONTACTS_UPSERT=false
RABBITMQ_EVENTS_CONTACTS_UPDATE=false
RABBITMQ_EVENTS_PRESENCE_UPDATE=false
RABBITMQ_EVENTS_CHATS_SET=false
RABBITMQ_EVENTS_CHATS_UPSERT=false
RABBITMQ_EVENTS_CHATS_UPDATE=false
RABBITMQ_EVENTS_CHATS_DELETE=false
RABBITMQ_EVENTS_GROUPS_UPSERT=false
RABBITMQ_EVENTS_GROUP_UPDATE=false
RABBITMQ_EVENTS_GROUP_PARTICIPANTS_UPDATE=false
RABBITMQ_EVENTS_CONNECTION_UPDATE=false
RABBITMQ_EVENTS_REMOVE_INSTANCE=false
RABBITMQ_EVENTS_LOGOUT_INSTANCE=false
RABBITMQ_EVENTS_CALL=false
RABBITMQ_EVENTS_TYPEBOT_START=false
RABBITMQ_EVENTS_TYPEBOT_CHANGE_STATUS=false

# SQS - Environment variables
SQS_ENABLED=false
SQS_ACCESS_KEY_ID=
SQS_SECRET_ACCESS_KEY=
SQS_ACCOUNT_ID=
SQS_REGION=

# Websocket - Environment variables
WEBSOCKET_ENABLED=false
WEBSOCKET_GLOBAL_EVENTS=false

# Pusher - Environment variables
PUSHER_ENABLED=false
PUSHER_GLOBAL_ENABLED=false
PUSHER_GLOBAL_APP_ID=
PUSHER_GLOBAL_KEY=
PUSHER_GLOBAL_SECRET=
PUSHER_GLOBAL_CLUSTER=
PUSHER_GLOBAL_USE_TLS=true
# Choose the events you want to send to Pusher
PUSHER_EVENTS_APPLICATION_STARTUP=true
PUSHER_EVENTS_QRCODE_UPDATED=true
PUSHER_EVENTS_MESSAGES_SET=true
PUSHER_EVENTS_MESSAGES_UPSERT=true
PUSHER_EVENTS_MESSAGES_EDITED=true
PUSHER_EVENTS_MESSAGES_UPDATE=true
PUSHER_EVENTS_MESSAGES_DELETE=true
PUSHER_EVENTS_SEND_MESSAGE=true
PUSHER_EVENTS_CONTACTS_SET=true
PUSHER_EVENTS_CONTACTS_UPSERT=true
PUSHER_EVENTS_CONTACTS_UPDATE=true
PUSHER_EVENTS_PRESENCE_UPDATE=true
PUSHER_EVENTS_CHATS_SET=true
PUSHER_EVENTS_CHATS_UPSERT=true
PUSHER_EVENTS_CHATS_UPDATE=true
PUSHER_EVENTS_CHATS_DELETE=true
PUSHER_EVENTS_GROUPS_UPSERT=true
PUSHER_EVENTS_GROUPS_UPDATE=true
PUSHER_EVENTS_GROUP_PARTICIPANTS_UPDATE=true
PUSHER_EVENTS_CONNECTION_UPDATE=true
PUSHER_EVENTS_LABELS_EDIT=true
PUSHER_EVENTS_LABELS_ASSOCIATION=true
PUSHER_EVENTS_CALL=true
PUSHER_EVENTS_TYPEBOT_START=false
PUSHER_EVENTS_TYPEBOT_CHANGE_STATUS=false

# WhatsApp Business API - Environment variables
# Token used to validate the webhook on the Facebook APP
WA_BUSINESS_TOKEN_WEBHOOK=evolution
WA_BUSINESS_URL=https://graph.facebook.com
WA_BUSINESS_VERSION=v20.0
WA_BUSINESS_LANGUAGE=en_US

# Global Webhook Settings
# Each instance's Webhook URL and events will be requested at the time it is created
WEBHOOK_GLOBAL_ENABLED=false
# Define a global webhook that will listen for enabled events from all instances
WEBHOOK_GLOBAL_URL=''
# With this option activated, you work with a url per webhook event, respecting the global url and the name of each event
WEBHOOK_GLOBAL_WEBHOOK_BY_EVENTS=false
# Set the events you want to hear
WEBHOOK_EVENTS_APPLICATION_STARTUP=false
WEBHOOK_EVENTS_QRCODE_UPDATED=true
WEBHOOK_EVENTS_MESSAGES_SET=true
WEBHOOK_EVENTS_MESSAGES_UPSERT=true
WEBHOOK_EVENTS_MESSAGES_EDITED=true
WEBHOOK_EVENTS_MESSAGES_UPDATE=true
WEBHOOK_EVENTS_MESSAGES_DELETE=true
WEBHOOK_EVENTS_SEND_MESSAGE=true
WEBHOOK_EVENTS_CONTACTS_SET=true
WEBHOOK_EVENTS_CONTACTS_UPSERT=true
WEBHOOK_EVENTS_CONTACTS_UPDATE=true
WEBHOOK_EVENTS_PRESENCE_UPDATE=true
WEBHOOK_EVENTS_CHATS_SET=true
WEBHOOK_EVENTS_CHATS_UPSERT=true
WEBHOOK_EVENTS_CHATS_UPDATE=true
WEBHOOK_EVENTS_CHATS_DELETE=true
WEBHOOK_EVENTS_GROUPS_UPSERT=true
WEBHOOK_EVENTS_GROUPS_UPDATE=true
WEBHOOK_EVENTS_GROUP_PARTICIPANTS_UPDATE=true
WEBHOOK_EVENTS_CONNECTION_UPDATE=true
WEBHOOK_EVENTS_REMOVE_INSTANCE=false
WEBHOOK_EVENTS_LOGOUT_INSTANCE=false
WEBHOOK_EVENTS_LABELS_EDIT=true
WEBHOOK_EVENTS_LABELS_ASSOCIATION=true
WEBHOOK_EVENTS_CALL=true
# This events is used with Typebot
WEBHOOK_EVENTS_TYPEBOT_START=false
WEBHOOK_EVENTS_TYPEBOT_CHANGE_STATUS=false
# This event is used to send errors
WEBHOOK_EVENTS_ERRORS=false
WEBHOOK_EVENTS_ERRORS_WEBHOOK=

# Name that will be displayed on smartphone connection
CONFIG_SESSION_PHONE_CLIENT=Evolution API
# Browser Name = Chrome | Firefox | Edge | Opera | Safari
CONFIG_SESSION_PHONE_NAME=Chrome

# Whatsapp Web version for baileys channel
# https://web.whatsapp.com/check-update?version=0&platform=web
CONFIG_SESSION_PHONE_VERSION=2.3000.1015901307

# Set qrcode display limit
QRCODE_LIMIT=30
# Color of the QRCode on base64
QRCODE_COLOR='#175197'

# Typebot - Environment variables
TYPEBOT_ENABLED=true
# old | latest
TYPEBOT_API_VERSION=latest

# Chatwoot - Environment variables
CHATWOOT_ENABLED=false
# If you leave this option as false, when deleting the message for everyone on WhatsApp, it will not be deleted on Chatwoot.
CHATWOOT_MESSAGE_READ=true
# If you leave this option as true, when sending a message in Chatwoot, the client's last message will be marked as read on WhatsApp.
CHATWOOT_MESSAGE_DELETE=true
# If you leave this option as true, a contact will be created on Chatwoot to provide the QR Code and update messages about the instance.
CHATWOOT_BOT_CONTACT=true
# This db connection is used to import messages from whatsapp to chatwoot database
CHATWOOT_IMPORT_DATABASE_CONNECTION_URI='postgresql://postgres-user:password@localhost:5432/chatwoot?sslmode=disable'
CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true

# OpenAI - Environment variables
OPENAI_ENABLED=false

# Dify - Environment variables
DIFY_ENABLED=false

# Cache - Environment variables
# Redis Cache enabled
CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://app_evo_redis_service:6379/2
CACHE_REDIS_TTL=604800
# Prefix serves to differentiate data from one installation to another that are using the same redis
CACHE_REDIS_PREFIX_KEY=evolution
# Enabling this variable will save the connection information in Redis and not in the database.
CACHE_REDIS_SAVE_INSTANCES=false
# Local Cache enabled
CACHE_LOCAL_ENABLED=false

# Amazon S3 - Environment variables
S3_ENABLED=false
S3_ACCESS_KEY=
S3_SECRET_KEY=
S3_BUCKET=evolution
S3_PORT=443
S3_ENDPOINT=s3.domain.com
S3_REGION=eu-west-3
S3_USE_SSL=true

# Define a global apikey to access all instances.
# OBS: This key must be inserted in the request header to create an instance.
AUTHENTICATION_API_KEY=${ENCRYPTION_KEY}

# If you leave this option as true, the instances will be exposed in the fetch instances endpoint.
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
LANGUAGE=es
EOF

# Crear archivo docker-compose.yml para Evolution API
cat <<EOF > $EVOLUTION_DIR/docker-compose.yml
version: '3.9'

services:
  evolution-api:
    container_name: app_evo_api_service
    image: atendai/evolution-api:latest
    restart: always
    depends_on:
      - redis
      - postgres
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - ./evolution_instances:/evolution/instances
    networks:
      - frontend
      - backend
    env_file:
      - .env
    expose:
      - 8080
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis:
    container_name: app_evo_redis_service
    image: redis:latest
    networks:
      - backend
    command: >
      redis-server --port 6379 --appendonly yes
    volumes:
      - ./evolution_redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    container_name: app_evo_postgres_service
    image: postgres:15
    networks:
      - backend
    restart: always
    environment:
      - POSTGRES_DB=evolution2
      - POSTGRES_USER=evolution_user
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - ./evolution_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U evolution_user -d evolution2"]
      interval: 30s
      timeout: 10s
      retries: 3
 
  rabbitmq:
    container_name: app_evo_rabbitmq_service
    image: rabbitmq:management
    entrypoint: docker-entrypoint.sh
    command: rabbitmq-server
    ports:
      - "127.0.0.1:5672:5672"
      - "127.0.0.1:15672:15672"
    hostname: rabbitmq
    volumes:
       - ./rabbitmq_data:/var/lib/rabbitmq/
    environment:
      - RABBITMQ_ERLANG_COOKIE=${REDIS_PASSWORD}
      - RABBITMQ_DEFAULT_VHOST=default
      - RABBITMQ_DEFAULT_USER=evo-rabbit
      - RABBITMQ_DEFAULT_PASS=${REDIS_PASSWORD}
    networks:
      - frontend
      - backend
    healthcheck:
      test: ["CMD", "rabbitmqctl", "status"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  evolution_instances:
  evolution_redis:
  evolution_postgres_data:
  rabbitmq_data:
    name: rabbitmq_data

networks:
  frontend:
    external: true
  backend:
    external: true
EOF

# Configurar escaneos automáticos de seguridad
log_progress "Configurando escaneos automáticos de seguridad..."
cat <<EOF > $BACKUP_DIR/security_scan.sh
#!/bin/bash
# Script de escaneo automático de seguridad

DATE=\$(date +%Y-%m-%d)
LOG_DIR=$LOG_DIR
mkdir -p \$LOG_DIR/security

echo "=== Iniciando escaneo de seguridad - \$DATE ===" > \$LOG_DIR/security/scan_\$DATE.log
echo "" >> \$LOG_DIR/security/scan_\$DATE.log

echo "*** Escaneando con rkhunter ***" >> \$LOG_DIR/security/scan_\$DATE.log
rkhunter --update --skip-keypress >> \$LOG_DIR/security/scan_\$DATE.log 2>&1
rkhunter --check --skip-keypress >> \$LOG_DIR/security/scan_\$DATE.log 2>&1

echo "" >> \$LOG_DIR/security/scan_\$DATE.log
echo "*** Escaneando con chkrootkit ***" >> \$LOG_DIR/security/scan_\$DATE.log
chkrootkit >> \$LOG_DIR/security/scan_\$DATE.log 2>&1

echo "" >> \$LOG_DIR/security/scan_\$DATE.log
echo "=== Escaneo de seguridad completado - \$DATE ===" >> \$LOG_DIR/security/scan_\$DATE.log

# Enviar alertas si se encuentran problemas
if grep -iE 'warning|infected|suspicious|detection' \$LOG_DIR/security/scan_\$DATE.log; then
  echo "Se encontraron posibles problemas de seguridad. Revise el log: \$LOG_DIR/security/scan_\$DATE.log"
fi

# Limpiar logs antiguos (mantener los últimos 30 días)
find \$LOG_DIR/security -type f -name "scan_*.log" -mtime +30 -delete 2>/dev/null || true
EOF

chmod +x $BACKUP_DIR/security_scan.sh

# Agregar tarea cron para escaneo de seguridad semanal (cada domingo a las 3:00 AM)
(crontab -l 2>/dev/null; echo "0 3 * * 0 $BACKUP_DIR/security_scan.sh") | crontab -

# Crear script de respaldo automático
log_progress "Configurando script de respaldo automático..."
cat <<EOF > $BACKUP_DIR/backup.sh
#!/bin/bash
# Script de respaldo automático para n8n y Evolution API

DATE=\$(date +%Y-%m-%d)
BACKUP_DIR=$BACKUP_DIR

# Crear directorio de respaldo para la fecha actual
mkdir -p \$BACKUP_DIR/\$DATE

# Respaldar bases de datos
echo "Respaldando base de datos de n8n..."
docker exec n8n_postgres pg_dump -U n8n_user -d n8n | gzip > \$BACKUP_DIR/\$DATE/n8n_db_\$DATE.sql.gz

echo "Respaldando base de datos de Evolution API..."
docker exec evolution_postgres pg_dump -U evolution_user -d evolution2 | gzip > \$BACKUP_DIR/\$DATE/evolution_db_\$DATE.sql.gz

# Respaldar volúmenes
echo "Respaldando datos de n8n..."
docker run --rm -v n8n_data:/data -v \$BACKUP_DIR/\$DATE:/backup alpine tar czf /backup/n8n_data_\$DATE.tar.gz -C /data .

echo "Respaldando instancias de Evolution API..."
docker run --rm -v evolution_instances:/data -v \$BACKUP_DIR/\$DATE:/backup alpine tar czf /backup/evolution_instances_\$DATE.tar.gz -C /data .

# Limpiar respaldos antiguos (mantener los últimos 7 días)
find \$BACKUP_DIR -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "Respaldo completado: \$DATE"
EOF

chmod +x $BACKUP_DIR/backup.sh

# Configurar respaldo automático con cron
(crontab -l 2>/dev/null; echo "0 2 * * * $BACKUP_DIR/backup.sh > $LOG_DIR/backup.log 2>&1") | crontab -

# Crear script para configurar ID de cuenta de Chatwoot
log_progress "Creando herramienta para configuración de Chatwoot..."
cat <<EOF > /usr/local/bin/configure-chatwoot-integration
#!/bin/bash
if [ \$# -ne 2 ]; then
  echo "Uso: configure-chatwoot-integration <ID_DE_CUENTA> <TOKEN_API>"
  echo "Ejemplo: configure-chatwoot-integration 1 abcdef123456"
  echo ""
  echo "Para obtener el ID de cuenta:"
  echo "  - Revise la URL después de iniciar sesión: https://${CHATWOOT_SUBDOMAIN}/app/accounts/1/..."
  echo "  - El número después de 'accounts/' es su ID de cuenta"
  echo ""
  echo "Para obtener el Token API:"
  echo "  - Vaya a Configuración del Perfil → API Access Tokens"
  echo "  - Cree un nuevo token con permisos completos"
  exit 1
fi

ACCOUNT_ID=\$1
API_TOKEN=\$2
ENV_FILE="${EVOLUTION_DIR}/.env"

# Validar que el ID sea un número
if ! [[ \$ACCOUNT_ID =~ ^[0-9]+$ ]]; then
  echo "Error: El ID de cuenta debe ser un número"
  exit 1
fi

# Actualizar el archivo .env
sed -i "s/CHATWOOT_ACCOUNT_ID=CHANGE_ME/CHATWOOT_ACCOUNT_ID=\$ACCOUNT_ID/" \$ENV_FILE
sed -i "s/CHATWOOT_TOKEN=CHANGE_ME/CHATWOOT_TOKEN=\$API_TOKEN/" \$ENV_FILE
echo "ID de cuenta de Chatwoot actualizado a \$ACCOUNT_ID"
echo "Token API de Chatwoot actualizado"

# Reiniciar Evolution API para aplicar cambios
cd ${EVOLUTION_DIR} && docker-compose restart evolution-api
echo "Evolution API reiniciado con la nueva configuración"
echo "La integración con Chatwoot ahora debería estar funcionando correctamente"
EOF

chmod +x /usr/local/bin/configure-chatwoot-integration
chmod -R 755 $N8N_DIR $EVOLUTION_DIR $CHATWOOT_DIR
chown -R 1000:1000 $N8N_DIR/data $N8N_DIR/local-files $EVOLUTION_DIR/evolution_instances

# Crear directorios para Chatwoot
mkdir -p $CHATWOOT_DIR/postgres $CHATWOOT_DIR/redis
chmod -R 755 $CHATWOOT_DIR/postgres $CHATWOOT_DIR/redis

# Iniciar servicios
log_progress "Iniciando contenedores Docker..."
cd $N8N_DIR && docker-compose up -d
cd $EVOLUTION_DIR && docker-compose up -d
cd $CHATWOOT_DIR && docker-compose up -d

# Configurar Nginx
log_progress "Configurando Nginx..."
cat <<EOF > /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name ${N8N_SUBDOMAIN};

    access_log /var/log/nginx/n8n.access.log;
    error_log /var/log/nginx/n8n.error.log;

    # Manejo de conexiones ws/wss
    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Configuración de timeouts para WebSockets
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60s;
    }
}
EOF

cat <<EOF > /etc/nginx/sites-available/chatwoot
server {
    listen 80;
    server_name ${CHATWOOT_SUBDOMAIN};

    access_log /var/log/nginx/chatwoot.access.log;
    error_log /var/log/nginx/chatwoot.error.log;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Configuración de timeouts para conexiones
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60s;
    }
}
EOFversion 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Habilitar configuraciones de Nginx
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/evolution /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/

# Eliminar el default si existe
rm -f /etc/nginx/sites-enabled/default

# Verificar configuración de Nginx
nginx -t

# Reiniciar Nginx
systemctl restart nginx

# SSL con certbot
log_progress "Configurando certificados SSL con Certbot..."
certbot --nginx -d ${N8N_SUBDOMAIN} --email ${EMAIL} --agree-tos --non-interactive --redirect
certbot --nginx -d ${EVOLUTION_SUBDOMAIN} --email ${EMAIL} --agree-tos --non-interactive --redirect
certbot --nginx -d ${CHATWOOT_SUBDOMAIN} --email ${EMAIL} --agree-tos --non-interactive --redirect

# Reiniciar Nginx después de configurar SSL
systemctl restart nginx

# Crear script de estado
cat <<EOF > /usr/local/bin/check-services
#!/bin/bash
echo "Estado de los servicios:"
echo "======================="
echo "n8n:"
docker ps --filter "name=app_n8n_service" --format "Status: {{.Status}}"
echo ""
echo "Evolution API:"
docker ps --filter "name=app_evo_api_service" --format "Status: {{.Status}}"
echo ""
echo "Chatwoot:"
docker ps --filter "name=app_chatwoot_service" --format "Status: {{.Status}}"
docker ps --filter "name=app_chatwoot_worker_service" --format "Status: {{.Status}}"
echo ""
echo "Bases de datos:"
docker ps --filter "name=app_n8n_db" --format "- n8n DB: {{.Status}}"
docker ps --filter "name=app_evo_postgres_service" --format "- Evolution DB: {{.Status}}"
docker ps --filter "name=app_chatwoot_postgres_service" --format "- Chatwoot DB: {{.Status}}"
echo ""
echo "Redis:"
docker ps --filter "name=app_evo_redis_service" --format "- Evolution Redis: {{.Status}}"
docker ps --filter "name=app_chatwoot_redis_service" --format "- Chatwoot Redis: {{.Status}}"
echo ""
echo "RabbitMQ:"
docker ps --filter "name=app_evo_rabbitmq_service" --format "Status: {{.Status}}"
echo ""
echo "Certificados SSL:"
echo "- n8n: \$(certbot certificates -d ${N8N_SUBDOMAIN} | grep 'Expiry' | awk '{print \$3, \$4, \$5, \$6}')"
echo "- Evolution: \$(certbot certificates -d ${EVOLUTION_SUBDOMAIN} | grep 'Expiry' | awk '{print \$3, \$4, \$5, \$6}')"
echo "- Chatwoot: \$(certbot certificates -d ${CHATWOOT_SUBDOMAIN} | grep 'Expiry' | awk '{print \$3, \$4, \$5, \$6}')"
EOF

chmod +x /usr/local/bin/check-services

# Mostrar resumen
clear
echo "================================================================"
echo "                   INSTALACIÓN COMPLETADA                        "
echo "================================================================"
echo ""
echo "Las aplicaciones se han instalado correctamente:"
echo ""
echo "1. n8n:"
echo "   - URL: https://${N8N_SUBDOMAIN}"
echo "   - Usuario BD: n8n_user"
echo "   - Contraseña BD: ${DB_PASSWORD}"
echo "   - Clave de Encriptación: ${ENCRYPTION_KEY}"
echo "   - Directorio de datos: ${N8N_DIR}/data"
echo "   - Directorio de archivos locales: ${N8N_DIR}/local-files"
echo "   - Directorio de base de datos: ${N8N_DIR}/db"
echo ""
echo "2. Evolution API:"
echo "   - URL: https://${EVOLUTION_SUBDOMAIN}"
echo "   - Usuario BD: evolution_user"
echo "   - Contraseña BD: ${DB_PASSWORD}"
echo "   - API Key: ${ENCRYPTION_KEY}"
echo "   - Usuario RabbitMQ: evo-rabbit"
echo "   - Contraseña RabbitMQ: ${REDIS_PASSWORD}"
echo "   - Panel RabbitMQ: http://localhost:15672"
echo "   - Directorio de instancias: ${EVOLUTION_DIR}/evolution_instances"
echo "   - Directorio de Redis: ${EVOLUTION_DIR}/evolution_redis"
echo "   - Directorio de BD: ${EVOLUTION_DIR}/evolution_postgres_data"
echo "   - Documentación API: https://${EVOLUTION_SUBDOMAIN}/api-docs"
echo ""
echo "3. Chatwoot:"
echo "   - URL: https://${CHATWOOT_SUBDOMAIN}"
echo "   - Usuario BD: postgres"
echo "   - Contraseña BD: ${CHATWOOT_POSTGRES_PASSWORD}"
echo "   - Secret Key Base: ${CHATWOOT_SECRET_KEY_BASE}"
echo "   - Email: ${EMAIL}"
echo "   - Directorios: ${CHATWOOT_DIR}"
echo ""
echo "4. Redis:"
echo "   - Integrado en Evolution API como 'redis' y en Chatwoot"
echo ""
echo "Directorios importantes:"
echo "   - n8n: ${N8N_DIR}"
echo "   - Evolution API: ${EVOLUTION_DIR}"
echo "   - Respaldos: ${BACKUP_DIR}"
echo ""
echo "Información adicional:"
echo "   - Se ha configurado un respaldo automático diario a las 2:00 AM"
echo "   - Los certificados SSL se renovarán automáticamente"
echo "   - Para ver el estado de los servicios, ejecute: check-services"
echo ""
echo "IMPORTANTE:"
echo "   - Todas las credenciales se han guardado en: ${CREDENTIALS_FILE}"
echo "   - Haga una copia de seguridad de este archivo y luego bórrelo del servidor"
echo ""
echo "Para acceder a n8n:"
echo "   1. Abra https://${N8N_SUBDOMAIN} en su navegador"
echo "   2. Complete el asistente de configuración inicial"
echo ""
echo "Para acceder a Evolution API:"
echo "   1. Use la API Key para autenticarse: ${ENCRYPTION_KEY}"
echo "   2. Documentación: https://${EVOLUTION_SUBDOMAIN}/api-docs"
echo ""
echo "Para acceder a Chatwoot:"
echo "   1. Abra https://${CHATWOOT_SUBDOMAIN} en su navegador"
echo "   2. Cree una cuenta de super admin"
echo "   3. Obtenga su ID de cuenta (visible en la URL después de iniciar sesión, ej: /app/accounts/1/...)"
echo "   4. Vaya a Perfil → Configuración → Tokens de acceso API y cree un nuevo token"
echo "   5. Configure la integración con el comando:"
echo "      configure-chatwoot-integration <ID_DE_CUENTA> <TOKEN_API>"
echo "   6. Configure un canal de WhatsApp en Chatwoot:"
echo "      - Ir a Ajustes → Canales de entrada → Añadir canal → API WhatsApp"
echo "      - URL de la API: https://${EVOLUTION_SUBDOMAIN}"
echo "      - API Key: ${ENCRYPTION_KEY} (La misma que usa Evolution API)"
echo ""
# Ejecutar escaneo de seguridad
log_progress "Ejecutando escaneo de seguridad con rkhunter..."
rkhunter --check --skip-keypress --quiet

log_progress "Ejecutando escaneo de seguridad con chkrootkit..."
chkrootkit

echo "================================================================"
echo "                  ¡INSTALACIÓN EXITOSA!                         "
echo "================================================================"

echo ""
echo "Se han realizado escaneos de seguridad con rkhunter y chkrootkit."
echo "Revise los logs para más detalles:"
echo "  - rkhunter: /var/log/rkhunter.log"
echo "  - chkrootkit: Resultado mostrado arriba"
echo ""
