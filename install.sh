# Instalar Nginx y Certbot
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx || {
  echo "Error instalando nginx y certbot. Intentando instalar por separado..."
  apt-get install -y nginx
  apt-get install -y certbot
  apt-get install -y python3-certbot-nginx
}cat <<EOF > /etc/nginx/sites-available/chatwoot
server {
    listen 80;
    server_name ${CHATWOOT_SUBDOMAIN};

    location / {
        proxy_pass http://localhost:3200;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location /cable {
        proxy_pass http://localhost:3200/cable;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF#!/bin/bash
# Evolution N8N Chatwoot Auto-Installer
# Instalación fácil: sh <(curl https://raw.githubusercontent.com/men2985/evolution-n8n-installer/main/install.sh || wget -O - https://raw.githubusercontent.com/men2985/evolution-n8n-installer/main/install.sh)
set -e

# Función para asegurar entrada de usuario
get_user_input() {
  local prompt="$1"
  local var_name="$2"
  local default_value="$3"
  local value=""
  
  # Intentar leer input con varios métodos
  printf "%s" "$prompt"
  read -r value </dev/tty || {
    # Si falla, intentar otro método
    echo "Error leyendo desde /dev/tty, intentando método alternativo..."
    printf "%s" "$prompt"
    read -r value || {
      if [ -n "$default_value" ]; then
        echo "Usando valor predeterminado: $default_value"
        value="$default_value"
      else
        echo "ERROR: No se pudo leer entrada del usuario y no hay valor predeterminado."
        exit 1
      fi
    }
  }
  
  # Verificar que no esté vacío
  if [ -z "$value" ] && [ -z "$default_value" ]; then
    echo "ERROR: El valor no puede estar vacío."
    exit 1
  elif [ -z "$value" ] && [ -n "$default_value" ]; then
    value="$default_value"
  fi
  
  # Asignar valor a variable global
  eval "$var_name=\"$value\""
  echo "$var_name configurado como: ${!var_name}"
}

# Solicitar información al usuario
echo "Por favor, introduce los siguientes datos:"
get_user_input "Ingrese su dominio principal (ejemplo.com): " DOMAIN

get_user_input "Ingrese su correo electrónico para SSL: " EMAIL

# Pedir contraseña de Google de forma segura
echo -n "Ingrese la contraseña para la aplicación de Google (para Chatwoot): "
stty -echo </dev/tty
read GOOGLE_PASSWORD </dev/tty
stty echo </dev/tty
echo ""
if [ -z "$GOOGLE_PASSWORD" ]; then
  echo "ERROR: La contraseña de Google no puede estar vacía."
  exit 1
fi

# Verificar si las variables están definidas
if [ -z "$DOMAIN" ]; then
  echo "ERROR: La variable DOMAIN está vacía. Abortando."
  exit 1
fi

if [ -z "$EMAIL" ]; then
  echo "ERROR: La variable EMAIL está vacía. Abortando."
  exit 1
fi

if [ -z "$GOOGLE_PASSWORD" ]; then
  echo "ERROR: La variable GOOGLE_PASSWORD está vacía. Abortando."
  exit 1
fi

# Definir subdominios y directorios
N8N_SUBDOMAIN="n8n.${DOMAIN}"
EVOLUTION_SUBDOMAIN="evoapi.${DOMAIN}"
CHATWOOT_SUBDOMAIN="chat.${DOMAIN}"
PORTAINER_SUBDOMAIN="portainer.${DOMAIN}"
N8N_DIR="/opt/n8n_app"
EVOLUTION_DIR="/opt/evolution_app"
REDIS_DIR="/opt/redis_app"
CHATWOOT_DIR="/opt/chatwoot_app"
PORTAINER_DIR="/opt/portainer_app"

echo "Configurando subdominios:"
echo "- n8n: ${N8N_SUBDOMAIN}"
echo "- Evolution API: ${EVOLUTION_SUBDOMAIN}"
echo "- Chatwoot: ${CHATWOOT_SUBDOMAIN}"
echo "- Portainer: ${PORTAINER_SUBDOMAIN}"

# Crear directorios para las aplicaciones
mkdir -p $N8N_DIR $EVOLUTION_DIR $REDIS_DIR $CHATWOOT_DIR $PORTAINER_DIR
mkdir -p /data/storage /data/postgres /data/redis /data/portainer

# Generar contraseñas y claves seguras
DB_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-16)
ENCRYPTION_KEY=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)
REDIS_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-16)
POSTGRES_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-16)
SECRET_KEY_BASE=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

# Instalar dependencias iniciales
apt-get update
apt-get install -y ca-certificates curl

# Configurar repositorio oficial de Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Añadir el repositorio a APT
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualizar e instalar Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configurar límites de logs para Docker
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Reiniciar Docker para aplicar los cambios
systemctl restart docker

# Iniciar y habilitar Docker
systemctl enable docker

# Crear redes de Docker compartidas
echo "Creando redes Docker..."
docker network rm frontend >/dev/null 2>&1 || true
docker network rm backend >/dev/null 2>&1 || true
docker network create frontend
docker network create backend

# Configurar n8n
mkdir -p /home/docker/n8n/db
mkdir -p /home/docker/n8n/data
mkdir -p /home/docker/n8n/local-files

cat <<EOF > $N8N_DIR/.env
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=n8n
POSTGRES_NON_ROOT_USER=n8n_user
POSTGRES_NON_ROOT_PASSWORD=${DB_PASSWORD}
EOF

cat <<EOF > $N8N_DIR/docker-compose.yml
version: '3.8'
volumes:
  db_storage:
  n8n_storage:
services:
  'n8n-db':
    image: docker.io/bitnami/postgresql:16
    restart: always
    user: root
    environment:
      - POSTGRESQL_USERNAME=n8n_user
      - POSTGRESQL_DATABASE=n8n
      - POSTGRESQL_PASSWORD=${DB_PASSWORD}
    networks:
      - backend
    volumes:
      - "/home/docker/n8n/db:/bitnami/postgresql"
  'n8n':
    image: docker.n8n.io/n8nio/n8n
    restart: always
    user: root
    environment:
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-db
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
      - 5678:5678
    links:
      - n8n-db
    networks:
      - frontend
      - backend
    volumes:
      - /home/docker/n8n/data:/home/node/.n8n
      - /home/docker/n8n/local-files:/files
    depends_on:
      - 'n8n-db'
EOF

# Configurar Evolution API
mkdir -p $EVOLUTION_DIR/evolution_instances
mkdir -p $EVOLUTION_DIR/evolution_redis
mkdir -p $EVOLUTION_DIR/evolution_postgres_data
mkdir -p $EVOLUTION_DIR/rabbitmq_data

cat <<EOF > $EVOLUTION_DIR/.env
SERVER_TYPE=http
SERVER_PORT=8080
SERVER_URL=https://${EVOLUTION_SUBDOMAIN}

SENTRY_DSN=

CORS_ORIGIN=*
CORS_METHODS=GET,POST,PUT,DELETE
CORS_CREDENTIALS=true

LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE,DARK,WEBHOOKS,WEBSOCKET
LOG_COLOR=true
LOG_BAILEYS=error

EVENT_EMITTER_MAX_LISTENERS=50

DEL_INSTANCE=false

DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://evolution_user:${DB_PASSWORD}@postgres:5432/evolution2?schema=public
DATABASE_CONNECTION_CLIENT_NAME=evolution

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

RABBITMQ_ENABLED=true
RABBITMQ_URI=amqp://evo-rabbit:${REDIS_PASSWORD}@rabbitmq:5672/default
RABBITMQ_EXCHANGE_NAME=evolution
RABBITMQ_ERLANG_COOKIE=${REDIS_PASSWORD}
RABBITMQ_DEFAULT_VHOST=default
RABBITMQ_DEFAULT_USER=evo-rabbit
RABBITMQ_DEFAULT_PASS=${REDIS_PASSWORD}
RABBITMQ_GLOBAL_ENABLED=false
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

SQS_ENABLED=false

WEBSOCKET_ENABLED=false
WEBSOCKET_GLOBAL_EVENTS=false

PUSHER_ENABLED=false
PUSHER_GLOBAL_ENABLED=false

WEBHOOK_GLOBAL_ENABLED=false
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
WEBHOOK_EVENTS_LABELS_EDIT=true
WEBHOOK_EVENTS_LABELS_ASSOCIATION=true
WEBHOOK_EVENTS_CALL=true

CONFIG_SESSION_PHONE_CLIENT=Evolution API
CONFIG_SESSION_PHONE_NAME=Chrome
CONFIG_SESSION_PHONE_VERSION=2.3000.1015901307

QRCODE_LIMIT=30
QRCODE_COLOR='#175197'

TYPEBOT_ENABLED=true
TYPEBOT_API_VERSION=latest

CHATWOOT_ENABLED=true
CHATWOOT_MESSAGE_READ=true
CHATWOOT_MESSAGE_DELETE=true
CHATWOOT_BOT_CONTACT=true
CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgresql://evolution_user:${DB_PASSWORD}@postgres:5432/evolution2?schema=public
CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true

OPENAI_ENABLED=false

DIFY_ENABLED=false

CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://redis:6379/2
CACHE_REDIS_TTL=604800
CACHE_REDIS_PREFIX_KEY=evolution
CACHE_REDIS_SAVE_INSTANCES=false
CACHE_LOCAL_ENABLED=false

S3_ENABLED=false

AUTHENTICATION_API_KEY=${ENCRYPTION_KEY}
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
LANGUAGE=es
EOF

cat <<EOF > $EVOLUTION_DIR/docker-compose.yml
services:
  evolution-api:
    container_name: evolution-api
    image: atendai/evolution-api:latest
    restart: always
    depends_on:
      - redis
      - postgres
    ports:
      - 8080:8080
    volumes:
      - ./evolution_instances:/evolution/instances
    networks:
      - frontend
      - backend
    env_file:
      - .env
    expose:
      - 8080
  redis:
    image: redis:latest
    networks:
      - backend
    command: >
      redis-server --port 6379 --appendonly yes
    volumes:
      - ./evolution_redis:/data
  postgres:
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
 
  rabbitmq:
    image: rabbitmq:management
    entrypoint: docker-entrypoint.sh
    command: rabbitmq-server
    ports:
      - 5672:5672
      - 15672:15672
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
volumes:
  evolution_instances:
  evolution_redis:
  evolution_postgres_data:
  rabbitmq_data:
    name: rabbitmq_data
networks:
  frontend:
    name: frontend
    external: true
  backend:
    name: backend
    external: true
EOF

# Configurar Chatwoot
cat <<EOF > $CHATWOOT_DIR/docker-compose.yml
version: '3'

services:
  base: &base
    image: chatwoot/chatwoot:latest
    env_file: .env
    volumes:
      - /data/storage:/app/storage
    networks:
      - backend
  rails:
    <<: *base
    depends_on:
      - chatwoot-postgres
      - redis
    ports:
      - '3200:3000'
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    entrypoint: docker/entrypoints/rails.sh
    command: ['bundle', 'exec', 'rails', 's', '-p', '3000', '-b', '0.0.0.0']
    restart: always
    networks:
      - frontend
      - backend
  sidekiq:
    <<: *base
    depends_on:
      - chatwoot-postgres
      - redis
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    command: ['bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml']
    restart: always
    networks:
      - backend
  chatwoot-postgres:
    container_name: chatwoot-postgres
    image: pgvector/pgvector:pg12
    restart: always
    volumes:
      - /data/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=chatwoot
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    networks:
      - backend
  redis:
    image: redis:alpine
    restart: always
    command: ["sh", "-c", "redis-server --requirepass \"\$REDIS_PASSWORD\""]
    env_file: .env
    volumes:
      - /data/redis:/data
    networks:
      - backend

networks:
  frontend:
    external: true
  backend:
    external: true
EOF

# Configurar .env para Chatwoot
cat <<EOF > "$CHATWOOT_DIR/.env"
SECRET_KEY_BASE=${SECRET_KEY_BASE}
FRONTEND_URL=https://${CHATWOOT_SUBDOMAIN}
WEBSOCKET_URL=wss://${CHATWOOT_SUBDOMAIN}/cable
FORCE_SSL=true
ENABLE_ACCOUNT_SIGNUP=false
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
REDIS_PASSWORD=${REDIS_PASSWORD}
POSTGRES_DATABASE=chatwoot
POSTGRES_HOST=chatwoot-postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
RAILS_ENV=production
MAILER_SENDER_EMAIL=Chatwoot <noreply@${DOMAIN}>
SMTP_DOMAIN=${DOMAIN}
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=${EMAIL}
SMTP_PASSWORD=${GOOGLE_PASSWORD}
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
SMTP_OPENSSL_VERIFY_MODE=peer
MAILER_INBOUND_EMAIL_DOMAIN=${DOMAIN}
ACTIVE_STORAGE_SERVICE=local
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info
LOG_SIZE=500
ENABLE_RACK_ATTACK=true
ENABLE_PUSH_RELAY_SERVER=true
DIRECT_UPLOADS_ENABLED=

# Acceso a la base de datos de Evolution API para integración
DATABASE_URL=postgresql://evolution_user:${DB_PASSWORD}@postgres:5432/evolution2
EOF

# Iniciar servicios
# Iniciar servicios
echo "Verificando redes Docker..."
if ! docker network inspect frontend >/dev/null 2>&1; then
  echo "Creando red frontend..."
  docker network create frontend
fi

if ! docker network inspect backend >/dev/null 2>&1; then
  echo "Creando red backend..."
  docker network create backend
fi

echo "Iniciando n8n..."
cd $N8N_DIR && docker-compose up -d
echo "Iniciando Evolution API..."
cd $EVOLUTION_DIR && docker-compose up -d
echo "Iniciando Chatwoot..."
cd $CHATWOOT_DIR && docker-compose up -d
echo "Iniciando Redis..."
cd $REDIS_DIR && docker-compose up -d
# Portainer ya ha sido iniciado anteriormente mediante docker run

# Configurar Nginx
cat <<EOF > /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name ${N8N_SUBDOMAIN};

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

cat <<EOF > /etc/nginx/sites-available/evolution
server {
    listen 80;
    server_name ${EVOLUTION_SUBDOMAIN};

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

cat <<EOF > /etc/nginx/sites-available/portainer
server {
    listen 80;
    server_name ${PORTAINER_SUBDOMAIN};

    location / {
        proxy_pass http://localhost:9000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Verificar dominios antes de continuar
echo "Verificando que los subdominios estén configurados correctamente:"
echo "N8N_SUBDOMAIN: ${N8N_SUBDOMAIN}"
echo "EVOLUTION_SUBDOMAIN: ${EVOLUTION_SUBDOMAIN}"
echo "CHATWOOT_SUBDOMAIN: ${CHATWOOT_SUBDOMAIN}"
echo "PORTAINER_SUBDOMAIN: ${PORTAINER_SUBDOMAIN}"

if [ -z "${N8N_SUBDOMAIN}" ] || [ -z "${EVOLUTION_SUBDOMAIN}" ] || [ -z "${CHATWOOT_SUBDOMAIN}" ] || [ -z "${PORTAINER_SUBDOMAIN}" ]; then
  echo "ERROR: Uno o más subdominios están vacíos. Abortando."
  exit 1
fi

# Verificar enlaces simbólicos
echo "Creando enlaces simbólicos para configuraciones de Nginx..."
rm -f /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/evolution
rm -f /etc/nginx/sites-enabled/chatwoot
rm -f /etc/nginx/sites-enabled/portainer

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/evolution /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/portainer /etc/nginx/sites-enabled/

# Validar la configuración de Nginx antes de reiniciar
echo "Validando configuración de Nginx..."
nginx -t || {
  echo "Error en la configuración de Nginx. Revisando archivos..."
  for config in /etc/nginx/sites-enabled/*; do
    echo "Verificando $config:"
    cat "$config"
    echo "------------------------"
  done
  exit 1
}

# Reiniciar Nginx solo si la configuración es válida
systemctl restart nginx || echo "Error al reiniciar Nginx"

# SSL con certbot
if [ -n "${N8N_SUBDOMAIN}" ]; then
  certbot --nginx -d "${N8N_SUBDOMAIN}" --email "${EMAIL}" --agree-tos --non-interactive
fi

if [ -n "${EVOLUTION_SUBDOMAIN}" ]; then
  certbot --nginx -d "${EVOLUTION_SUBDOMAIN}" --email "${EMAIL}" --agree-tos --non-interactive
fi

if [ -n "${CHATWOOT_SUBDOMAIN}" ]; then
  certbot --nginx -d "${CHATWOOT_SUBDOMAIN}" --email "${EMAIL}" --agree-tos --non-interactive
fi

if [ -n "${PORTAINER_SUBDOMAIN}" ]; then
  certbot --nginx -d "${PORTAINER_SUBDOMAIN}" --email "${EMAIL}" --agree-tos --non-interactive
fi
systemctl restart nginx

# Mostrar resumen
echo "------------------------------------------------------------"
echo "                   RESUMEN DE LA INSTALACIÓN                "
echo "------------------------------------------------------------"
echo "Las aplicaciones se han instalado correctamente:"
echo ""
echo "1. n8n:"
echo "   - URL: https://${N8N_SUBDOMAIN}"
echo "   - Contenedor: nn8nn_app"
echo "   - DB: n8n_user"
echo "   - DB Password: ${DB_PASSWORD}"
echo "   - Encryption Key: ${ENCRYPTION_KEY}"
echo ""
echo "2. Evolution API:"
echo "   - URL: https://${EVOLUTION_SUBDOMAIN}"
echo "   - Contenedor: evolution-api"
echo "   - DB: evolution_user"
echo "   - DB Password: ${DB_PASSWORD}"
echo "   - API Key: ${ENCRYPTION_KEY}"
echo "   - RabbitMQ Admin: http://localhost:15672 (usuario: evo-rabbit, contraseña: ${REDIS_PASSWORD})"
echo ""
echo "3. Chatwoot:"
echo "   - URL: https://${CHATWOOT_SUBDOMAIN}"
echo "   - DB: postgres"
echo "   - DB Password: ${POSTGRES_PASSWORD}"
echo "   - Secret Key Base: ${SECRET_KEY_BASE}"
echo "   - SMTP configurado con tu cuenta de Google"
echo ""
echo "4. Redis:"
echo "   - Contenedor: redis_server"
echo "   - Contraseña: ${REDIS_PASSWORD}"
echo ""
echo "------------------------------------------------------------"
echo "IMPORTANTE: Guarda esta información en un lugar seguro."
echo "NOTA: El primer inicio de Chatwoot puede tardar varios minutos."
echo ""
echo "PASOS ADICIONALES PARA COMPLETAR LA INTEGRACIÓN:"
echo "1. Accede a Chatwoot en https://${CHATWOOT_SUBDOMAIN} y completa la configuración inicial"
echo "2. Crea un usuario administrador"
echo "3. Genera un token de API desde Profile Settings -> Access Token"
echo "4. Configura este token en Evolution API para completar la integración"
echo "------------------------------------------------------------"
