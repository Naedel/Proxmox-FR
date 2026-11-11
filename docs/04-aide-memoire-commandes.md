# Chapitre 04 : Aide-Mémoire des Commandes CLI & Dépannage

[⬅️ Chapitre précédent : Post-Installation](./03-post-installation.md) | [🏠 Retour à l'accueil](../README.md)

---

Même si 99 % de l'administration quotidienne de Proxmox VE se fait via l'interface Web (`https://IP:8006`), connaître les commandes de base en terminal (**SSH** ou **Shell**) vous permettra de vous dépanner en quelques secondes en cas de blocage.

---

## 📑 Table des matières

1. [Informations système & Versions (`pveversion`)](#1-informations-système--versions-pveversion)
2. [Gestion des Machines Virtuelles KVM (`qm`)](#2-gestion-des-machines-virtuelles-kvm-qm)
3. [Gestion des Conteneurs LXC (`pct`)](#3-gestion-des-conteneurs-lxc-pct)
4. [Gestion du Stockage (`pvesm`, LVM, ZFS)](#4-gestion-du-stockage-pvesm-lvm-zfs)
5. [Services Système Proxmox & Logs](#5-services-système-proxmox--logs)
6. [Procédures de dépannage courantes](#6-procédures-de-dépannage-courantes)

---

## 1. Informations système & Versions (`pveversion`)

| Commande | Description |
| :--- | :--- |
| `pveversion -v` | Affiche la version exacte de Proxmox VE, du noyau Linux et de tous les paquets PVE. |
| `pveperf` | Lance un mini-benchmark rapide du CPU et du disque racine (FSyncs/sec). |
| `sensors` | Affiche les températures du processeur, de la carte mère et des disques NVMe. |
| `lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT` | Affiche l'arbre complet des disques et partitions. |

---

## 2. Gestion des Machines Virtuelles KVM (`qm`)

Dans les exemples ci-dessous, remplacez `100` par l'identifiant (`VMID`) de votre machine virtuelle.

| Commande | Action |
| :--- | :--- |
| `qm list` | Liste toutes les VM du nœud et leur état (`running`, `stopped`). |
| `qm start 100` | Démarre la VM `100`. |
| `qm shutdown 100` | Envoie un signal d'extinction propre (ACPI) à la VM `100`. |
| `qm stop 100` | Coupe brutalement l'alimentation de la VM `100` (équivalent à débrancher la prise). |
| `qm reboot 100` | Redémarre proprement la VM `100`. |
| `qm config 100` | Affiche la configuration complète de la VM (`/etc/pve/qemu-server/100.conf`). |
| `qm unlock 100` | **Déverrouille une VM bloquée** (après une sauvegarde ou un snapshot interrompu). |
| `qm destroy 100 --purge` | Supprime définitivement la VM `100`, ses disques et ses tâches de backup associées. |

---

## 3. Gestion des Conteneurs LXC (`pct`)

Dans les exemples ci-dessous, remplacez `200` par l'identifiant (`CTID`) de votre conteneur LXC.

| Commande | Action |
| :--- | :--- |
| `pct list` | Liste tous les conteneurs LXC présents sur le nœud. |
| `pct start 200` | Démarre le conteneur `200`. |
| `pct shutdown 200` | Éteint proprement le conteneur `200`. |
| `pct stop 200` | Force l'arrêt immédiat du conteneur `200`. |
| `pct enter 200` | **Ouvre directement un shell `root` à l'intérieur du conteneur `200` (sans mot de passe !)** — Tapez `exit` pour en sortir. |
| `pct config 200` | Affiche la configuration du conteneur (`/etc/pve/lxc/200.conf`). |
| `pct unlock 200` | Déverrouille un conteneur bloqué (`lock`). |
| `pveam update && pveam available` | Met à jour et liste tous les templates LXC officiels (Debian, Ubuntu, Alpine, TurnKey...). |

---

## 4. Gestion du Stockage (`pvesm`, LVM, ZFS)

| Commande | Action |
| :--- | :--- |
| `pvesm status` | Affiche l'état et le taux de remplissage de tous les stockages Proxmox. |
| `lvs` / `vgs` / `pvs` | Affiche l'état des volumes logiques LVM et du pool `local-lvm` (`data`). |
| `zpool status -v` | Affiche l'état de santé de vos pools ZFS (`ONLINE`, `DEGRADED`) et les erreurs éventuelles. |
| `zpool list` | Affiche l'espace utilisé et libre sur les pools ZFS. |
| `zfs list` | Liste tous les datasets et volumes ZFS des VM/LXC. |
| `arc_summary` | Affiche les statistiques détaillées du cache RAM ZFS (ARC Hit Ratio). |
| `fstrim -av` | Force un `TRIM` immédiat sur les systèmes de fichiers montés sur SSD. |

---

## 5. Services Système Proxmox & Logs

Si l'interface Web (`:8006`) ne répond plus mais que votre serveur et vos VM fonctionnent toujours en SSH :

```bash
# Redémarrer uniquement le serveur Web de Proxmox (sans couper aucune VM !)
systemctl restart pveproxy.service pvedaemon.service pvestatd.service

# Vérifier l'état du système de fichiers de configuration Proxmox (/etc/pve)
systemctl status pve-cluster.service

# Suivre les journaux système de Proxmox en temps réel
journalctl -f -u pveproxy -u pvedaemon
```

### Emplacement des fichiers de configuration clés sur Proxmox

| Chemin | Contenu |
| :--- | :--- |
| `/etc/pve/` | Système de fichiers virtuel (`pmxcfs`) contenant toute la configuration Proxmox (synchronisé en base SQLite `/var/lib/pve-cluster/config.db`). |
| `/etc/pve/qemu-server/<VMID>.conf` | Fichiers de configuration des machines virtuelles KVM. |
| `/etc/pve/lxc/<CTID>.conf` | Fichiers de configuration des conteneurs LXC. |
| `/etc/pve/storage.cfg` | Configuration de tous les espaces de stockage. |
| `/etc/network/interfaces` | Configuration réseau du serveur hôte (cartes physiques, bridges `vmbr*`, VLANs). |
| `/var/lib/vz/` | Emplacement physique du stockage `local` (`template/iso/` pour les ISO, `dump/` pour les sauvegardes). |

---

## 6. Procédures de dépannage courantes

### A. Comment changer l'adresse IP de son serveur Proxmox après l'installation ?
Si vous changez de box Internet ou de sous-réseau (ex: passer de `192.168.1.200` à `192.168.0.200`), vous devez modifier **3 fichiers** :

1. **`/etc/network/interfaces`** : modifiez `address` et `gateway` sous `iface vmbr0 inet static`.
2. **`/etc/hosts`** : **Très important !** Mettez à jour l'adresse IP associée au nom de votre serveur (`pve.home.arpa pve`). Si `/etc/hosts` contient l'ancienne IP, le service `pve-cluster` refusera de démarrer !
3. **`/etc/resolv.conf`** : mettez à jour l'adresse IP du `nameserver` (DNS).
4. Appliquez sans redémarrer avec :
   ```bash
   ifreload -a
   systemctl restart pve-cluster pveproxy pvedaemon
   ```

### B. Une VM refuse de s'arrêter même avec le bouton « Stop »
Si une VM est totalement gelée et qu'un processus de sauvegarde ou un disque réseau NFS bloqué empêche son arrêt :

```bash
# 1. Déverrouiller la VM (remplacez 100 par le VMID)
qm unlock 100

# 2. Trouver le numéro de processus (PID) du processus KVM de la VM 100 et le tuer proprement
ps aux | grep "/usr/bin/kvm -id 100"
kill -9 <PID>
```

### C. Vous avez oublié le mot de passe d'un conteneur LXC
Pas besoin de réinstaller le conteneur ! Depuis le Shell du serveur hôte Proxmox :

```bash
# Entrer dans le conteneur 200 en tant que root sans mot de passe
pct enter 200

# Changer le mot de passe root du conteneur
passwd
```
