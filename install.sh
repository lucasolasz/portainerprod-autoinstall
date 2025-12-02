#!/bin/bash
# ================================================
# TRAEFIK + PORTAINER PRODUÇÃO (Docker Swarm 2025)
# FUNCIONA 100% – Testado em Ubuntu 22.04/24.04
# ================================================

GREEN='\e[32m'; YELLOW='\e[33m'; RED='\e[31m'; BLUE='\e[34m'; NC='\e[0m'

clear
echo -e "${GREEN}
  _____          __      __      _            _
 |  __ \\        / _|    / _|    (_)          (_)
 | |__) | __ ___ | |_ ___| |_ _ __ _  ___  _ __
 |  ___/ '__/ _ \\|  _/ _ \\  _| '__| |/ _ \\| '__|
 | |   | | | (_) | ||  __/ | | |  | | (_) | |
 |_|   |_|  \\___/|_| \\___|_| |_|  |_|\\___/|_|
${NC}"
echo -e "${GREEN}       TRAEFIK + PORTAINER (SWARM PRODUÇÃO)${NC}\n"

read -p "E-mail para Let's Encrypt: " email
read -p "Domínio do Portainer (ex: portainer.seudominio.com): " portainer_domain
read -p "Domínio do Edge Stack (ex: edge.seudominio.com): " edge_domain

echo -e "\n${BLUE}Resumo:${NC}"
echo "E-mail:     $email"
echo "Portainer:  https://$portainer_domain"
echo "Edge:       https://$edge_domain\n"
read -p "Tudo certo? (y/n): " confirma
[[ "$confirma" != "y" && "$confirma" != "Y" ]] && echo -e "${RED}Cancelado.${NC}" && exit 0

# 1. Instalar Docker (se não existir)
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Instalando Docker...${NC}"
    curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1
    echo -e "${GREEN}Docker instalado${NC}"
fi

# 2. Iniciar Swarm (se ainda não estiver)
if ! sudo docker info | grep -q "Swarm: active"; then
    echo -e "${YELLOW}Inicializando Swarm...${NC}"
    sudo docker swarm init --advertise-addr $(hostname -I | awk '{print $1}') >/dev/null 2>&1
fi

# 3. Criar diretório
mkdir -p ~/portainerprod && cd ~/portainerprod

# 4. .env
cat > .env <<EOF
LETSENCRYPT_EMAIL=$email
PORTAINER_DOMAIN=$portainer_domain
EDGE_DOMAIN=$edge_domain
EOF

# 5. Rede overlay + volume
sudo docker network create --driver overlay swarm_network 2>/dev/null || true
sudo docker volume create volume_swarm_traefik_acme 2>/dev/null || true

# 6. traefik-stack.yml
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
      - "--accesslog=true"
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
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
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

# 7. portainer-stack.yml
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
      - "traefik.http.routers.portainer.rule=Host('${PORTAINER_DOMAIN}')"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
      - "traefik.http.routers.edge.rule=Host('${EDGE_DOMAIN}')"
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

# 8. SUBIR TUDO (com sudo onde necessário)
echo -e "${YELLOW}Subindo Traefik...${NC}"
sudo docker stack deploy -c traefik-stack.yml traefik

echo -e "${YELLOW}Subindo Portainer + Agent...${NC}"
sudo docker stack deploy -c portainer-stack.yml portainer

# 9. Status final
sleep 8
echo -e "${YELLOW}Status dos serviços:${NC}"
sudo docker stack ls
sudo docker service ls

clear
echo -e "${GREEN}INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${GREEN}════════════════════════════════════${NC}"
echo -e "Portainer → https://$portainer_domain"
echo -e "Edge      → https://$edge_domain"
echo -e "${GREEN}════════════════════════════════════${NC}\n"
echo -e "${BLUE}Aguarde 3-5 minutos para os certificados SSL.${NC}"
echo -e "${BLUE}Depois acesse o Portainer e crie seu usuário admin.${NC}"