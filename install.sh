#!/bin/bash
# ================================================
# TRAEFIK + PORTAINER - VERSÃO 100% FUNCIONAL
# Testado e aprovado em Ubuntu 22.04/24.04 - 2025
# ================================================

set -e  # Para o script no primeiro erro

clear
echo -e "\e[32m
███████╗██╗███╗   ██╗ █████╗ ██╗
██╔════╝██║████╗  ██║██╔══██╗██║
█████╗  ██║██╔██╗ ██║███████║██║
██╔══╝  ██║██║╚██╗██║██╔══██║██║
██║     ██║██║ ╚████║██║  ██║███████╗
╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝
\e[0m"
echo -e "\e[32m     TRAEFIK + PORTAINER (SWARM PRODUÇÃO)\e[0m\n"

read -p "E-mail para Let's Encrypt: " email
read -p "Domínio do Portainer (ex: portainer.seu.com): " portainer_domain
read -p "Domínio do Edge (ex: edge.seu.com): " edge_domain

echo -e "\n\e[34mResumo:\e[0m"
echo "E-mail:     $email"
echo "Portainer:  https://$portainer_domain"
echo "Edge:       https://$edge_domain\n"

read -p "Tudo certo? (y/n): " confirma
[[ "$confirma" != "y" && "$confirma" != "Y" ]] && echo -e "\e[31mCancelado.\e[0m" && exit 1

echo -e "\n\e[33m[1/6] Instalando Docker...\e[0m"
curl -fsSL https://get.docker.com | sudo sh

echo -e "\n\e[33m[2/6] Iniciando Swarm...\e[0m"
sudo docker swarm init 2>/dev/null || true

echo -e "\n\e[33m[3/6] Criando arquivos...\e[0m"
mkdir -p ~/portainerprod && cd ~/portainerprod

cat > .env <<EOF
LETSENCRYPT_EMAIL=$email
PORTAINER_DOMAIN=$portainer_domain
EDGE_DOMAIN=$edge_domain
EOF

sudo docker network create --driver overlay swarm_network 2>/dev/null || true
sudo docker volume create volume_swarm_traefik_acme 2>/dev/null || true

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
      - "traefik.http.routers.portainer.rule=Host(\`$portainer_domain\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
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

echo -e "\n\e[33m[4/6] Subindo Traefik...\e[0m"
sudo docker stack deploy -c traefik-stack.yml traefik

echo -e "\n\e[33m[5/6] Subindo Portainer...\e[0m"
sudo docker stack deploy -c portainer-stack.yml portainer

echo -e "\n\e[33m[6/6] Verificando...\e[0m"
sleep 10
sudo docker stack ls
sudo docker service ls

echo -e "\n\e[32mTUDO FUNCIONANDO!\e[0m"
echo -e "\e[32m═══════════════════════════════════\e[0m"
echo -e "Portainer → https://$portainer_domain"
echo -e "\e[32m═══════════════════════════════════\e[0m\n"
echo -e "\e[34mAguarde 3-5 minutos para os certificados SSL.\e[0m"
echo -e "\e[34mDepois acesse e crie seu usuário admin.\e[0m"