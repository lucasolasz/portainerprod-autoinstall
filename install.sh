#!/bin/bash
# ================================================
# TRAEFIK + PORTAINER PRODUÇÃO (Docker Swarm 2025)
# Repositório: https://github.com/lucasolasz/portainerprod-autoinstall
# ================================================

GREEN='\e[32m'; YELLOW='\e[33m'; RED='\e[31m'; BLUE='\e[34m'; NC='\e[0m'

spinner() {
    local pid=$1; local delay=0.15; local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b\b"
    done
    printf "       \b\b\b\b\b\b\b"
}

clear
echo -e "${GREEN}
  _____          __      __      _            _
 |  __ \        / _|    / _|    (_)          (_)
 | |__) | __ ___ | |_ ___| |_ _ __ _  ___  _ __
 |  ___/ '__/ _ \|  _/ _ \  _| '__| |/ _ \| '__|
 | |   | | | (_) | ||  __/ | | |  | | (_) | |
 |_|   |_|  \___/|_| \___|_| |_|  |_|\___/|_|
${NC}"
echo -e "${GREEN}       TRAEFIK + PORTAINER (SWARM PRODUÇÃO)${NC}"
echo

read -p "E-mail para Let's Encrypt: " email
read -p "Domínio do Portainer (ex: portainer.seudominio.com): " portainer_domain
read -p "Domínio do Edge Stack (ex: edge.seudominio.com): " edge_domain

echo -e "\n${BLUE}Resumo:${NC}"
echo "E-mail: $email"
echo "Portainer: https://$portainer_domain"
echo "Edge:      https://$edge_domain"
echo
read -p "Tudo certo? (y/n): " confirma
[[ "$confirma" != "y" && "$confirma" != "Y" ]] && echo -e "${RED}Cancelado.${NC}" && exit 0

# Instalar Docker se não existir
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Instalando Docker...${NC}"
    curl -fsSL https://get.docker.com | sudo sh > /dev/null 2>&1 &
    spinner $!
fi

# Iniciar Swarm
if ! docker info | grep -q "Swarm: active"; then
    echo -e "${YELLOW}Inicializando Docker Swarm...${NC}"
    docker swarm init --advertise-addr $(hostname -I | awk '{print $1}') > /dev/null 2>&1
fi

# Criar pasta de trabalho
mkdir -p ~/portainerprod && cd ~/portainerprod

# .env
cat > .env <<EOF
LETSENCRYPT_EMAIL=$email
PORTAINER_DOMAIN=$portainer_domain
EDGE_DOMAIN=$edge_domain
EOF

# Rede e volume
docker network create --driver overlay swarm_network 2>/dev/null || true
docker volume create volume_swarm_traefik_acme 2>/dev/null || true

# traefik-stack.yml
cat > traefik-stack.yml <<'EOF'
version: "3.8"
services:
  traefik:
    image: traefik:v2.11
    command:
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
      - "--providers.docker=true"
      - "--providers.docker.swarmmode=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=swarm_network"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${LETSENCRYPT_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/acme/acme.json"
      - "--log.level=INFO"
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.http.routers.catchall.rule=HostRegexp(`{host:.+}`)"
        - "traefik.http.routers.catchall.entrypoints=web"
        - "traefik.http.routers.catchall.middlewares=redirect-https"
        - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
        - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
        - "traefik.http.routers.catchall.priority=1"
    ports:
      - target: 80; published: 80; mode: host
      - target: 443; published: 443; mode: host
    volumes:
      - volume_swarm_traefik_acme:/acme
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks: [swarm_network]
networks:
  swarm_network:
    external: true
volumes:
  volume_swarm_traefik_acme:
    external: true
EOF

# portainer-stack.yml
cat > portainer-stack.yml <<EOF
version: "3.8"
services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
    networks: [swarm_network]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
      - "traefik.http.routers.edge.rule=Host(\`${EDGE_DOMAIN}\`)"
      - "traefik.http.routers.edge.entrypoints=websecure"
      - "traefik.http.routers.edge.tls.certresolver=letsencrypt"
      - "traefik.http.services.edge.loadbalancer.server.port=8000"
  agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    deploy:
      mode: global
    networks: [swarm_network]
networks:
  swarm_network:
    external: true
volumes:
  portainer_data:
EOF

# Subir stacks
echo -e "${YELLOW}Subindo Traefik...${NC}"
docker stack deploy -c traefik-stack.yml traefik &
spinner $!

sleep 12

echo -e "${YELLOW}Subindo Portainer + Agent...${NC}"
docker stack deploy -c portainer-stack.yml portainer &
spinner $!

clear
echo -e "${GREEN}Instalação concluída com sucesso!${NC}"
echo -e "${GREEN}════════════════════════════════════${NC}"
echo -e "Portainer → https://$portainer_domain"
echo -e "Edge Stack → https://$edge_domain"
echo -e "${GREEN}════════════════════════════════════${NC}"
echo -e "\n${BLUE}Aguarde 3-5 minutos para os certificados SSL.${NC}"
echo -e "${BLUE}Depois acesse o Portainer e crie seu admin.${NC}"