# VPS Preparation Script

This script (`preparevps.sh`) automates the setup of a new Ubuntu VPS with a secure user account, SSH hardening, and a Docker-based homelab environment featuring Portainer and Nginx Proxy Manager.

## What This Script Does

1. **User Creation & Security**
   - Creates a new non-root user with sudo privileges
   - Generates an SSH key pair for the user
   - Hardens SSH configuration (disables password auth, root login)
   - Sets up ZSH as the default shell

2. **SSH Key Management**
   - Generates a new ed25519 SSH key pair
   - Displays the private key for you to save locally
   - Configures public key authentication

3. **Homelab Setup**
   - Creates a Docker Compose configuration for:
     - **Portainer** (Docker management UI) - accessible on port 9000
     - **Nginx Proxy Manager** (reverse proxy with SSL) - admin on port 81, proxy on ports 80/443
   - Sets up proper directory structure and permissions

## Prerequisites

- Fresh Ubuntu 20.04/22.04 VPS with root access
- Docker and Docker Compose installed on the VPS
- SSH access to the VPS as root

## Usage

### 1. Upload the script to your VPS

```bash
scp preparevps.sh root@your-vps-ip:/root/
```

### 2. Make it executable and run

```bash
ssh root@your-vps-ip
chmod +x preparevps.sh
./preparevps.sh
```

### 3. Follow the prompts

The script will ask for:
- **Username**: Enter your desired username (lowercase letters, digits, underscores)
- **Password**: Enter and confirm a password for the new user

### 4. Save your SSH private key

The script will display your SSH private key. **Save this immediately** to a secure location on your local machine:

```bash
# Save the displayed key to a file on your local machine
nano ~/.ssh/your-vps-key
chmod 600 ~/.ssh/your-vps-key
```

### 5. Test your new connection

```bash
ssh -i ~/.ssh/your-vps-key username@your-vps-ip
```

### 6. Start your services

Once logged in as the new user:

```bash
cd ~/homelab
docker-compose up -d
```

## Accessing Your Services

- **Portainer**: `http://your-vps-ip:9000`
- **Nginx Proxy Manager**: `http://your-vps-ip:81`
  - Default login: `admin@example.com` / `changeme`

## Testing Locally

Before running on your VPS, you can test the script locally:

```bash
./test_preparevps.sh
```

This validates:
- Script syntax
- SSH key generation
- Docker Compose configuration
- Directory structure creation

## Directory Structure

After running, your VPS will have:

```
/home/username/
├── .ssh/
│   ├── id_ed25519          # Private key
│   ├── id_ed25519.pub      # Public key
│   └── authorized_keys     # Authorized public keys
├── .config/                # User configuration directory
└── homelab/
    ├── docker-compose.yml  # Main compose file
    ├── portainer/          # Portainer data
    └── nginx-proxy-manager/
        ├── data/           # NPM configuration
        └── letsencrypt/    # SSL certificates
```

## Security Features

- Password authentication disabled for SSH
- Root login disabled
- SSH keys required for access
- Non-root user with sudo privileges
- Proper file permissions set

## Troubleshooting

### SSH Connection Issues
- Ensure you saved the private key correctly
- Check file permissions: `chmod 600 ~/.ssh/your-key`
- Verify the username and IP address

### Docker Issues
- Ensure Docker and Docker Compose are installed on your VPS
- Check if the user is in the docker group: `groups $USER`

### Service Access Issues
- Check if services are running: `docker-compose ps`
- Verify firewall settings allow the required ports
- Ensure the VPS IP is correct

## Manual Cleanup

If you need to remove the test environment:

```bash
rm -rf test_env/
```

## Security Notes

- **Save your SSH private key securely** - this is your only way to access the server
- Change default passwords for Nginx Proxy Manager immediately
- Consider setting up a firewall (ufw) after initial setup
- Regularly update your system: `sudo apt update && sudo apt upgrade`

## Support

This script is designed for Ubuntu 20.04/22.04 but should work on most systemd-based distributions with minor modifications.