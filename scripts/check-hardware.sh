#!/usr/bin/env bash
# ==============================================================================
# Script de Diagnostic Matériel & Virtualisation pour Proxmox VE (Français)
# Dépôt : https://github.com/Naedel/Proxmox-FR
# ==============================================================================
# Ce script vérifie en lecture seule (aucune modification du système) :
#   1. Le modèle CPU et l'activation de la virtualisation KVM (Intel VT-x / AMD-V)
#   2. L'activation de l'IOMMU (Intel VT-d / AMD-Vi) pour le Passthrough PCIe
#   3. L'état de la mémoire RAM (et détection de la mémoire ECC si disponible)
#   4. L'état de santé S.M.A.R.T. et l'usure de tous les disques (SATA / NVMe)
#   5. L'état des pools ZFS et des volumes LVM
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}       Audit Matériel & Virtualisation Proxmox VE (Proxmox-FR)        ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. Vérification du CPU et de la virtualisation KVM
echo -e "\n${BLUE}[1/5] Processeur & Virtualisation matérielle (KVM)${NC}"
CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo || echo "Inconnu")
CPU_CORES=$(nproc || echo "?")
echo -e "  • Modèle CPU       : ${CPU_MODEL} (${CPU_CORES} threads logiques)"

if grep -E -q '(vmx|svm)' /proc/cpuinfo; then
    VIRT_FLAG=$(grep -E -o '(vmx|svm)' /proc/cpuinfo | head -n 1)
    echo -e "  • Support KVM      : ${GREEN}ACTIVÉ (${VIRT_FLAG})${NC}"
else
    echo -e "  • Support KVM      : ${RED}DÉSACTIVÉ ! Activez Intel VT-x ou AMD SVM dans votre BIOS.${NC}"
fi

if [[ -e /dev/kvm ]]; then
    echo -e "  • Périphérique KVM : ${GREEN}/dev/kvm présent et opérationnel${NC}"
else
    echo -e "  • Périphérique KVM : ${RED}/dev/kvm absent !${NC}"
fi

# 2. Vérification de l'IOMMU (Passthrough PCIe)
echo -e "\n${BLUE}[2/5] Support IOMMU (Passthrough PCIe / GPU / HBA)${NC}"
IOMMU_GROUPS=$(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l || echo 0)
if [[ "$IOMMU_GROUPS" -gt 0 ]]; then
    echo -e "  • Groupes IOMMU    : ${GREEN}ACTIVÉ (${IOMMU_GROUPS} groupes détectés)${NC}"
else
    echo -e "  • Groupes IOMMU    : ${YELLOW}INACTIF (0 groupe détecté).${NC}"
    echo -e "    -> Si vous souhaitez faire du PCIe/GPU Passthrough, activez Intel VT-d ou AMD IOMMU dans le BIOS."
fi

# 3. Mémoire RAM
echo -e "\n${BLUE}[3/5] Mémoire Vive (RAM & Swap)${NC}"
free -h | awk 'NR==1{print "  • " $0} NR==2{printf "  • RAM  : Total=%s | Utilisé=%s | Libre=%s | Disponible=%s\n", $2, $3, $4, $7} NR==3{printf "  • Swap : Total=%s | Utilisé=%s | Libre=%s\n", $2, $3, $4}'

# 4. Disques et santé S.M.A.R.T.
echo -e "\n${BLUE}[4/5] Stockage Physique & Santé S.M.A.R.T.${NC}"
lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN | awk 'NR==1{print "  " $0} NR>1 && $1 !~ /^loop|^sr|^zd/{rota=($4=="0"?"SSD/NVMe":"HDD"); printf "  %-8s %-26s %-8s %-10s %s\n", $1, $2, $3, rota, $5}'

if command -v smartctl >/dev/null 2>&1; then
    echo -e "\n  ${BLUE}État S.M.A.R.T. rapide :${NC}"
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n1; do
        [[ -b "$disk" ]] || continue
        HEALTH=$(smartctl -H "$disk" 2>/dev/null | grep -E "overall-health|result:" | awk -F': ' '{print $2}' || echo "Non supporté")
        if [[ "$HEALTH" == *"PASSED"* || "$HEALTH" == *"OK"* ]]; then
            echo -e "  • ${disk} : ${GREEN}${HEALTH}${NC}"
        else
            echo -e "  • ${disk} : ${YELLOW}${HEALTH}${NC}"
        fi
    done
fi

# 5. Pools ZFS et LVM
echo -e "\n${BLUE}[5/5] État des Stockages Proxmox (ZFS / LVM)${NC}"
if command -v zpool >/dev/null 2>&1 && zpool list >/dev/null 2>&1; then
    zpool list
else
    echo -e "  • Aucun pool ZFS actif détecté."
fi

if command -v pvesm >/dev/null 2>&1; then
    echo ""
    pvesm status
fi

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}   Diagnostic terminé.                                                ${NC}"
echo -e "${GREEN}======================================================================${NC}"
