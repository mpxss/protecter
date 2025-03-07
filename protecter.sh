#!/bin/bash

# Check root access
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Main menu
while true; do
  clear
  echo " __  ___     __    _                      __  
 /  |/  /____/ /   (_)___  ____ __________/ /  
/ /|_/ / ___/ /   / /_  / / __  / ___/ __  /   
/ /  / / /  / /___/ / / /_/ /_/ / /  / /_/ /    
/_/  /_/ /  /_____/_/ /___/__,_/_/   __,_/ "
  echo "-------------------------------------------"
  echo "1. Check active ports & create UFW rules"
  echo "2. Change SSH port"
  echo "3. Block ICMP (Ping)"
  echo "4. Close arbitrary ports"
  echo "5. Block private IP ranges"
  echo "6. Install Smart DNS (Unbound)"
  echo "0. Exit"
  read -p "Select an option: " choice

  case $choice in
    1)
      echo "Checking active ports..."
      netstat -tuln | grep -E 'Proto|LISTEN'
      read -p "Create UFW rules for these ports? (y/n): " confirm
      if [ "$confirm" == "y" ]; then
        ufw reset
        ufw default deny incoming
        ufw default allow outgoing
        for port in $(netstat -tuln | grep -E 'tcp|udp' | awk '{print $4}' | grep -oE '[0-9]+'); do
          ufw allow $port
        done
        ufw enable
      fi
      ;;
    
    2)
      read -p "Enter new SSH port (1024-65535): " ssh_port
      if [[ $ssh_port =~ ^[0-9]+$ ]] && [ $ssh_port -ge 1024 ] && [ $ssh_port -le 65535 ]; then
        echo "Updating SSH configuration..."
        sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
        ufw allow $ssh_port/tcp
        systemctl restart ssh
        echo "SSH port changed to $ssh_port"
      else
        echo "Invalid port number"
      fi
      ;;
    
    3)
      echo "Blocking ICMP..."
      ufw deny in proto icmp
      echo "ICMP blocked"
      ;;
    
    4)
      read -p "How many ports to close? " num_ports
      for ((i=1; i<=$num_ports; i++)); do
        read -p "Enter port $i to block: " block_port
        ufw deny $block_port
      done
      ;;
    
    5)
      echo "Blocking private IP ranges..."
      iptables -A FORWARD -s 200.0.0.0/8 -j DROP
      iptables -A FORWARD -s 102.0.0.0/8 -j DROP
      iptables -A FORWARD -s 10.0.0.0/8 -j DROP
      iptables -A FORWARD -s 100.64.0.0/10 -j DROP
      iptables -A FORWARD -s 169.254.0.0/16 -j DROP
      iptables -A FORWARD -s 198.18.0.0/15 -j DROP
      iptables -A FORWARD -s 198.51.100.0/24 -j DROP
      iptables -A FORWARD -s 203.0.113.0/24 -j DROP
      iptables -A FORWARD -s 224.0.0.0/4 -j DROP
      iptables -A FORWARD -s 240.0.0.0/4 -j DROP
      iptables -A FORWARD -s 255.255.255.255/32 -j DROP
      iptables -A FORWARD -s 192.0.0.0/24 -j DROP
      iptables -A FORWARD -s 192.0.2.0/24 -j DROP
      iptables -A FORWARD -s 127.0.0.0/8 -j DROP
      iptables -A FORWARD -s 127.0.53.53 -j DROP
      iptables -A FORWARD -s 192.168.0.0/16 -j DROP
      iptables -A FORWARD -s 0.0.0.0/8 -j DROP
      iptables -A FORWARD -s 172.16.0.0/12 -j DROP
      iptables -A FORWARD -s 224.0.0.0/3 -j DROP
      iptables -A FORWARD -s 192.88.99.0/24 -j DROP
      iptables -A FORWARD -s 169.254.0.0/16 -j DROP
      iptables -A FORWARD -s 198.18.140.0/24 -j DROP
      iptables -A FORWARD -s 102.230.9.0/24 -j DROP
      iptables -A FORWARD -s 102.233.71.0/24 -j DROP
      iptables-save
      ;;
    
    6)
      echo "Installing Unbound DNS..."
      apt update
      apt install -y unbound
      unbound-control-setup
      
      # Backup original config
      mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.bak
      
      # Create new config
      cat <<EOL > /etc/unbound/unbound.conf
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

    remote-control:
        control-enable: yes
        control-interface: 127.0.0.1

forward-zone:
    name: "."
    forward-first: no
    forward-addr: 8.8.8.8
    forward-addr: 1.1.1.1
    forward-addr: 2001:4860:4860::8888
    forward-addr: 2606:4700:4700::1111
EOL

      # Verify configuration
      unbound-checkconf
      systemctl restart unbound
      
      # Update resolv.conf
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      echo "nameserver ::1" >> /etc/resolv.conf
      chattr +i /etc/resolv.conf  # Prevent changes
      ;;
    
    0)
      break
      ;;
    
    *)
      echo "Invalid option"
      ;;
  esac
  read -p "Press enter to continue..."
done
