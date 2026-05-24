# Runbook: Node Maintenance

> **Security note:** This runbook contains no real hostnames, IPs, or node-specific details. All topology lives in `.inventory/nodes.yaml` (encrypted, gitignored).

---

## Overview

This runbook covers routine and emergency node maintenance tasks including:

- OS package updates
- Controlled reboots
- mdadm software RAID rebuild
- Disk health monitoring
- Service restarts

---

## Pre-maintenance checklist

Before performing any maintenance on a node:

- [ ] Identify the node in `.inventory/nodes.yaml` and note its role and dependencies
- [ ] Check `services.yaml` for services running on this node that may be impacted
- [ ] Notify dependent services (e.g., pause backup jobs before rebooting a NAS)
- [ ] Verify current disk health with `smartctl`
- [ ] Snapshot or backup if the node hosts stateful data (see [cold-storage-backup.md](cold-storage-backup.md))

---

## OS package updates

```bash
# Update package lists and apply security updates
apt-get update
apt-get upgrade -y

# Apply distribution upgrades (major version bumps — do this cautiously)
# apt-get dist-upgrade -y

# Check for held-back packages
apt-mark showhold
```

> After a kernel update, a reboot is required. Check with:
> ```bash
> needrestart -r a   # or check /run/reboot-required
> ```

---

## Controlled reboot

```bash
# Notify users and schedule a reboot in 5 minutes
shutdown -r +5 "Scheduled maintenance reboot in 5 minutes"

# Cancel if needed
shutdown -c

# Immediate reboot (use only if no users/jobs are active)
# reboot
```

Verify the node comes back up:

```bash
# From another node or monitoring system
ping -c 5 <NODE_IP_FROM_INVENTORY>
ssh <SSH_USER>@<NODE_IP_FROM_INVENTORY> 'uptime; systemctl --failed'
```

---

## mdadm RAID maintenance

### Check RAID status

```bash
cat /proc/mdstat
mdadm --detail /dev/<MD_DEVICE>
```

> Replace `<MD_DEVICE>` with the actual md device name (e.g., `md0`). Do not commit real device names.

### Rebuild a degraded array (replace failed disk)

> ⚠️ **Destructive operation.** Adding the wrong device to an array can cause data loss. Identify the correct new device before running these commands.

1. Identify the failed member:
   ```bash
   mdadm --detail /dev/<MD_DEVICE>
   ```

2. Mark the failed device as removed (if not auto-removed):
   ```bash
   # Requires manual confirmation of the correct device path
   # Example only — substitute the actual failed device:
   # mdadm --manage /dev/<MD_DEVICE> --remove /dev/<FAILED_DISK>
   ```

3. Add the replacement disk:
   ```bash
   # Example only — substitute the actual replacement device:
   # mdadm --manage /dev/<MD_DEVICE> --add /dev/<REPLACEMENT_DISK>
   ```

4. Monitor rebuild progress:
   ```bash
   watch -n 10 cat /proc/mdstat
   ```

5. After rebuild completes, save the new mdadm configuration:
   ```bash
   mdadm --detail --scan >> /etc/mdadm/mdadm.conf
   update-initramfs -u
   ```

### Check disk health

```bash
# Install smartmontools if not present
apt-get install -y smartmontools

# Short self-test
smartctl -t short /dev/<DISK>

# View results after ~2 minutes
smartctl -a /dev/<DISK>
```

---

## Service management

### Check service status

```bash
systemctl list-units --state=failed
journalctl -p err --since "24 hours ago"
```

### Restart a specific service

```bash
systemctl restart <SERVICE_NAME>
systemctl status <SERVICE_NAME>
```

### Drain a service before maintenance

For containerized workloads:

```bash
# Stop new requests from reaching the service
# (implementation depends on load balancer or proxy in use)

# Wait for in-flight requests to drain, then stop
systemctl stop <SERVICE_NAME>
```

---

## Post-maintenance validation

- [ ] `systemctl --failed` returns no units
- [ ] `cat /proc/mdstat` shows all arrays as `[UU]` (no degraded)
- [ ] `df -h` confirms expected filesystems are mounted
- [ ] Services defined in `.inventory/services.yaml` are running
- [ ] Run `./scripts/healthcheck.sh` from the control plane repo
- [ ] Check monitoring dashboard for anomalies (if applicable)

---

## Rollback

- For failed package upgrades: `apt-get install <package>=<previous-version>`
- For failed RAID operations: restore from cold-storage backup (see [cold-storage-backup.md](cold-storage-backup.md))
- For unbootable system: boot from rescue media and mount filesystems to diagnose
