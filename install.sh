#!/bin/bash

# ======================================================================
#  AUTO-INSTALADOR – TRAEFIK + PORTAINER EM DOCKER SWARM (PRODUÇÃO)
# ======================================================================

GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[34m'
NC='\e[0m'

clear
echo -e "${GREEN}============================================================"
echo -e "        INSTALAÇÃO AUTOMÁTICA – SWARM + TRAEFIK + PORTAINER"
echo -e "============================================================${NC}"

sleep 1

# ============================================================
# PERGUNTAS AO USUÁRIO
# ============================================================

read -p "📧 Seu e-mail (LetsEncrypt): " email
read -p "🌐 Domínio do Traefik (dashboard): " traefik
read -p "🌐 Domínio do Portainer (UI): " portainer
read -p "🌐 Domínio do Edge Agent: " edge
read -s -p "🔑 Usuário e senha do dashboard (formato user:$(openssl passwd -apr1 pass)): " senha
echo ""

# ============================================================
# INSTALAR DOCKER
# ============================================================

echo -e "${BLUE}📦 Instalando Docker...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh > /dev/null 2>&1

# ============================================================
# INICIALIZAR SWARM
# ============================================================

echo -e "${BLUE}⚙️ Inicializando Docker Swarm...${NC}"
docker swarm init > /dev/null 2>&1 || true

# ============================================================
# CRIAR DIRETÓRIO
# ============================================================

mkdir -p /opt/prod-infra
cd /opt/prod-infra

# ============================================================
# CRIAR ARQUIVOS DE VOLUME
# ============================================================

touch acme.json
chmod 600 acme.json

# ============================================================
# DOCKER STACK – PRODUÇÃO COM SWARM
# ============================================================

cat > docker-compose.yml <<EOF
version: "3.8"

services:

  traefik:
    image: traefik:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_letsencrypt:/letsencrypt
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"

        # Redirecionamento HTTP -> HTTPS
        - "traefik.http.routers.http-catchall.rule=HostRegexp(\`{host:.+}\`)"
        - "traefik.http.routers.http-catchall.entrypoints=web"
        - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
        - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"

        # Dashboard
        - "traefik.http.routers.dashboard.rule=Host(\`${traefik}\`)"
        - "traefik.http.routers.dashboard.entrypoints=websecure"
        - "traefik.http.routers.dashboard.tls.certresolver=leresolver"
        - "traefik.http.routers.dashboard.service=api@internal"
        - "traefik.http.middlewares.dashboard-auth.basicauth.users=${senha}"
        - "traefik.http.routers.dashboard.middlewares=dashboard-auth"

    command:
      - --providers.docker.swarmmode=true
      - --providers.docker
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.leresolver.acme.email=${email}
      - --certificatesresolvers.leresolver.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.leresolver.acme.httpchallenge.entrypoint=web
      - --api.dashboard=true
      - --api.insecure=false
      - --log.level=ERROR

  portainer:
    image: portainer/portainer-ce:latest
    volumes:
      - portainer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"

        # Portainer UI
        - "traefik.http.routers.portainer.rule=Host(\`${portainer}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=leresolver"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

        # Edge
        - "traefik.http.routers.edge.rule=Host(\`${edge}\`)"
        - "traefik.http.routers.edge.entrypoints=websecure"
        - "traefik.http.routers.edge.tls.certresolver=leresolver"
        - "traefik.http.services.edge.loadbalancer.server.port=8000"

volumes:
  traefik_letsencrypt:
  portainer_data:
EOF

# ============================================================
# DEPLOY STACK
# ============================================================

echo -e "${GREEN}🚀 Deploy da stack em produção...${NC}"
docker stack deploy -c docker-compose.yml infra

sleep 3

echo -e "${GREEN}"
echo "============================================================"
echo " Instalação concluída com sucesso! "
echo "============================================================"
echo -e "${BLUE}Traefik Dashboard:${NC} https://${traefik}"
echo -e "${BLUE}Portainer:${NC} https://${portainer}"
echo -e "${BLUE}Edge Agent:${NC} https://${edge}"
echo ""
echo -e "${YELLOW}Aguarde alguns minutos até os certificados SSL serem emitidos.${NC}"
