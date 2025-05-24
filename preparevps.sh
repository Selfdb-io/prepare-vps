#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-user.sh — Interactive helper to create a non-root sudo user,
#                  harden SSH, and migrate root SSH keys.
#
# Works on modern Ubuntu (20.04/22.04) but should be portable to most
# systemd-based Linux distributions that ship OpenSSH and use /etc/ssh/sshd_config.
# -----------------------------------------------------------------------------

# ----------------------------------------------------------------------
#  Safety rails
# ----------------------------------------------------------------------
set -euo pipefail
# -e  : exit immediately on non-zero status
# -u  : treat unset variables as errors
# -o pipefail : fail a pipeline if any component command fails

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -yq zsh

ZSH_BIN="$(command -v zsh || true)"

# Add zsh to /etc/shells if missing
if [[ -n "$ZSH_BIN" && ! $(grep -Fx "$ZSH_BIN" /etc/shells) ]]; then
  echo "$ZSH_BIN" >> /etc/shells
fi


# ----------------------------------------------------------------------
#  1. Ask for a valid *new* username
# ----------------------------------------------------------------------
while true; do
    read -rp "Enter a username you want to login as: " username
    # Username rules: must start with a lowercase letter, followed by
    # lowercase letters, digits, hyphens or underscores.
    if [[ "$username" =~ ^[a-z][-a-z0-9_]*$ ]]; then
        break
    else
        echo "⚠️  Invalid username. Use lowercase letters, digits, underscores; must start with a letter."
    fi
done

# ----------------------------------------------------------------------
#  2. Read and confirm the password for the new user
# ----------------------------------------------------------------------
while true; do
    # -s  : silent (no echo)
    read -rsp "Enter a password for that user: " password1; echo
    read -rsp "Confirm password: "               password2; echo
    if [[ "$password1" == "$password2" && -n "$password1" ]]; then
        break
    else
        echo "⚠️  Passwords do not match. Please try again."
    fi
done

# ----------------------------------------------------------------------
#  3. Abort early if the user already exists
# ----------------------------------------------------------------------
if id "$username" &>/dev/null; then
    echo "❌ User $username already exists." >&2
    exit 1
fi

# ----------------------------------------------------------------------
#  4. Create the user with a bash login shell and add to sudoers
# ----------------------------------------------------------------------
default_shell="/bin/bash"
[[ -x "$ZSH_BIN" ]] && default_shell="$ZSH_BIN"

useradd --create-home --shell "$default_shell" "$username"

echo "${username}:${password1}" | chpasswd
usermod -aG sudo "$username"
usermod -aG docker "$username"

# ----------------------------------------------------------------------
#  5. Prepare the user’s ~/.ssh directory and copy root’s keys
# ----------------------------------------------------------------------
mkdir -p /home/"$username"/.ssh
chmod 700 /home/"$username"/.ssh

# Copy root’s authorized_keys so the new user can SSH using the same key(s)
# Generate SSH key pair for the user
ssh-keygen -t ed25519 -f /home/"$username"/.ssh/id_ed25519 -N "" -C "$username@$(hostname)"

# Copy the public key to authorized_keys
cp /home/"$username"/.ssh/id_ed25519.pub /home/"$username"/.ssh/authorized_keys

chmod 600 /home/"$username"/.ssh/authorized_keys
chmod 600 /home/"$username"/.ssh/id_ed25519
chmod 644 /home/"$username"/.ssh/id_ed25519.pub
chown -R "$username":"$username" /home/"$username"/.ssh

# Display the private key for the user to copy
echo ""
echo "🔑 SSH Private Key (save this somewhere safe):"
echo "==============================================" 
cat /home/"$username"/.ssh/id_ed25519
echo "=============================================="
echo ""

# ----------------------------------------------------------------------
#  6. Prep ZSH
# ----------------------------------------------------------------------
if [[ -x "$ZSH_BIN" ]]; then
  cat > /home/"$username"/.zshrc <<'EOF'
# ~/.zshrc – minimal starter file
export HISTFILE=~/.zsh_history
export HISTSIZE=10000
export SAVEHIST=10000
setopt inc_append_history share_history
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '
EOF
  chown "$username":"$username" /home/"$username"/.zshrc
fi


# ----------------------------------------------------------------------
#  7. Harden SSH daemon configuration
# ----------------------------------------------------------------------
SSHCFG='/etc/ssh/sshd_config'                 # main sshd config
CLOUDINIT='/etc/ssh/sshd_config.d/50-cloud-init.conf' # cloud-init drop-in

patch_line() {
  # Replace or append a key/value pair in sshd_config.
  # Usage: patch_line <Directive> <Value>
  local key=$1
  local value=$2

  # If the directive exists (commented or not), replace the line;
  # otherwise append it at the end of the file.
  if grep -qiE "^\s*#?\s*${key}\s+" "$SSHCFG"; then
    sed -Ei "s|^\s*#?\s*${key}\s+.*|${key} ${value}|I" "$SSHCFG"
  else
    echo "${key} ${value}" >> "$SSHCFG"
  fi
}

# Disable password auth & root login; disable PAM to avoid bypass
patch_line "PasswordAuthentication" "no"
patch_line "PermitRootLogin"        "no"
patch_line "UsePAM"                 "no"

# Remove cloud-init override file (if present) so it can’t re-enable passwords
if [[ -f $CLOUDINIT ]]; then
    rm -f "$CLOUDINIT"
fi

# ----------------------------------------------------------------------
#  7. Validate and reload sshd
# ----------------------------------------------------------------------
/usr/sbin/sshd -t          # syntax check; exits non-zero if invalid
systemctl restart ssh      # graceful restart (Ubuntu service name)

echo "✅ User $username created and SSH hardened successfully."

# Setup Portainer and Nginx Proxy Manager
mkdir -p /home/$username/homelab/portainer
mkdir -p /home/$username/homelab/nginx-proxy-manager

# Create docker-compose.yml for Portainer and NPM
cat > /home/$username/homelab/docker-compose.yml <<'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer:/data
    networks:
      - homelab

  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./nginx-proxy-manager/data:/data
      - ./nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    networks:
      - homelab

networks:
  homelab:
    driver: bridge
EOF

mkdir -p /home/$username/homelab/nginx-proxy-manager/data
mkdir -p /home/$username/homelab/nginx-proxy-manager/letsencrypt

chown -R $username:$username /home/$username/homelab

mkdir -p /home/$username/.config
chown -R $username:$username /home/$username/.config