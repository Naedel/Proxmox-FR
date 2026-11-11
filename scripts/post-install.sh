#!/usr/bin/env bash
# ==============================================================================
# Script de Post-Installation Proxmox VE (Français)
# Dépôt : https://github.com/Naedel/Proxmox-FR
# Compatibilité : Proxmox VE 8.x (Debian 12 Bookworm) & 9.x (Debian 13 Trixie)
# ==============================================================================
# Ce script réalise de façon idempotente et sécurisée :
#   1. La sauvegarde des fichiers de dépôts APT existants
#   2. La désactivation des dépôts payants (pve-enterprise & ceph-enterprise)
#   3. L'activation des dépôts officiels gratuits (pve-no-subscription & ceph)
#   4. La suppression persistante de la popup d'abonnement (Nag Screen)
#   5. La mise à jour complète du système (apt-get full-upgrade)
#   6. L'installation du microcode CPU (Intel ou AMD) et des utilitaires de base
#   7. L'optimisation du paramètre noyau vm.swappiness (réduit à 10)
# ==============================================================================

set -euo pipefail

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Reset

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[ATTENTION]${NC} $*"; }
error()   { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }

# Mode non-interactif possible avec : ./post-install.sh --yes
ASSUME_YES=false
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
    ASSUME_YES=true
fi

confirm() {
    local prompt="$1"
    if [[ "$ASSUME_YES" == true ]]; then
        return 0
    fi
    read -r -p "$(echo -e "${YELLOW}?${NC} ${prompt} [O/n] : ")" response
    case "$response" in
        [nN][oO]|[nN]) return 1 ;;
        *) return 0 ;;
    esac
}

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}       Script de Post-Installation Proxmox VE (Proxmox-FR)            ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. Vérification des privilèges root et de l'environnement Proxmox VE
if [[ "$EUID" -ne 0 ]]; then
    error "Ce script doit être exécuté en tant que root (utilisez sudo ou connectez-vous en root)."
fi

if ! command -v pveversion >/dev/null 2>&1; then
    error "Proxmox VE ne semble pas installé sur cette machine (commande 'pveversion' introuvable)."
fi

DEBIAN_CODENAME=$(grep -oP '(?<=VERSION_CODENAME=).*' /etc/os-release | tr -d '"' || echo "bookworm")
PVE_VER=$(pveversion | awk -F'/' '{print $2}')
info "Système détecté : Proxmox VE ${PVE_VER} (Debian ${DEBIAN_CODENAME})"

# 2. Sauvegarde et configuration des dépôts APT
if confirm "Voulez-vous configurer les dépôts gratuits (pve-no-subscription) et désactiver les dépôts Enterprise ?"; then
    BACKUP_DIR="/root/proxmox-apt-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r /etc/apt/sources.list* "$BACKUP_DIR/" 2>/dev/null || true
    info "Sauvegarde des dépôts actuels effectuée dans : ${BACKUP_DIR}"

    # Désactivation des dépôts Enterprise (.list et .sources DEB822)
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list
        success "Dépôt pve-enterprise.list désactivé."
    fi
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.sources ]]; then
        mv /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/pve-enterprise.sources.disabled
        success "Dépôt pve-enterprise.sources désactivé."
    fi
    if [[ -f /etc/apt/sources.list.d/ceph.list ]]; then
        sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/ceph.list
        success "Dépôt ceph.list (Enterprise) désactivé."
    fi
    if [[ -f /etc/apt/sources.list.d/ceph.sources ]]; then
        mv /etc/apt/sources.list.d/ceph.sources /etc/apt/sources.list.d/ceph.sources.disabled
        success "Dépôt ceph.sources (Enterprise) désactivé."
    fi

    # Ajout du dépôt gratuit pve-no-subscription
    cat << EOF > /etc/apt/sources.list.d/pve-no-subscription.list
# Dépôt officiel Proxmox VE gratuit (No-Subscription) - Configuré par Proxmox-FR
deb http://download.proxmox.com/debian/pve ${DEBIAN_CODENAME} pve-no-subscription
EOF
    success "Dépôt pve-no-subscription activé pour ${DEBIAN_CODENAME}."

    # Ajout du dépôt gratuit Ceph (Squid par défaut sur PVE 8.2+)
    cat << EOF > /etc/apt/sources.list.d/ceph-no-subscription.list
# Dépôt officiel Ceph gratuit (No-Subscription) - Configuré par Proxmox-FR
deb http://download.proxmox.com/debian/ceph-squid ${DEBIAN_CODENAME} no-subscription
EOF
    success "Dépôt ceph-squid no-subscription activé."

    # Activation de non-free-firmware sur Debian (requis pour intel-microcode / amd64-microcode)
    if [[ -f /etc/apt/sources.list ]] && ! grep -q "non-free-firmware" /etc/apt/sources.list; then
        sed -i 's/main contrib$/main contrib non-free-firmware/g' /etc/apt/sources.list
        success "Composant 'non-free-firmware' ajouté à /etc/apt/sources.list."
    fi
fi

# 3. Suppression persistante de la popup d'abonnement (Nag Screen)
if confirm "Voulez-vous désactiver la popup 'Pas d'abonnement valide' (Nag Screen) de l'interface Web ?"; then
    cat << 'EOF' > /etc/apt/apt.conf.d/no-nag-script
DPkg::Post-Invoke { "dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ $? -eq 1 ]; then { echo 'Suppression de la popup d abonnement Proxmox...'; sed -i '/.*data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi"; };
EOF
    chmod 644 /etc/apt/apt.conf.d/no-nag-script
    if [[ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]]; then
        sed -i '/.*data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js || true
        systemctl restart pveproxy.service || true
    fi
    success "Popup d'abonnement désactivée (pensez à faire Ctrl+F5 dans votre navigateur)."
fi

# 4. Mise à jour complète de Proxmox VE (full-upgrade)
if confirm "Voulez-vous mettre à jour tous les paquets du système (apt-get full-upgrade) ?"; then
    info "Mise à jour de la liste des paquets APT..."
    apt-get update
    info "Installation des mises à jour (full-upgrade)..."
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    success "Système Proxmox VE entièrement mis à jour."
fi

# 5. Installation du microcode CPU (Intel ou AMD)
if confirm "Voulez-vous installer automatiquement le microcode CPU (Intel/AMD) ?"; then
    CPU_VENDOR=$(awk -F': ' '/vendor_id/ {print $2; exit}' /proc/cpuinfo || echo "unknown")
    if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        info "Processeur Intel détecté. Installation de intel-microcode..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y intel-microcode iucode-tool
        success "Microcode Intel installé."
    elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
        info "Processeur AMD détecté. Installation de amd64-microcode..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y amd64-microcode
        success "Microcode AMD installé."
    else
        warn "Fournisseur CPU non reconnu (${CPU_VENDOR}), étape ignorée."
    fi
fi

# 6. Installation des outils d'administration essentiels
if confirm "Voulez-vous installer les outils d'administration recommandés (htop, btop, iotop, curl, git, tmux, lm-sensors, nvme-cli, ethtool) ?"; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        htop btop iotop \
        curl wget git \
        vim nano tmux \
        ethtool net-tools dnsutils \
        lm-sensors smartmontools nvme-cli \
        unzip zip jq
    success "Outils d'administration installés."
fi

# 7. Optimisation de vm.swappiness
if confirm "Voulez-vous réduire le swappiness à 10 (évite d'user les SSD et garde les VM en RAM) ?"; then
    echo "vm.swappiness = 10" > /etc/sysctl.d/99-proxmox-swappiness.conf
    sysctl -p /etc/sysctl.d/99-proxmox-swappiness.conf >/dev/null
    success "Paramètre vm.swappiness configuré à 10."
fi

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}   Post-installation terminée avec succès !                           ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Prochaines étapes recommandées :"
echo -e "  1. Videz le cache de votre navigateur (${YELLOW}Ctrl + F5${NC}) sur https://$(hostname -I | awk '{print $1}'):8006"
echo -e "  2. Activez la double authentification (${YELLOW}2FA / TOTP${NC}) dans Datacenter > Permissions > Two Factor"
echo -e "  3. Si un nouveau noyau Linux a été installé, redémarrez le serveur avec : ${YELLOW}reboot${NC}"
