#!/bin/bash
set -e

STUDENT_NAME="Matt Slaunwhite"
BOB_PASS="Password123!"

echo "[+] Starting configuration for Steps 4 - 8..."

# ==============================================================================
# Step 4: Storage Configuration on /dev/sdb
# ==============================================================================
echo "[+] Step 4: Partitioning /dev/sdb..."
parted -s /dev/sdb mklabel msdos
parted -s /dev/sdb mkpart primary ext4 1MiB 30721MiB
parted -s /dev/sdb mkpart primary xfs 30721MiB 100%
udevadm settle

mkfs.ext4 -F /dev/sdb1
mkfs.xfs -f /dev/sdb2

mkdir -p /data1 /data2
mount /dev/sdb1 /data1
mount /dev/sdb2 /data2

UUID1=$(blkid -s UUID -o value /dev/sdb1)
UUID2=$(blkid -s UUID -o value /dev/sdb2)

sed -i '/\/data1/d' /etc/fstab
sed -i '/\/data2/d' /etc/fstab

echo "UUID=$UUID1 /data1 ext4 defaults 0 2" >> /etc/fstab
echo "UUID=$UUID2 /data2 xfs defaults 0 0" >> /etc/fstab

# Copy /etc/ssh to /data2
cp -a /etc/ssh /data2/

# ==============================================================================
# Step 5: Shell, File, Git, User, and Cron Operations
# ==============================================================================
echo "[+] Step 5: Git repo, files, user bob, and cron..."
mkdir -p /data1/gitstuff
cd /data1/gitstuff
git init
git config --global user.name "$STUDENT_NAME"
git config --global user.email "matt@slaunwhite.com"

# Baseline stats and file searches
vmstat > /data1/gitstuff/baseline.txt
find / -name "sshd_config" > /data1/gitstuff/sshconfigs.txt 2>/dev/null

# Capture Bluetooth entries from journal
journalctl -p err..emerg | grep -i "bluetooth" > /data1/gitstuff/bluetooth.txt || true
if [ ! -s /data1/gitstuff/bluetooth.txt ]; then
    journalctl | grep -i "bluetooth" > /data1/gitstuff/bluetooth.txt || true
fi

# Git Commit 1
git add .
git commit -m "Commit 1"

# Append line and Git Commit 2
echo "New line added by $STUDENT_NAME" >> /data1/gitstuff/sshconfigs.txt
git add sshconfigs.txt
git commit -m "Commit 2"

# Alias cls in ~/.bashrc for root and woot
grep -q "alias cls=" /root/.bashrc || echo "alias cls='clear'" >> /root/.bashrc
if [ -d "/home/woot" ]; then
    grep -q "alias cls=" /home/woot/.bashrc || echo "alias cls='clear'" >> /home/woot/.bashrc
fi

# Tar backup and Friday 9:45 PM cron entry
tar -czf /gitstuff-backup.tar.gz -C /data1 gitstuff
crontab -l 2>/dev/null | grep -v "/gitstuff-backup.tar.gz" > /tmp/cron.tmp || true
echo "45 21 * * 5 tar -czf /gitstuff-backup.tar.gz -C /data1 gitstuff" >> /tmp/cron.tmp
crontab /tmp/cron.tmp
rm -f /tmp/cron.tmp

# User bob configuration, permissions, and append-only attribute
if ! id "bob" &>/dev/null; then
    useradd -G wheel bob
else
    usermod -aG wheel bob
fi
echo "bob:$BOB_PASS" | chpasswd

chown bob:bob /data1/gitstuff/bluetooth.txt
chmod 400 /data1/gitstuff/bluetooth.txt
chattr +a /data1/gitstuff/bluetooth.txt

# ==============================================================================
# Step 6: SSH Daemon Configuration
# ==============================================================================
echo "[+] Step 6: Enabling OpenSSH..."
systemctl enable --now sshd
mkdir -p /etc/ssh/sshd_config.d
echo "PermitRootLogin yes" > /etc/ssh/sshd_config.d/01-permitroot.conf
systemctl restart sshd

firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# ==============================================================================
# Step 7: Apache Web Server
# ==============================================================================
echo "[+] Step 7: Setting up Apache..."
dnf install -y httpd mod_ssl
systemctl enable --now httpd
echo "Default Apache Page from $STUDENT_NAME" > /var/www/html/index.html
chmod 644 /var/www/html/index.html

firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# ==============================================================================
# Step 8: Very Secure FTP Daemon (vsftpd)
# ==============================================================================
echo "[+] Step 8: Configuring vsftpd..."
dnf install -y vsftpd
sed -i 's/^anonymous_enable=NO/anonymous_enable=YES/' /etc/vsftpd/vsftpd.conf
grep -q "^anonymous_enable" /etc/vsftpd/vsftpd.conf || echo "anonymous_enable=YES" >> /etc/vsftpd/vsftpd.conf

systemctl enable --now vsftpd
systemctl restart vsftpd
setsebool -P ftpd_full_access 1 2>/dev/null || true

firewall-cmd --permanent --add-service=ftp
firewall-cmd --reload

echo "[SUCCESS] Configuration script completed!"
