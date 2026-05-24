# Runbook: Windows-to-Debian Workstation Conversion

> **Security note:** This runbook contains no hostnames, IPs, usernames, or hardware serial numbers. All site-specific details live in `.inventory/nodes.yaml` (encrypted, gitignored).

---

## Overview

This runbook describes the high-level process for converting a Windows workstation to Debian Linux. It covers pre-migration checklist, installation, post-install hardening, and validation steps.

---

## Pre-migration checklist

Before touching any disk or running any installer:

- [ ] Confirm the target node name and role in `.inventory/nodes.yaml`
- [ ] Back up all user data to cold storage (see [cold-storage-backup.md](cold-storage-backup.md))
- [ ] Record current Windows product key if needed for future reference (store encrypted, not in this repo)
- [ ] Note BIOS/UEFI settings: Secure Boot state, TPM version, SATA mode (AHCI vs RAID)
- [ ] Download the latest Debian stable netinstall ISO from [debian.org/distrib](https://www.debian.org/distrib/)
- [ ] Verify the ISO SHA512 checksum against the official release file
- [ ] Create bootable installation media (USB)

> ⚠️ **The next steps are destructive.** All data on the target disk will be erased. Confirm backups are complete and verified before proceeding.

---

## BIOS / UEFI preparation

1. Enter BIOS/UEFI setup (key varies by vendor — consult hardware docs)
2. Set storage controller to **AHCI** mode if currently in Intel RST or RAID mode
3. Disable **Secure Boot** temporarily during installation (can be re-enabled after enrolling Debian keys)
4. Enable **boot from USB**
5. Optionally enable **TPM** for future LUKS/FIDO2 integration

---

## Debian installation

### Disk partitioning (example layout)

> Replace device paths with actual device names shown in the installer.  
> Do not commit real device names to this file.

| Partition | Mount point | Filesystem | Size      | Notes                          |
|-----------|-------------|------------|-----------|--------------------------------|
| EFI       | `/boot/efi` | FAT32      | 512 MiB   | Required for UEFI boot         |
| Boot      | `/boot`     | ext4       | 1 GiB     | Separate from EFI              |
| Root      | `/`         | ext4/btrfs | 40+ GiB   | OS and applications            |
| Swap      | swap        | swap       | RAM size  | Or use a swapfile post-install |
| Home      | `/home`     | ext4/btrfs | Remaining | User data                      |

> ⚠️ Disk partitioning is destructive. Double-check the target device is correct before confirming any write operation.

### Installation steps

1. Boot from USB
2. Select **Graphical Install** or **Install**
3. Choose language, locale, keyboard
4. Configure network (use DHCP initially; set static IP post-install via `.inventory/`)
5. Partition disks per layout above
6. Install base system, select **SSH server** and **standard system utilities** only (no desktop environment if headless)
7. Install GRUB to the EFI partition

---

## Post-installation hardening

### Networking

- Set hostname to match the value in `.inventory/nodes.yaml`  
  ```bash
  hostnamectl set-hostname <NODE_NAME>
  ```
- Configure static IP per `.inventory/nodes.yaml`  
  Edit `/etc/network/interfaces` or use NetworkManager with a config file  
  **Do not commit the config file containing real IPs**

### SSH hardening

```bash
# Disable password authentication, enable key-only login
# Edit /etc/ssh/sshd_config:
#   PasswordAuthentication no
#   PermitRootLogin no
#   AllowUsers <SSH_USER>
systemctl restart ssh
```

### Automatic security updates

```bash
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

### Firewall (ufw example)

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw enable
```

---

## Validation

- [ ] SSH login works from another node using key authentication
- [ ] `systemd-analyze` shows no failed units
- [ ] `df -h` confirms partitions are mounted correctly
- [ ] Internet connectivity confirmed (`ping -c3 1.1.1.1`)
- [ ] DNS resolution works (`dig debian.org`)
- [ ] Hostname matches `.inventory/nodes.yaml`
- [ ] Run `./scripts/healthcheck.sh` from the control plane repo

---

## Rollback

If the installation fails or the system is not bootable:

1. Boot from the Debian live USB
2. Mount the EFI partition and re-run `grub-install` if needed
3. If disk is unrecoverable, restore from cold-storage backup (see [cold-storage-backup.md](cold-storage-backup.md))
