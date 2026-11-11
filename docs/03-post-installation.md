# Chapitre 03 : Post-Installation Essentielle & Sécurisation

[⬅️ Chapitre précédent : Installation de Proxmox](./02-installation-proxmox.md) | [🏠 Accueil](../README.md) | [Chapitre suivant : Aide-Mémoire CLI ➡️](./04-aide-memoire-commandes.md)

---

> [!IMPORTANT]
> **Pourquoi la post-installation est-elle obligatoire sur Proxmox VE ?**
> Par défaut, une installation fraîche de Proxmox VE est configurée avec les dépôts **`pve-enterprise`** (réservés aux entreprises disposant d'une licence payante).
> **Si vous ne modifiez pas les dépôts, les mises à jour échoueront avec une erreur `401 Unauthorized` et votre serveur ne recevra aucun correctif de sécurité !**

Ce chapitre vous explique comment réaliser la post-installation **automatiquement via notre script**, ou **étape par étape (via l'interface Web ou en ligne de commande)** pour comprendre exactement ce qui est fait.

---

## 📑 Table des matières

1. [Option Rapide : Script de post-installation automatisé](#1-option-rapide--script-de-post-installation-automatisé)
2. [Étape 1 : Configurer les dépôts APT (`no-subscription`)](#2-étape-1--configurer-les-dépôts-apt-no-subscription)
3. [Étape 2 : Supprimer la popup « Pas d'abonnement valide » (Nag Screen)](#3-étape-2--supprimer-la-popup--pas-dabonnement-valide--nag-screen)
4. [Étape 3 : Mettre à jour complètement Proxmox VE](#4-étape-3--mettre-à-jour-complètement-proxmox-ve)
5. [Étape 4 : Installer le Microcode CPU (Intel / AMD) et les outils utiles](#5-étape-4--installer-le-microcode-cpu-intel--amd-et-les-outils-utiles)
6. [Étape 5 : Sécuriser l'accès (2FA/TOTP, Clés SSH, Fail2ban)](#6-étape-5--sécuriser-laccès-2fatotp-clés-ssh-fail2ban)
7. [Étape 6 : Activer la surveillance des disques (S.M.A.R.T.) et les alertes Mail](#7-étape-6--activer-la-surveillance-des-disques-smart-et-les-alertes-mail)
8. [Étape 7 : Optimisations recommandées (ZFS ARC, Swappiness, Gouverneur CPU)](#8-étape-7--optimisations-recommandées-zfs-arc-swappiness-gouverneur-cpu)

---

## 1. Option Rapide : Script de post-installation automatisé

Si vous souhaitez automatiser les étapes **1 à 5** proprement, ce dépôt met à votre disposition le script commenté [`scripts/post-install.sh`](../scripts/post-install.sh).

Ouvrez le **Shell** de votre nœud Proxmox (ou connectez-vous en SSH `ssh root@IP_PROXMOX`) et exécutez :

```bash
curl -fsSL https://raw.githubusercontent.com/Naedel/Proxmox-FR/main/scripts/post-install.sh -o post-install.sh
chmod +x post-install.sh
./post-install.sh
```

Vous préférez tout faire vous-même ou via l'interface graphique ? Suivez les étapes détaillées ci-dessous !

---

## 2. Étape 1 : Configurer les dépôts APT (`no-subscription`)

Proxmox propose 3 niveaux de dépôts officiels :
* **`pve-enterprise`** : activé par défaut, nécessite une clé d'abonnement payante (renvoie une erreur `401 Unauthorized` sans licence).
* **`pve-no-subscription`** : **gratuit, officiel et stable** pour un Homelab, des projets personnels ou de la PME sans contrat de support.
* **`pvetest`** : dépôt bêta pour les développeurs (à ne jamais activer sur un serveur principal).

### Méthode A : Via l'interface Web (100 % Graphique)

1. Dans la colonne de gauche, cliquez sur le nom de votre nœud (ex: **`pve`**).
2. Déroulez le menu **`Mises à jour` (*Updates*)** ➔ cliquez sur **`Dépôts` (*Repositories*)**.
3. **Désactivez les 2 dépôts Enterprise** :
   * Cliquez sur la ligne `https://enterprise.proxmox.com/debian/pve` ➔ cliquez sur le bouton **`Désactiver` (*Disable*)** en haut.
   * Cliquez sur la ligne `https://enterprise.proxmox.com/debian/ceph-quincy` (ou `ceph-reef`/`ceph-squid`) ➔ cliquez sur **`Désactiver` (*Disable*)**.
4. **Ajoutez les dépôts gratuits (`No-Subscription`)** :
   * Cliquez sur le bouton **`Ajouter` (*Add*)** en haut.
   * Dans la liste déroulante *Dépôt*, sélectionnez **`No-Subscription`** ➔ cliquez sur **`Ajouter`**.
   * Cliquez à nouveau sur **`Ajouter`**, sélectionnez **`Ceph Squid No-Subscription`** (ou **`Ceph Reef No-Subscription`** selon votre version) ➔ cliquez sur **`Ajouter`**.

### Méthode B : En ligne de commande (SSH / Shell)

Sous **Proxmox VE 8.x (Debian 12 Bookworm)** :

```bash
# 1. Désactiver les dépôts payants (Enterprise PVE et Ceph)
sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/ceph.list 2>/dev/null || true

# 2. Ajouter les dépôts gratuits pve-no-subscription et ceph-no-subscription
cat << 'EOF' > /etc/apt/sources.list.d/pve-no-subscription.list
# Dépôt officiel Proxmox VE gratuit (No-Subscription)
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF

cat << 'EOF' > /etc/apt/sources.list.d/ceph-no-subscription.list
# Dépôt officiel Ceph gratuit (No-Subscription)
deb http://download.proxmox.com/debian/ceph-squid bookworm no-subscription
EOF

# 3. Activer non-free-firmware dans les dépôts Debian (utile pour le microcode CPU)
sed -i 's/main contrib$/main contrib non-free-firmware/g' /etc/apt/sources.list
```

*(Note : Des modèles au format moderne DEB822 `.sources` compatibles Proxmox 8.x / 9.x sont également disponibles dans [`configs/apt/`](../configs/apt/)).*

---

## 3. Étape 2 : Supprimer la popup « Pas d'abonnement valide » (Nag Screen)

À chaque connexion à l'interface Web, Proxmox affiche une fenêtre d'avertissement `No valid subscription`.
Pour la désactiver de manière **persistante** (même après les futures mises à jour du paquet `proxmox-widget-toolkit`), créez un *hook* `dpkg` automatique :

```bash
cat << 'EOF' > /etc/apt/apt.conf.d/no-nag-script
DPkg::Post-Invoke { "dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ $? -eq 1 ]; then { echo 'Patching nag screen...'; sed -i '/.*data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi"; };
EOF

# Appliquer immédiatement le correctif en réinstallant le paquet UI
apt-get --reinstall install -y proxmox-widget-toolkit
systemctl restart pveproxy.service
```

> [!TIP]
> Après avoir exécuté cette commande, **videz le cache de votre navigateur** avec **`Ctrl + F5`** (ou `Cmd + Shift + R` sur Mac) et reconnectez-vous : la boîte de dialogue a disparu !

---

## 4. Étape 3 : Mettre à jour complètement Proxmox VE

> [!CAUTION]
> **Règle d'or sous Proxmox VE : N'utilisez JAMAIS `apt upgrade` !**
> Utilisez toujours **`apt dist-upgrade`** ou **`apt full-upgrade`** (ou le bouton *Mettre à niveau* de l'interface Web). En effet, `apt upgrade` refuse d'installer les nouveaux noyaux Linux (`proxmox-kernel-*`) ou les nouvelles dépendances de paquets Proxmox, ce qui peut casser votre système en laissant des paquets à moitié mis à jour.

En ligne de commande :

```bash
apt-get update && apt-get full-upgrade -y
```

Si un nouveau noyau Linux (`proxmox-kernel-6.8...`) a été installé pendant la mise à jour, **redémarrez le serveur** pour l'activer :

```bash
reboot
```

---

## 5. Étape 4 : Installer le Microcode CPU (Intel / AMD) et les outils utiles

### A. Pourquoi installer le microcode CPU ?
Les constructeurs **Intel** et **AMD** publient régulièrement des correctifs de stabilité et de sécurité pour les processeurs (le *microcode*). Sur certains mini-PC récents (Intel N100/N305, Core 12e/13e/14e gén., AMD Ryzen), installer le dernier microcode corrige des crashs aléatoires de VM (*kernel panic*).

```bash
# S'assurer que non-free-firmware est actif puis mettre à jour la liste
apt-get update

# Détection automatique du CPU et installation du microcode correspondant
if grep -q "GenuineIntel" /proc/cpuinfo; then
    apt-get install -y intel-microcode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    apt-get install -y amd64-microcode
fi
```

### B. Outils d'administration indispensables en CLI
Installez quelques utilitaires légers très précieux au quotidien :

```bash
apt-get install -y \
    htop btop iotop \
    curl wget git \
    vim nano \
    tmux \
    ethtool net-tools dnsutils iperf3 \
    lm-sensors smartmontools nvme-cli \
    unzip zip jq
```

---

## 6. Étape 5 : Sécuriser l'accès (2FA/TOTP, Clés SSH, Fail2ban)

### A. Activer la Double Authentification (2FA / TOTP) sur l'interface Web
Protégez immédiatement votre compte `root@pam` avec une application d'authentification (Aegis, Bitwarden, Ente Auth, Google Authenticator) ou une clé physique **YubiKey (WebAuthn)** :

1. Dans l'interface Web Proxmox, cliquez sur **`Datacenter`** (tout en haut à gauche).
2. Allez dans **`Permissions`** ➔ **`Authentification à deux facteurs` (*Two Factor*)**.
3. Cliquez sur **`Ajouter` (*Add*)** ➔ **`TOTP`**.
4. Sélectionnez l'utilisateur `root@pam`, scannez le **QR Code** avec votre téléphone, saisissez le code à 6 chiffres et validez.
5. **Important** : Cliquez à nouveau sur **`Ajouter`** ➔ **`Clés de récupération` (*Recovery Keys*)** et sauvegardez précieusement les codes de secours dans votre gestionnaire de mots de passe au cas où vous perdriez votre téléphone !

### B. Authentification SSH par clé cryptographique (`Ed25519`)
Sur votre **ordinateur personnel** (Windows PowerShell, macOS ou Linux), générez une clé SSH si vous n'en avez pas encore :

```bash
# Sur votre ordinateur personnel :
ssh-keygen -t ed25519 -C "admin-proxmox"

# Envoyer votre clé publique sur le serveur Proxmox :
ssh-copy-id root@192.168.1.200
```

Une fois que vous avez vérifié que `ssh root@192.168.1.200` vous connecte **sans vous demander de mot de passe**, vous pouvez désactiver l'authentification SSH par mot de passe sur le serveur Proxmox :

```bash
# Sur le serveur Proxmox (uniquement après avoir testé votre clé SSH !) :
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload sshd
```
*(Note : cela ne bloque pas la connexion par mot de passe sur l'interface Web `:8006` ni sur l'écran physique branché au serveur, uniquement le protocole SSH port 22).*

### C. Protéger l'interface Web (port 8006) et SSH avec Fail2ban
**Fail2ban** bannit automatiquement toute adresse IP qui échoue plusieurs fois à se connecter sur le port `8006` (Web UI) ou `22` (SSH).

```bash
# 1. Installer Fail2ban et rsyslog / systemd-journal
apt-get install -y fail2ban

# 2. Copier la configuration Fail2ban fournie dans ce dépôt
cp configs/security/fail2ban-filter-proxmox.conf /etc/fail2ban/filter.d/proxmox.conf
cp configs/security/fail2ban-jail-proxmox.local /etc/fail2ban/jail.d/proxmox.local

# 3. Redémarrer Fail2ban et vérifier l'état de la prison proxmox
systemctl enable --now fail2ban
systemctl restart fail2ban
fail2ban-client status proxmox
```

---

## 7. Étape 6 : Activer la surveillance des disques (S.M.A.R.T.) et les alertes Mail

### A. Surveillance S.M.A.R.T. des SSD et disques durs
Par défaut, le démon `smartd` est installé sur Proxmox. Vérifiez qu'il est bien actif et que tous vos disques passent le test de santé :

```bash
systemctl status smartmontools

# Tester notre script d'audit matériel qui affiche l'état S.M.A.R.T. et l'usure de tous vos disques :
bash scripts/check-hardware.sh
```

Vous pouvez aussi voir l'état d'usure (*Wearout*) de vos SSD directement dans l'interface Web : **`Nœud (pve)`** ➔ **`Disques` (*Disks*)**.

### B. Configurer les notifications par e-mail (SMTP depuis Proxmox VE 8.1+)
Depuis Proxmox VE 8.1, plus besoin de configurer `Postfix` en ligne de commande ! Tout se fait dans l'interface graphique :

1. Allez dans **`Datacenter`** ➔ **`Notifications`**.
2. Dans la section **`Cibles de notification` (*Notification Targets*)**, cliquez sur **`Ajouter` ➔ `SMTP`**.
3. Remplissez les paramètres de votre fournisseur mail (ex: Gmail avec un *Mot de passe d'application*, Infomaniak, ProtonMail Bridge, OVH...) :
   * **Nom de la cible** : `mon-smtp`
   * **Serveur** : ex: `smtp.gmail.com` (Port `465` avec `TLS` ou `587` avec `STARTTLS`)
   * **Utilisateur / Mot de passe** : vos identifiants SMTP
   * **Destinataire(s)** : `root@pam`
4. Sélectionnez votre nouvelle cible `mon-smtp` et cliquez sur **`Tester` (*Test*)** en haut pour recevoir immédiatement un e-mail de test !
5. Dans **` Notification Matchers`** en bas, modifiez **`default-matcher`** pour qu'il utilise votre cible `mon-smtp` au lieu de `mail-to-root` (Postfix local).

---

## 8. Étape 7 : Optimisations recommandées (ZFS ARC, Swappiness, Gouverneur CPU)

### A. Réduire l'utilisation du Swap (`vm.swappiness`)
Par défaut sous Linux, `vm.swappiness` vaut `60`, ce qui pousse le noyau à écrire sur le disque Swap même quand il reste beaucoup de RAM libre (ce qui ralentit les VM et use les SSD). Réduisez cette valeur à `10` :

```bash
echo "vm.swappiness = 10" > /etc/sysctl.d/99-proxmox-swappiness.conf
sysctl -p /etc/sysctl.d/99-proxmox-swappiness.conf
```

### B. Limiter la RAM utilisée par ZFS (ARC Max) — *Uniquement si vous utilisez ZFS*
Si vous utilisez ZFS et voulez ajuster la limite maximale de RAM utilisée par son cache ARC (par exemple à **4 Go** sur un serveur de 16/32 Go de RAM, ou **8 Go** sur un serveur de 64 Go) :

```bash
# Exemple pour limiter l'ARC ZFS à 4 Go (4 * 1024 * 1024 * 1024 = 4294967296 octets)
echo "options zfs zfs_arc_max=4294967296" > /etc/modprobe.d/zfs.conf

# Mettre à jour l'initramfs pour appliquer au démarrage
update-initramfs -u -k all
```

### C. Synchronisation horaire précise (`chrony`)
Un serveur de virtualisation (et a fortiori l'authentification TOTP 2FA ou un cluster) a besoin d'une horloge précise à la milliseconde près. Proxmox utilise **`chrony`** par défaut. Vérifiez qu'il est bien synchronisé :

```bash
chronyc tracking
chronyc sources -v
```

---

🎉 **Félicitations ! Votre serveur Proxmox VE est désormais proprement installé, à jour, sécurisé et optimisé.**
Consultez le [Chapitre 04 : Aide-Mémoire CLI & Dépannage](./04-aide-memoire-commandes.md) pour garder sous la main toutes les commandes utiles au quotidien.
