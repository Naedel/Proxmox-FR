# Chapitre 01 : Prérequis Matériels, BIOS/UEFI et Clé USB Bootable

[⬅️ Retour à l'accueil](../README.md) | [Chapitre suivant : Installation de Proxmox VE ➡️](./02-installation-proxmox.md)

---

Avant de lancer l'installation de **Proxmox Virtual Environment (PVE)**, une bonne préparation matérielle et une configuration rigoureuse du **BIOS/UEFI** vous éviteront 90 % des erreurs courantes (impossibilité de démarrer une VM, passthrough PCIe non fonctionnel, usure prématurée des SSD, ou coupures réseau avec les cartes Realtek/Intel).

---

## 📑 Table des matières

1. [Qu'est-ce que Proxmox VE ?](#1-quest-ce-que-proxmox-ve-)
2. [Choisir et dimensionner son matériel](#2-choisir-et-dimensionner-son-matériel)
3. [Préparation du réseau local (Plan d'adressage)](#3-préparation-du-réseau-local-plan-dadressage)
4. [Configuration indispensable du BIOS / UEFI](#4-configuration-indispensable-du-bios--uefi)
5. [Télécharger et vérifier l'image ISO officielle](#5-télécharger-et-vérifier-limage-iso-officielle)
6. [Créer la clé USB bootable](#6-créer-la-clé-usb-bootable)
7. [Checklist avant de passer à l'installation](#7-checklist-avant-de-passer-à-linstallation)

---

## 1. Qu'est-ce que Proxmox VE ?

**Proxmox VE** est un hyperviseur **Bare-Metal (Type 1)** libre et open-source basé sur **Debian GNU/Linux** avec un noyau Linux Ubuntu modifié (`pve-kernel`). Il s'installe directement sur votre machine physique (il écrase tout le disque cible) et combine :

* **KVM (Kernel-based Virtual Machine)** : pour faire tourner des machines virtuelles (VM) complètes et isolées (Windows, Linux, BSD, routeurs OPNsense/pfSense, Home Assistant OS...).
* **LXC (Linux Containers)** : pour faire tourner des conteneurs Linux ultra-légers partageant le noyau de l'hôte (consommation RAM et CPU minimale).
* **Une interface Web complète** (sur le port `8006`), une API REST et des outils en ligne de commande (`qm`, `pct`, `pvesm`).
* **Un support natif du stockage avancé** : LVM-Thin, ZFS, Btrfs, NFS, SMB/CIFS, iSCSI et Ceph.

---

## 2. Choisir et dimensionner son matériel

### Profils de configuration recommandés

| Composant | Minimum officiel (Tests) | Homelab / Mini-PC (Recommandé) | Serveur Avancé / Production |
| :--- | :--- | :--- | :--- |
| **Processeur (CPU)** | 64 bits (Intel EMT64 ou AMD64) avec VT-x/AMD-V | Intel Core i3/i5/N100/N305 ou AMD Ryzen 5 (4 à 8 cœurs) | Intel Xeon / Core i7-i9 ou AMD EPYC / Ryzen 7-9 (8+ cœurs) |
| **Mémoire vive (RAM)** | 2 Go minimum | **16 Go à 32 Go** (DDR4/DDR5) | **64 Go+** (RAM **ECC** vivement recommandée avec ZFS) |
| **Stockage Système (OS)** | 1 disque (SSD/HDD 32 Go+) | SSD SATA ou NVMe de 128 à 256 Go dédié à PVE (ou partagé LVM) | **2x SSD Enterprise en miroir ZFS (RAID 1)** pour l'OS |
| **Stockage VM / LXC** | Partagé sur le disque OS | SSD NVMe de 500 Go à 2 To dédié aux VM/LXC | Pool **ZFS** (Miroir ou RAIDZ) sur SSD avec **PLP** (*Power Loss Protection*) |
| **Carte Réseau (NIC)** | 1x 1 Gbps Ethernet | 1x ou 2x **Intel i210 / i225 / i226** (1 Gbps ou 2.5 Gbps) | 2x 10 Gbps (SFP+ Intel X520/X710 ou Mellanox ConnectX-3/4) + IPMI |

### Points d'attention matériels importants

> [!WARNING]
> **Attention à l'usure des SSD grand public avec ZFS !**
> Proxmox VE écrit en permanence des journaux et des métriques (RRDcached, logs cluster). Sur un système de fichiers **ZFS** avec des SSD grand public d'entrée de gamme (QLC ou sans cache DRAM), l'amplification d'écriture peut user un SSD en quelques mois.
> * **Si vous avez un seul disque ou des SSD grand public** : privilégiez **ext4 (LVM-Thin)** lors de l'installation.
> * **Si vous utilisez ZFS** : privilégiez des SSD à haute endurance (TLC avec DRAM) ou des SSD datacenter dotés de **PLP** (*Power Loss Protection*, ex : Samsung PM883/PM893, Micron 5300/5400, Kingston DC600M, Intel D3-S4510/S4610).

> [!TIP]
> **Cartes réseau : Intel vs Realtek**
> Les contrôleurs **Intel** et **Broadcom/Mellanox** sont reconnus nativement et extrêmement stables sous Debian/Proxmox. Les puces **Realtek** (ex: `RTL8111`/`RTL8125` 2.5GbE) fonctionnent, mais nécessitent parfois le pilote `r8168-dkms` ou `r8125-dkms` en cas de coupures sous forte charge réseau. **Le Wi-Fi n'est pas supporté nativement pour un pont réseau (`vmbr0`)** : connectez toujours votre serveur en câble **Ethernet (RJ45 ou SFP+)**.

---

## 3. Préparation du réseau local (Plan d'adressage)

Contrairement à un PC de bureau, un serveur Proxmox **doit impérativement avoir une adresse IP fixe (statique)** et ne jamais changer d'IP. Avant de démarrer l'installation, notez sur papier les paramètres de votre réseau local (Box Internet ou routeur) :

| Paramètre | Exemple (Box standard) | Votre valeur à noter |
| :--- | :--- | :--- |
| **Sous-réseau / Masque CIDR** | `192.168.1.0/24` (`255.255.255.0`) | `...` |
| **Passerelle (Gateway)** | `192.168.1.1` ou `192.168.1.254` (Freebox) | `...` |
| **Plage DHCP de votre Box** | ex: `192.168.1.10` à `192.168.1.150` | `...` |
| **IP Statique choisie pour Proxmox** | `192.168.1.200/24` *(choisir **hors** de la plage DHCP !)* | `...` |
| **Serveur DNS** | `192.168.1.1` (ou `1.1.1.1` / `9.9.9.9`) | `...` |
| **Nom d'hôte complet (FQDN)** | `pve.home.arpa` ou `proxmox.lan` | `...` |

> [!IMPORTANT]
> Choisissez une adresse IP statique située **en dehors de la plage DHCP** de votre routeur/box Internet (ou créez un bail DHCP statique sur votre routeur en associant l'adresse MAC de votre serveur) afin d'éviter tout conflit d'adresse IP sur votre réseau.

---

## 4. Configuration indispensable du BIOS / UEFI

Branchez un écran et un clavier sur votre serveur, allumez-le et entrez dans le **BIOS/UEFI** (touche `Suppr`, `F2`, `F10` ou `F12` selon le constructeur).

Vérifiez et activez impérativement les options suivantes :

### A. Virtualisation CPU (Obligatoire)
Sans cette option, **aucune machine virtuelle KVM ne pourra démarrer** (`KVM virtualization configured, but not available`).

* **Chez Intel** :
  * Cherchez `Intel Virtualization Technology` ou **`Intel VT-x`** (parfois nommé `VMX`) ➔ **Enabled**
* **Chez AMD** :
  * Cherchez **`SVM Mode`** (*Secure Virtual Machine*) ou `AMD-V` (souvent caché dans *Advanced > CPU Configuration* sur ASUS/MSI/Gigabyte) ➔ **Enabled**

### B. Passthrough PCIe / IOMMU (Fortement recommandé)
Indispensable si vous comptez transmettre directement une carte graphique (GPU), un contrôleur SATA/HBA, une clé USB Zigbee ou une carte réseau directement à une VM.

* **Chez Intel** :
  * **`Intel VT-d`** (*Virtualization Technology for Directed I/O*) ➔ **Enabled**
* **Chez AMD** :
  * **`IOMMU`** (dans *AMD CBS > NBIO Common Options*) ➔ **Enabled** (ne pas laisser sur *Auto*, forcer sur *Enabled*)
* **Options PCIe associées (Intel & AMD)** :
  * **`Above 4G Decoding`** ➔ **Enabled**
  * **`SR-IOV Support`** (si présent) ➔ **Enabled**
  * **`ACS` (Access Control Services)** (si présent) ➔ **Enabled**

### C. Démarrage et Alimentation
* **Mode de démarrage (Boot Mode)** : **`UEFI Only`** (désactivez le mode `Legacy / CSM` sauf sur de très vieux serveurs d'avant 2012).
* **Secure Boot** : **`Disabled`** (Proxmox VE supporte désormais le Secure Boot depuis la version 8.1+, mais le désactiver simplifie l'installation de modules noyau tiers DKMS comme les pilotes NVIDIA ou Realtek).
* **Comportement après coupure de courant** :
  * Cherchez **`Restore on AC/Power Loss`** (ou *AC Back* / *After Power Loss*) ➔ réglez sur **`Power On`** (ou *Last State*). Votre serveur redémarrera tout seul lorsque le courant revient après une coupure électrique.
* **Profil mémoire (XMP / EXPO)** :
  * Pour un serveur stable 24h/24, privilégiez les fréquences JEDEC officielles ou un profil XMP très stable (évitez l'overclocking agressif).

N'oubliez pas de sauvegarder et quitter le BIOS (**`F10` — Save & Exit**).

---

## 5. Télécharger et vérifier l'image ISO officielle

1. Rendez-vous sur la page officielle de téléchargement de Proxmox :
   * 🔗 **https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso**
2. Téléchargez la dernière version de **Proxmox VE ISO Installer** (ex: `proxmox-ve_8.3-1.iso` ou supérieure).
3. **Vérifiez l'intégrité du fichier ISO (Checksum SHA256)** pour être certain que le téléchargement n'est pas corrompu (cause n°1 des erreurs d'installation au milieu de la copie des paquets) :

#### Sous Windows (PowerShell)
```powershell
Get-FileHash .\proxmox-ve_*.iso -Algorithm SHA256
```

#### Sous Linux
```bash
sha256sum proxmox-ve_*.iso
```

#### Sous macOS
```bash
shasum -a 256 proxmox-ve_*.iso
```

Comparez la chaîne obtenue avec la valeur **`SHA256SUM`** affichée sur la page de téléchargement officielle de Proxmox. Elles doivent être strictement identiques.

---

## 6. Créer la clé USB bootable

Munissez-vous d'une clé USB d'au moins **4 Go** (toutes les données présentes sur la clé seront effacées).

### Méthode A : Avec Ventoy (Recommandé — Windows & Linux)
[**Ventoy**](https://www.ventoy.net/) est la solution la plus pratique : vous installez Ventoy une seule fois sur votre clé USB, puis il vous suffit de **copier-coller le fichier `.iso`** directement sur la clé comme un fichier normal !
1. Téléchargez et lancez Ventoy (`Ventoy2Disk`).
2. Dans le menu **Option > Partition Style**, choisissez **GPT** (recommandé pour UEFI).
3. Cliquez sur **Install**.
4. Une fois terminé, copiez simplement votre fichier `proxmox-ve_*.iso` dans la clé USB.
5. *(Note : lors du boot Ventoy, si le mode Normal bloque avec Proxmox, choisissez **Boot in GRUB2 mode**).*

### Méthode B : Avec BalenaEtcher (Windows, macOS, Linux)
1. Téléchargez [**BalenaEtcher**](https://etcher.balena.io/).
2. Cliquez sur **Flash from file** et sélectionnez l'ISO de Proxmox VE.
3. Sélectionnez votre clé USB puis cliquez sur **Flash!**.

### Méthode C : Avec Rufus (Windows uniquement)
1. Téléchargez [**Rufus**](https://rufus.ie/fr/).
2. Sélectionnez votre clé USB et le fichier ISO Proxmox VE.
3. Cliquez sur **Démarrer**.
4. ⚠️ **Très important** : Rufus va afficher une fenêtre vous demandant comment écrire l'image (*Mode ISO* ou *Mode DD*). **Sélectionnez impérativement « Écrire en mode Image DD » (DD Image mode)**, sinon l'installateur Proxmox ne trouvera pas le CD-ROM au démarrage (`No CD-ROM found`).

### Méthode D : En ligne de commande sous Linux / macOS (`dd`)
Identifiez le nom de votre clé USB avec `lsblk` (sous Linux) ou `diskutil list` (sous macOS). **Attention à ne pas vous tromper de disque !**

```bash
# Exemple sous Linux si votre clé USB est /dev/sdX (remplacez sdX par votre clé, sans numéro de partition !)
sudo dd bs=1M conv=fdatasync if=./proxmox-ve_*.iso of=/dev/sdX status=progress
```

---

## 7. Checklist avant de passer à l'installation

Avant de passer au chapitre suivant, vérifiez que toutes les cases sont cochées :

- [ ] Mon serveur est branché en **câble Ethernet** à mon switch ou ma box.
- [ ] J'ai noté mon **adresse IP statique**, mon masque CIDR (`/24`), ma passerelle et mon serveur DNS.
- [ ] J'ai activé **Intel VT-x / VT-d** (ou **AMD SVM / IOMMU**) dans le BIOS.
- [ ] J'ai sauvegardé toutes les données des disques présents dans le serveur (ou débranché temporairement les disques de données que je ne veux pas formater par erreur).
- [ ] Ma clé USB Proxmox VE est prête et son empreinte `SHA256` a été vérifiée.

---

👉 **Tout est prêt ? Passez au [Chapitre 02 : Installation Pas-à-Pas de Proxmox VE](./02-installation-proxmox.md) !**
