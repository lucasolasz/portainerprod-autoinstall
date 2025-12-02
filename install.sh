#!/bin/bash

echo "=============================================="
echo "  INSTALADOR AUTOMÁTICO DO TRAEFIK (SEGURO)   "
echo "      Otimizado para Ubuntu + Oracle Cloud     "
echo "=============================================="

# ---------------------------------------------
# 1. VERIFICAR SE O USUÁRIO É UBUNTU
# ---------------------------------------------
if [ "$(whoami)" != "ubuntu" ]; then
  echo "⚠️  ATENÇÃO: você não está rodando como usuário 'ubuntu'"
  echo "Recomendo entrar como ubuntu e rodar novamente:"
  echo "sudo su - ubuntu"
  exit 1
fi


# ---------------------------------------------
# 2. COLETAR DADOS DO USUÁRIO
# ---------------------------------------------
read -p "Digite o e-mail para Let's Encrypt: " TRAEFIK_EMAIL
read -p "Digite o domínio do dashboard Traefik (ex: traefik.seudominio.com): " TRAEFIK_HOST

echo "Digite a senha do dashboard Traefik:"
read -s PASSWORD
echo


# ---------------------------------------------
# 3. INSTALAR apache2-utils SE NECESSÁRIO
# ---------------------------------------------
if ! command -v htpasswd >/dev/null 2>&1; then
  echo "📦 Instalando apache2-utils para gerar hash..."
  sudo apt update -y >/dev/null 2>&1
  sudo apt install apache2-utils -y >/dev/null 2>&1
else
  echo "✔ apache2-utils já instalado."
fi

# Gerar hash
echo "🔐 Gerando hash da senha..."
HASH=$(htpasswd -nb admin "$PASSWORD")
echo "Hash gerado: $HASH"


# ---------------------------------------------
# 4. INSTALAR DOCKER SE NECESSÁRIO
# ---------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "🐳 Instalando Docker..."
  sudo curl -fsSL https://get.docker.com | sudo bash >/dev/null 2>&1
  sudo systemctl enable docker >/dev/null 2>&1
  sudo systemctl start docker >/dev/null 2>&1
  echo "✔ Docker instalado."
else
  echo "✔ Docker já está instalado."
fi


# ---------------------------------------------
# 5. INSTALAR DOCKER COMPOSE SE NECESSÁRIO
# ---------------------------------------------
if ! docker compose version >/dev/null 2>&1; then
  echo "🧩 Instalando Docker Compose..."
  sudo apt install docker-compose -y >/dev/null 2>&1
  echo "✔ Docker Compose instalado."
else
  echo "✔ Docker Compose já está instalado."
fi


# ---------------------------------------------
# 6. CRIAR REDE traefik-public SE NÃO EXISTIR
# ---------------------------------------------
echo "🌐 Verificando rede traefik-public..."
if ! sudo docker network ls | grep -q "traefik-public"; then
  sudo docker network create traefik-public >/dev/null 2>&1
  echo "✔ Rede traefik-public criada."
else
  echo "✔ Rede traefik-public já existe."
fi


# ---------------------------------------------
# 7. CRIAR ACME.JSON
# ---------------------------------------------
echo "📄 Criando acme.json..."
sudo rm -f acme.json
sudo touch acme.json
sudo chmod 600 acme.json


# ---------------------------------------------
# 8. GERAR ARQUIVO .env
# ---------------------------------------------
echo "⚙️ Criando .env..."
cat > .env <<EOF
TRAEFIK_EMAIL=$TRAEFIK_EMAIL
TRAEFIK_USER=$HASH
TRAEFIK_HOST=$TRAEFIK_HOST
EOF


# ---------------------------------------------
# 9. GERAR DOCKER-COMPOSE.YML
# ---------------------------------------------
echo "📝 Criando docker-compose.yml..."

cat > docker-compose.yml <<EOF
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
      - "traefik.http.routers.traefik.rule=Host(${TRAEFIK_HOST})"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.tls.certresolver=leresolver"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_USER}"
      - "traefik.http.routers.traefik.middlewares=traefik-auth"

networks:
  traefik-public:
    external: true
EOF


# ---------------------------------------------
# 10. VALIDAR O YAML
# ---------------------------------------------
echo "🔍 Validando docker-compose.yml..."
sudo docker compose config >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "❌ ERRO: Arquivo docker-compose.yml inválido!"
  exit 1
fi
echo "✔ YAML válido."


# ---------------------------------------------
# 11. SUBIR TRAEFIK
# ---------------------------------------------
echo "🚀 Subindo Traefik..."
sudo docker compose up -d

echo "==================================================="
echo "🎉 TRAEFIK INSTALADO E RODANDO!"
echo "Acesse o dashboard em:"
echo "👉 https://$TRAEFIK_HOST"
echo ""
echo "Login: admin"
echo "Senha: (a que você digitou)"
echo ""
echo "Se necessário, libere portas 80/443 no Oracle Cloud."
echo "==================================================="