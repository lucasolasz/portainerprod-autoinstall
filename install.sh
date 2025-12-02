#!/bin/bash

echo "===== CONFIGURAÇÃO AUTOMÁTICA DO TRAEFIK ====="

# ------------------------------
# COLETAR DADOS DO USUÁRIO
# ------------------------------
read -p "Digite o email para Let's Encrypt: " TRAEFIK_EMAIL
read -p "Digite o domínio para o dashboard Traefik (ex: traefik.seudominio.com): " TRAEFIK_HOST

echo "Digite a senha para acessar o dashboard:"
read -s PASSWORD
echo

# ------------------------------
# GERAR HASH DA SENHA
# ------------------------------
echo "Gerando senha criptografada..."
HASH=$(htpasswd -nb admin "$PASSWORD")
echo "Senha gerada: $HASH"

# ------------------------------
# INSTALAR DOCKER
# ------------------------------
echo "Instalando Docker..."
curl -fsSL https://get.docker.com | sudo bash

# ------------------------------
# INSTALAR DOCKER COMPOSE
# ------------------------------
echo "Instalando Docker Compose..."
sudo apt install docker-compose -y

# ------------------------------
# CRIAR REDE DO TRAEFIK
# ------------------------------
echo "Criando rede traefik-public..."
docker network create traefik-public || true

# ------------------------------
# CRIAR ARQUIVOS NECESSÁRIOS
# ------------------------------
echo "Criando acme.json..."
touch acme.json
chmod 600 acme.json

echo "Criando arquivo .env..."
cat > .env <<EOF
TRAEFIK_EMAIL=$TRAEFIK_EMAIL
TRAEFIK_USER=$HASH
TRAEFIK_HOST=$TRAEFIK_HOST
EOF

# ------------------------------
# CRIAR DOCKER COMPOSE DO TRAEFIK
# ------------------------------
echo "Gerando docker-compose.yml..."

cat > docker-compose.yml <<'EOF'
version: "3.9"

services:
  traefik:
    container_name: traefik
    image: "traefik:v2.11"
    restart: always

    command:
      - --log.level=ERROR
      - --api.insecure=false
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=traefik-public
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      - --certificatesresolvers.leresolver.acme.tlschallenge=true
      - --certificatesresolvers.leresolver.acme.email=${TRAEFIK_EMAIL}
      - --certificatesresolvers.leresolver.acme.storage=/acme.json

    ports:
      - "80:80"
      - "443:443"

    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./acme.json:/acme.json"

    networks:
      - traefik-public

    labels:
      - "traefik.http.routers.traefik.rule=Host(`${TRAEFIK_HOST}`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.tls.certresolver=leresolver"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_USER}"
      - "traefik.http.routers.traefik.middlewares=traefik-auth"

networks:
  traefik-public:
    external: true
EOF

# ------------------------------
# SUBIR O TRAEFIK
# ------------------------------
echo "Subindo o Traefik..."
docker compose up -d

echo "====================================================="
echo "Traefik instalado e rodando!"
echo "Acesse: https://${TRAEFIK_HOST}"
echo "Login: admin"
echo "====================================================="
