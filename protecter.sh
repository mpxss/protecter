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
  echo "4. Open arbitrary ports"
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
        for port in $(netstat -tuln | grep -E 'tcp|udp' | grep 'LISTEN' | awk '{print $4}' | grep -oE '[0-9]+'); do
          ufw allow $port
        done
        ufw enable -y
      fi
      ufw reload
      ;;
    
    2)
      read -p "Enter new SSH port (1024-65535): " ssh_port
      if [[ $ssh_port =~ ^[0-9]+$ ]] && [ $ssh_port -ge 1024 ] && [ $ssh_port -le 65535 ]; then
        echo "Updating SSH configuration..."
        sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
        ufw delete allow 22/tcp
        ufw allow $ssh_port/tcp
        systemctl restart ssh
        ufw enable -y
        ufw reload
        echo "SSH port changed to $ssh_port"
      else
        echo "Invalid port number"
      fi
      ;;
    
    3)
      echo "Blocking ICMP..."
      ufw delete allow icmp
      ufw deny icmp
      ufw enable -y
      ufw reload
      echo "ICMP blocked"
      ;;
    
    4)
      echo "Opening ports..."
      read -p "How many ports to open? " num_ports
      for ((i=1; i<=$num_ports; i++)); do
        read -p "Enter port $i to open: " open_port
        ufw allow $open_port
      done
      ufw enable -y
      ufw reload
      ;;
    
    5)
      echo "Blocking private IP ranges..."
      iptables -A INPUT -s 200.0.0.0/8 -j DROP
      iptables -A FORWARD -s 200.0.0.0/8 -j DROP
      iptables -A OUTPUT -d 200.0.0.0/8 -j DROP
      # (تکرار این خطوط برای سایر آیپیهای خصوصی)
      iptables-save
      ;;
    
    6)
      # (قسمت DNS همانند پیشین)
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
