#!/bin/bash

# Check root access
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Function to reload and enable UFW
apply_ufw() {
  ufw enable -y  # Enable first to avoid reload errors
  ufw reload
}

# Main menu
while true; do
  clear
  echo " __  ___     __    _                      __  
 /  |/  /____/ /   (_)___  ____ __________/ /  
/ /|_/ / ___/ /   / /_  / / __  / ___/ __  /   
/ /  / / /  / /___/ / / /_/ /_/ / /  / /_/ /    
/_/  /_/ /  /_____/_/ /___/__,_/_/   __,_/ "
  echo "-------------------------------------------"
  echo "1. Block Ping (IPv4/IPv6)"
  echo "2. Change SSH Port"
  echo "3. Enable Firewall"
  echo "4. Block Private IPs"
  echo "5. Install Smart DNS (Unbound)"
  echo "6. Open New Port"
  echo "0. Exit"
  
  # Read and sanitize input
  read -p "Select an option: " choice
  choice=$(echo "$choice" | tr -d '[:space:]')

  case $choice in
    1)
      echo "Blocking ping..."
      ufw deny in proto icmp
      ufw deny in proto ipv6-icmp
      apply_ufw
      echo "Ping blocked."
      ;;
    
    2)
      read -p "Enter new SSH port (1024-65535): " ssh_port
      if [[ $ssh_port =~ ^[0-9]+$ ]] && [ $ssh_port -ge 1024 ] && [ $ssh_port -le 65535 ]; then
        echo "Changing SSH port..."
        sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
        ufw delete allow 22/tcp &>/dev/null
        ufw allow $ssh_port/tcp
        systemctl restart ssh
        apply_ufw
        echo "SSH port changed to $ssh_port"
      else
        echo "Invalid port!"
      fi
      ;;
    
    3)
      echo "Checking active ports..."
      netstat -tuln | grep -E 'Proto|LISTEN'
      read -p "Create UFW rules for these ports? (y/n): " confirm
      if [ "$confirm" == "y" ]; then
        ufw reset
        ufw default deny incoming
        ufw default allow outgoing
        for port in $(netstat -tuln | grep -E 'tcp|udp' | grep 'LISTEN' | awk '{print $4}' | grep -oE '[0-9]+'); do
          ufw allow $port
        done
        apply_ufw
        echo "Firewall enabled."
      fi
      ;;
    
    4)
      echo "Blocking private IP ranges..."
      iptables -A INPUT -s 192.168.0.0/16 -j DROP
      iptables -A INPUT -s 172.16.0.0/12 -j DROP
      iptables -A INPUT -s 10.0.0.0/8 -j DROP
      iptables -A FORWARD -s 192.168.0.0/16 -j DROP
      iptables -A FORWARD -s 172.16.0.0/12 -j DROP
      iptables -A FORWARD -s 10.0.0.0/8 -j DROP
      iptables -A OUTPUT -d 192.168.0.0/16 -j DROP
      iptables -A OUTPUT -d 172.16.0.0/12 -j DROP
      iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
      iptables-save
      echo "Private IPs blocked."
      ;;
    
    5)
      echo "Installing Unbound..."
      apt update
      apt install -y unbound
      unbound-control-setup

      # Configure Unbound
      cat > /etc/unbound/unbound.conf <<EOL
server:
    cache-max-ttl: 86400
    cache-min-ttl: 3600
    prefetch: yes
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    interface: 127.0.0.1
    interface: ::1
    port: 53
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow
    private-address: 192.168.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10

forward-zone:
    name: "."
    forward-addr: 8.8.8.8
    forward-addr: 1.1.1.1
    forward-addr: 2001:4860:4860::8888
    forward-addr: 2606:4700:4700::1111
EOL

      # Set DNS to localhost
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      echo "nameserver ::1" >> /etc/resolv.conf
      systemctl restart unbound
      echo "Smart DNS installed."
      ;;
    
    6)
      read -p "How many ports to open? " num_ports
      for ((i=1; i<=$num_ports; i++)); do
        read -p "Enter port $i: " open_port
        ufw allow $open_port
      done
      apply_ufw
      echo "Ports opened."
      ;;
    
    0)
      break
      ;;
    
    *)
      echo "Invalid option!"
      ;;
  esac
  read -p "Press enter to continue..."
done
