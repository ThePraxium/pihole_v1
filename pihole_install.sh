#!/bin/bash

# Automated Setup Script
# This script automates the installation and configuration of Pi-hole, Unbound, PiVPN, and Cloudflare DDNS Updater

# Welcome message
echo "====================================="
echo "Automated Setup Script for Pi-hole, Unbound, PiVPN, and one day Cloudflare DDNS Updater"
echo "====================================="

# Collect variables upfront
echo "\nPlease provide the following configuration details:"
read -p "Enter a static IP address for your Pi-hole (e.g., 192.168.1.100): " STATIC_IP
read -p "Enter your router's gateway IP address (e.g., 192.168.1.1): " GATEWAY_IP
read -p "Enter DNS server IP address (leave blank to use default Pi-hole settings): " DNS_IP
read -sp "Enter a new admin password for Pi-hole: " ADMIN_PASSWORD
echo "\n"

# Update system packages
echo "\nUpdating system packages..."
sudo apt update && sudo apt upgrade -y
if [ $? -ne 0 ]; then
  echo "Error: Failed to update packages."
  exit 1
fi
echo "System updated successfully."

# Install and configure SELinux
# echo "\nInstalling and configuring SELinux..."
# sudo apt install -y selinux-utils selinux-basics policycoreutils
# if [ $? -ne 0 ]; then
#   echo "Error: Failed to install SELinux packages."
#   exit 1
# fi
# sudo selinux-activate
# sudo selinux-config-enforcing


# Pi-hole installation
echo "\nInstalling Pi-hole..."
if ! command -v pihole &> /dev/null; then
  curl -sSL https://install.pi-hole.net | sudo bash
  if [ $? -ne 0 ]; then
    echo "Error: Pi-hole installation failed."
    exit 1
  fi
else
  echo "Pi-hole is already installed. Skipping installation."
fi

# Configure Pi-hole
echo "\nConfiguring Pi-hole..."
echo -e "interface wlan0\nstatic ip_address=$STATIC_IP/24\nstatic routers=$GATEWAY_IP\nstatic domain_name_servers=${DNS_IP:-$GATEWAY_IP}" | sudo tee -a /etc/dhcpcd.conf
sudo systemctl restart NetworkManager
sudo pihole -a -p "$ADMIN_PASSWORD"

# Add blocklists to Pi-hole from adlists.pihole
echo "\nAdding blocklists to Pi-hole..."
if [ -f "adlists.pihole" ]; then
  while IFS= read -r line; do
    # Skip commented lines
    if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
      sudo pihole -g --addurl "$line"
      echo "Added blocklist: $line"
    fi
  done < adlists.pihole
else
  echo "Error: adlists.pihole file not found. Skipping blocklist addition for Pi-hole."
fi

echo "Pi-hole configuration completed."

# Unbound installation
echo "\nInstalling and configuring Unbound..."
sudo apt install -y unbound
if [ $? -ne 0 ]; then
  echo "Error: Failed to install Unbound."
  exit 1
fi
sudo tee /etc/unbound/unbound.conf.d/pi-hole.conf > /dev/null <<EOL
server:
    verbosity: 1
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    prefer-ip6: no
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes
    rrset-roundrobin: yes
    cache-max-ttl: 86400
    cache-min-ttl: 3600
    prefetch: yes
    num-threads: 2
    so-rcvbuf: 4m
    so-sndbuf: 4m
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
EOL

sudo systemctl start unbound
sudo systemctl enable unbound

# Add blocklists to Unbound from adlists.unbound
echo "\nAdding blocklists to Unbound..."
if [ -f "adlists.unbound" ]; then
  while IFS= read -r line; do
    # Skip commented lines
    if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
      echo "local-zone: \"$line\" static" | sudo tee -a /etc/unbound/unbound.conf.d/blocklist.conf > /dev/null
      echo "Added blocklist: $line"
    fi
  done < adlists.unbound
  sudo systemctl restart unbound
else
  echo "Error: adlists.unbound file not found. Skipping blocklist addition for Unbound."
fi

if dig @127.0.0.1 -p 5335 google.com | grep -q "status: NOERROR"; then
  echo "Unbound is working correctly."
else
  echo "Error: Unbound test failed."
  exit 1
fi

# PiVPN installation
echo "\nInstalling PiVPN..."
curl -L https://install.pivpn.io | sudo bash
if [ $? -ne 0 ]; then
  echo "Error: PiVPN installation failed."
  exit 1
fi
echo "PiVPN installation completed. Follow the on-screen prompts during installation."


# Restart Networking
echo "\nRestarting networking services..."
sudo systemctl restart dhcpcd
if [ $? -ne 0 ]; then
  echo "Error: Failed to restart networking services."
  exit 1
fi

# Completion message
echo "\n====================================="
echo "Setup Complete!"
echo "Pi-hole, Unbound, PiVPN, and SELinux have been installed and configured."
echo "Access Pi-hole admin panel at: http://$STATIC_IP/admin"
echo "Ensure PiVPN is working by completing its setup."
echo "====================================="
