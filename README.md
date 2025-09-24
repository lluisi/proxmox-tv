# IPTVnator Proxmox Container Setup

Simple, reliable two-script approach to set up IPTVnator in a Proxmox LXC container.

## Quick Start

### Step 1: Create Debian Container
```bash
# Download and run the container creation script
curl -fsSL https://raw.githubusercontent.com/lluisi/proxmox-tv/main/create-debian-ct.sh | bash

# Or with specific container ID
curl -fsSL https://raw.githubusercontent.com/lluisi/proxmox-tv/main/create-debian-ct.sh | bash -s 200
```

### Step 2: Install IPTVnator
```bash
# Replace 139 with your container ID from step 1
curl -fsSL https://raw.githubusercontent.com/lluisi/proxmox-tv/main/install-iptvnator.sh | bash -s 139
```

## Manual Usage

If you prefer to download the scripts locally:

```bash
# Download scripts
wget https://raw.githubusercontent.com/lluisi/proxmox-tv/main/create-debian-ct.sh
wget https://raw.githubusercontent.com/lluisi/proxmox-tv/main/install-iptvnator.sh
chmod +x *.sh

# Step 1: Create container
./create-debian-ct.sh [container-id]

# Step 2: Install IPTVnator
./install-iptvnator.sh [container-id]
```

## What Each Script Does

### create-debian-ct.sh
- Finds available Debian 12 template (local or downloads one)
- Creates LXC container with proper Docker support
- Configures networking and basic settings
- Starts the container and waits for network

### install-iptvnator.sh
- Updates the container OS
- Installs Docker and Docker Compose
- Sets up IPTVnator with docker-compose.yml
- Starts the services
- Provides access URLs

## Access IPTVnator

After installation, access IPTVnator at:
- **Frontend**: `http://[container-ip]:4333`
- **Backend**: `http://[container-ip]:7333`

## Container Management

```bash
# View logs
pct exec [container-id] -- docker compose -f /opt/iptvnator/compose.yml logs

# Restart services
pct exec [container-id] -- docker compose -f /opt/iptvnator/compose.yml restart

# Stop services
pct exec [container-id] -- docker compose -f /opt/iptvnator/compose.yml stop

# Start services
pct exec [container-id] -- docker compose -f /opt/iptvnator/compose.yml start
```

## Container Specifications

- **OS**: Debian 12
- **Memory**: 2048MB
- **CPU**: 1 core
- **Disk**: 15GB
- **Features**: Docker support (nesting=1, keyctl=1)
- **Network**: DHCP on vmbr0

## Troubleshooting

### Container Creation Issues
- Ensure you're running on a Proxmox VE host
- Check that the container ID isn't already in use
- Verify storage has enough space

### Installation Issues
- Make sure the container is running: `pct status [container-id]`
- Check container logs: `pct exec [container-id] -- journalctl -f`
- Verify internet connectivity from container

### Service Issues
- Check Docker status: `pct exec [container-id] -- systemctl status docker`
- View service logs: `pct exec [container-id] -- docker compose -f /opt/iptvnator/compose.yml logs`