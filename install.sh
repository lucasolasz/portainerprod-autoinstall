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

# Gerar hash da senha
echo "🔐 Gerando hash da senha..."
sudo apt install apache2-utils -y >/dev/null 2>&1
HASH=$(htpasswd -nb admin "$PASSWORD")
echo "Hash gerado: $HASH"


# ---------------------------------------------
# 3. INSTALAR DOCKER
# ---------------------------------------------
echo "🐳 Instalando Docker..."
curl -fsSL https://get.docker.com | sudo bash >/dev/null 2>&1

sudo systemctl enable docker >/dev/null 2>&1
sudo systemctl start docker >/dev/null 2>&1

# Adicionar usuário ubuntu ao grupo docker
echo "🔧 Ajustando permissões do Docker..."
sudo usermod -aG docker ubuntu
newgrp docker <<EONG
echo "Permissões aplicadas."
EONG


# ---------------------------------------------
# 4. INSTALAR DOCKER COMPOSE
# ---------------------------------------------
echo "🧩 Instalando Docker Compose..."
sudo apt install docker-compose -y >/dev/null 2>&1


# ---------------------------------------------
# 5. CRIAR REDE traefik-public
# ---------------------------------------------
echo "🌐 Criando rede Docker traefik-public..."
docker network create traefik-public >/dev/null 2>&1 || true


# ---------------------------------------------
# 6. CRIAR ACME.JSON COM PERMISSÕES CORRETAS
# ---------------------------------------------
echo "📄 Criando acme.json..."
rm -f acme.json
touch acme.json
chmod 600 acme.json


# ---------------------------------------------
# 7. GERAR ARQUIVO .env
# ---------------------------------------------
echo "⚙️ Criando .env..."
cat > .env <<EOF
TRAEFIK_EMAIL=$TRAEFIK_EMAIL
TRAEFIK_USER=$HASH
TRAEFIK_HOST=$TRAEFIK_HOST
EOF


# ---------------------------------------------
# 8. GERAR DOCKER-COMPOSE SEGURO E VALIDADO
# ---------------------------------------------
echo "📝 Criando docker-compose.yml seguro..."

cat > docker-compose.yml <<'EOF'
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


# ---------------------------------------------
# 9. VALIDAR YAML ANTES DE SUBIR
# ---------------------------------------------
echo "🔍 Validando docker-compose.yml..."
sudo docker compose config >/dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "❌ ERRO: O arquivo docker-compose.yml está inválido!"
  echo "Abra o arquivo e verifique indentação."
  exit 1
fi
echo "✔ YAML válido."


# ---------------------------------------------
# 10. SUBIR TRAEFIK
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
echo "Caso a porta 443 ou 80 esteja bloqueada no Oracle Cloud,"
echo "libere no painel de segurança da instância!"
echo "==================================================="
