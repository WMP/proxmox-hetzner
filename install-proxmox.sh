#!/bin/bash

# Default variables
skip_installer=false
no_shutdown=false
verbose=false
specified_iface_name=""
use_ovh=false

# Function to show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "OPTIONS:"
    echo "  -v, --vnc-password PASSWORD   Set VNC password"
    echo "  -P, --port PORT               Change default SSH port"
    echo "  -k, --ssh-key SSH_KEY         Add SSH public key to authorized_keys (must be a path to .pub file)"
    echo "  -e, --acme-email EMAIL        Set email for ACME account, required for register_acme_account plugin"
    echo "  --skip-installer              Skip Proxmox installer and boot directly from installed disks"
    echo "  --no-shutdown                 Do not shut down the virtual machine after finishing work"
    echo "  --disable PLUGIN1,PLUGIN2     Disable specified plugins"
    echo "  --list-ifaces                 List network interfaces and exit"
    echo "  --iface-name NAME             Specify the network interface name directly"
    echo "  --verbose                     Enable extra log output"
    echo "  -h, --help                    Show this help message and exit"
    echo ""
    echo "Available plugins (default enabled):"
    for plugin in $(echo "$plugin_list" | tr ',' '\n'); do
        echo "  $plugin: $(describe_plugin "$plugin")"
    done
}

# Function to describe each plugin
describe_plugin() {
    case $1 in
        "run_tteck_post-pve-install")
            echo "Run additional post-installation tasks from https://tteck.github.io/Proxmox/"
            ;;
        "set_network")
            echo "Configure network settings based on Hetzner rescure network"
            ;;
        "update_locale_gen")
            echo "Update locale settings with your ssh_client LC_NAME: ${LC_NAME}"
            ;;
        "register_acme_account")
            echo "Get Let's Encrypt certificate for hostname set in Proxmox installer. Cert ordering is after reboot"
            ;;
        "disable_rpcbind")
            echo "Disable rpcbind service"
            ;;
        "install_iptables_rule")
            echo "Install custom iptables rule"
            ;;
        "add_ssh_key_to_authorized_keys")
            echo "Add SSH public key to authorized_keys file and disable ssh only password login"
            ;;
        "change_ssh_port")
            echo "Change default SSH port"
            ;;
        "add_tun_lxc_device")
            echo "Add default configuration to LXC containers to create a tun interface"
            ;;
        *)
            echo "No description available"
            ;;
    esac
}

# Function to run the specified plugin
run_plugin() {
    case $1 in
        "run_tteck_post-pve-install")
            run_tteck_post-pve-install
            ;;
        "set_network")
            set_network
            ;;
        "update_locale_gen")
            update_locale_gen
            ;;
        "register_acme_account")
            register_acme_account
            ;;
        "disable_rpcbind")
            disable_rpcbind
            ;;
        "install_iptables_rule")
            install_iptables_rule
            ;;
        "add_ssh_key_to_authorized_keys")
            add_ssh_key_to_authorized_keys
            ;;
        "change_ssh_port")
            change_ssh_port
            ;;
        "add_tun_lxc")
            add_tun_lxc
            ;;
        *)
            echo "Unknown plugin: $1"
            ;;
    esac
}

print_interface_names() {
    for iface in $(ls /sys/class/net | grep -v lo); do
        echo "Interface: $iface"
        echo "$(udevadm info -e | grep -m1 -A20 "^P.*${iface}" | grep 'ID_NET_NAME_PATH' | awk -F'=' '{print "  " $1 ": " $2}')"
        echo "$(udevadm info -e | grep -m1 -A20 "^P.*${iface}" | grep 'ID_NET_NAME_ONBOARD' | awk -F'=' '{print "  " $1 ": " $2}')"
    done
    exit 0
}

# Default list of plugins
plugin_list="update_locale_gen,set_network,run_tteck_post-pve-install,register_acme_account,disable_rpcbind,install_iptables_rule,add_ssh_key_to_authorized_keys,change_ssh_port,add_tun_lxc_device"

# Parsing command line options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -v|--vnc-password)
            vnc_password="$2"
            shift
            shift
            ;;
        -P|--port)
            ssh_port="$2"
            shift
            shift
            ;;
        -k|--ssh-key)
            ssh_key="$2"
            if [[ "$ssh_key" != *.pub ]]; then
                echo "Error: Provided SSH key file must have a .pub extension."
                exit 1
            fi
            shift
            shift
            ;;
        -e|--acme-email)
            acme_email="$2"
            shift
            shift
            ;;
        --skip-installer)
            skip_installer=true
            shift
            ;;
        --no-shutdown)
            no_shutdown=true
            shift
            ;;
        --disable)
            disabled_plugins="$2"
            IFS=',' read -ra plugins_to_disable <<< "$disabled_plugins"
            for plugin in "${plugins_to_disable[@]}"; do
                plugin_list="${plugin_list//$plugin/}"
            done
            shift
            shift
            ;;
        --list-ifaces)
            print_interface_names
            exit 0
            ;;
        --iface-name)
            specified_iface_name="$2"
            shift
            shift
            ;;
        --verbose)
            verbose=true
            shift
            ;;
        --ovh)
            use_ovh=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

WAN_IFACE=$(ip route show default | awk '/default/ {print $5}')
PUBLIC_IPV4=$(ip -f inet addr show ${WAN_IFACE} | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')

# Function to add SSH public key to authorized_keys
add_ssh_key_to_authorized_keys() {
    if [ -n "$ssh_key" ]; then
        if [ -f "$ssh_key" ]; then
            # Copy SSH key to local host via scp
            if ssh-copy-id -f -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$ssh_key" -p 5555 root@127.0.0.1 2>&1 | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'; then
                echo "Added SSH public key to authorized_keys"
                
                # Disable password authentication for SSH
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 root@127.0.0.1 "sed -i 's/^PasswordAuthentication yes$/PasswordAuthentication no/' /etc/ssh/sshd_config" 2>&1 | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
                echo "Password authentication disabled for SSH"
            else
                echo "Error: Failed to copy SSH public key to authorized_keys."
                exit 1
            fi
        else
            echo "Error: File '$ssh_key' does not exist."
            exit 1
        fi
    fi
}


change_ssh_port() {
    if [ -n "$ssh_port" ]; then
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 root@127.0.0.1 "sed -i 's/^#Port.*$/Port $ssh_port/' /etc/ssh/sshd_config"  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 root@127.0.0.1 "echo 'Port $ssh_port' >> /root/.ssh/config"  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
        echo "SSH port changed to $ssh_port on proxmox server."
    fi
}

disable_rpcbind() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 root@127.0.0.1 "systemctl disable --now rpcbind rpcbind.socket && systemctl mask rpcbind"  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
    echo "rpcbind disabled on proxmox server."
}

install_iptables_rule() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 127.0.0.1 "
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections &&
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections &&
        apt-get install -y iptables-persistent &&
        iptables -I INPUT -i vmbr0 -p tcp -m tcp --dport 3128 -j DROP &&
        netfilter-persistent save
    "  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
}

update_locale_gen() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 127.0.0.1 "
        if grep -q \"^# *\$LC_NAME\" /etc/locale.gen; then
            sed -i \"s/^# *\$LC_NAME/\$LC_NAME/\" /etc/locale.gen
            locale-gen
            echo \"Updated /etc/locale.gen and generated locales for \$LC_NAME\"
        fi
        update-locale LANG=en_US.UTF-8
    "  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
}

set_network() {
    curl -L "https://github.com/WMP/proxmox-hetzner/raw/main/files/main_vmbr0_basic_template.txt" -o ~/interfaces_sample
    
    if [ "$specified_iface_name" ]; then
        IFACE_NAME=$specified_iface_name
    else
        IFACE_NAME="$(udevadm info -e | grep -m1 -A 20 ^P.*${WAN_IFACE} | grep ID_NET_NAME_PATH | cut -d'=' -f2)"
    fi

    # Continue with setting up the network using the chosen IFACE_NAME
    MAIN_IPV4_CIDR="$(ip address show ${WAN_IFACE} | grep global | grep "inet "| xargs | cut -d" " -f2)"
    MAIN_IPV4_GW="$(ip route | grep default | xargs | cut -d" " -f3)"
    MAIN_IPV6_CIDR="$(ip address show ${WAN_IFACE} | grep global | grep "inet6 "| xargs | cut -d" " -f2)"
    MAIN_MAC_ADDR="$(cat /sys/class/net/${WAN_IFACE}/address)"

    # Check if the MAIN_IPV4_CIDR variable has a value
    if [ -z "$MAIN_IPV4_CIDR" ]; then
        echo "Enter the value for MAIN_IPV4_CIDR manually:"
        read -r MAIN_IPV4_CIDR
    fi

    # Check if the MAIN_IPV4_GW variable has a value
    if [ -z "$MAIN_IPV4_GW" ]; then
        echo "Enter the value for MAIN_IPV4_GW manually:"
        read -r MAIN_IPV4_GW
    fi

    # Check if the MAIN_IPV6_CIDR variable has a value
    if [ -z "$MAIN_IPV6_CIDR" ]; then
        echo "Enter the value for MAIN_IPV6_CIDR manually:"
        read -r MAIN_IPV6_CIDR
    fi

    # Check if the MAIN_MAC_ADDR variable has a value
    if [ -z "$MAIN_MAC_ADDR" ]; then
        echo "Enter the value for MAIN_MAC_ADDR manually:"
        read -r MAIN_MAC_ADDR
    fi

    sed -i "s|#IFACE_NAME#|$IFACE_NAME|g" ~/interfaces_sample
    sed -i "s|#MAIN_IPV4_CIDR#|$MAIN_IPV4_CIDR|g" ~/interfaces_sample
    sed -i "s|#MAIN_IPV4_GW#|$MAIN_IPV4_GW|g" ~/interfaces_sample
    sed -i "s|#MAIN_MAC_ADDR#|$MAIN_MAC_ADDR|g" ~/interfaces_sample
    sed -i "s|#MAIN_IPV6_CIDR#|$MAIN_IPV6_CIDR|g" ~/interfaces_sample

    # Choose DNS based on platform (OVH or Hetzner)
    if [ "$use_ovh" = true ]; then
        DNS1="213.186.33.99"  # OVH DNS
        DNS2="8.8.8.8"        # Google DNS as backup
    else
        DNS1="185.12.64.1"    # Hetzner DNS
        DNS2="185.12.64.2"    # Hetzner secondary DNS
    fi

    # Display the configuration for user verification
    if [ "$verbose" = true ]; then
        echo "The generated network configuration is as follows:"
        cat ~/interfaces_sample
    fi

    # Apply the configuration
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 5555 ~/interfaces_sample root@127.0.0.1:/etc/network/interfaces  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'

    # Configure DNS on the remote machine
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 127.0.0.1 "printf 'nameserver $DNS1\nnameserver $DNS2\n' > /etc/resolv.conf; sed -i 's/10.0.2.15/$PUBLIC_IPV4/' /etc/hosts;"  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
}


# Function to download the latest Proxmox ISO if not already downloaded
download_latest_proxmox_iso() {
    # URL from which we fetch Proxmox ISO images
    ISO_URL="https://enterprise.proxmox.com/iso/"

    # Fetching the list of ISO images
    iso_list=$(curl -s "$ISO_URL")

    # Extracting the name of the latest ISO file
    latest_iso_name=$(echo "$iso_list" | grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -r | head -n 1 | sed 's/">proxmox-ve.*//')

    # Check if ISO already exists
    if [ -f "$latest_iso_name" ]; then
        echo "ISO already exists at $latest_iso_name"
        return
    fi

    echo "Downloading the latest ISO file"
    if curl --help all | grep -q -- --remove-on-error; then
        curl --remove-on-error -o "$latest_iso_name" "$ISO_URL/$latest_iso_name"
    else
        curl -o "$latest_iso_name" "$ISO_URL/$latest_iso_name"
    fi

    if [ $? -eq 0 ]; then
        echo "Downloaded the latest ISO image: $latest_iso_name"
    else
        echo "Error downloading the ISO image."
    fi
}

# Function to check if SSH server is up with a timeout of 60 seconds
check_ssh_server() {
    local server="127.0.0.1"
    local port="5555"
    local timeout=60
    local end_time=$((SECONDS + timeout))

    while [ $SECONDS -lt $end_time ]; do
        if nc -z "$server" "$port" </dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

order_acme_certificate() {
    cat <<EOF > /root/acme_certificate_order_script.sh
#!/bin/bash
sleep 30;
pvenode acme cert order

rm "/etc/cron.d/acme_certificate_order_cron"
rm "/root/acme_certificate_order_script.sh"
EOF

    chmod +x /root/acme_certificate_order_script.sh

    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 5555 /root/acme_certificate_order_script.sh 127.0.0.1:/root/acme_certificate_order_script.sh  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)' && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 127.0.0.1 "
        echo -e \"@reboot root /root/acme_certificate_order_script.sh > /var/log/acme_certificate_order_script.log\n\" > /etc/cron.d/acme_certificate_order_cron && \
        chmod 644 /etc/cron.d/acme_certificate_order_cron
    "  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
}

register_acme_account() {
    ssh -o CheckHostIP=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 127.0.0.1 " 
        apt update && apt install -y expect && 
        expect -c \"
            spawn pvenode acme account register default $acme_email --directory https://acme-v02.api.letsencrypt.org/directory
            expect -re {Do you agree}
            send \"y\\\r\"
            interact
        \" && pvenode config set --acme domains=\$(hostname -f) 
    "  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
    order_acme_certificate
}

add_tun_lxc() {
    cat <<EOF >/usr/share/lxc/config/common.conf.d/10-tun.conf
lxc.cgroup2.devices.allow = c 10:200 rwm
lxc.hook.pre-start = sh -c "/usr/sbin/modprobe tun && [ ! -e /dev/net/tun-lxc ] && /usr/bin/mknod /dev/net/tun-lxc c 10 200 || true && /usr/bin/chown 100000:100000 /dev/net/tun-lxc"
lxc.mount.entry = /dev/net/tun-lxc dev/net/tun none bind,create=file
EOF

}

run_tteck_post-pve-install() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 127.0.0.1  -t  'bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/post-pve-install.sh)"'
}


## EXECUTION ##
if ! dpkg -s qemu-system netcat-traditional ovmf >/dev/null 2>&1; then
  apt-get update
  apt-get install -y qemu-system netcat-traditional ovmf
fi




# Detecting EFI/UEFI system
if [ -d "/sys/firmware/efi" ]; then
    bios="-bios /usr/share/ovmf/OVMF.fd"
else
    bios=""
fi

# Display the list of disks with the added device path
if [ "$verbose" = true ]; then
    # Array to store disk information as text
    hard_disks_text=()
    
    # Read disk information using lsblk and store it in the array
    first_line=true
    while read -r line; do
        if $first_line; then
            first_line=false
            continue
        fi
        hard_disks_text+=("$line")
    done < <(lsblk -o NAME,SIZE,SERIAL,VENDOR,MODEL,PARTTYPE -d -p | grep -v 'loop' | grep -v 'sr')
    
    # Add a column with device path /dev/vd*
    device_path="/dev/vd"
    counter=97  # ASCII code for 'a'
    for ((i = 0; i < ${#hard_disks_text[@]}; i++)); do
        if (( $counter > 122 )); then  # If ASCII code exceeds 'z'
            echo "Too many disks to assign"
            break
        fi
        # Append device path to each disk entry
        hard_disks_text[$i]="${hard_disks_text[$i]} $device_path$(printf "\x$(printf %x $counter)")"
        ((counter++))
    done
    
    echo "Disk mapping table:"
    for disk_info in "${hard_disks_text[@]}"; do
        echo "$disk_info"
    done
fi

hard_disks=()
while read -r line; do
    hard_disks+=("$line")
done < <(lsblk -o NAME -d -n -p | grep -v 'loop' | grep -v 'sr')

latest_machine=$(qemu-system-x86_64 -machine help | grep -oP "pc-q35-\d+\.\d+" | sort -V | tail -n 1)

if [ "$skip_installer" = false ]; then
    # Call the function to download the latest Proxmox ISO
    download_latest_proxmox_iso

    if [ ! -n "$vnc_password" ]; then
        # Generate random VNC password
        vnc_password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    fi

    echo
    echo "Connecto to vnc://$PUBLIC_IPV4:5900 with password: $vnc_password"
    echo "If VNC stuck before open installator, try to reconnect VNC client"
    echo
    echo "In the network settings window, make sure to set the correct hostname and DO NOT change the IP addresses. There IP addresses are needed only for the system installation process."
    echo

    # Building QEMU command with detected hard disks
    qemu_command="printf \"change vnc password\n%s\n\" $vnc_password | qemu-system-x86_64 -machine $latest_machine -enable-kvm $bios -cpu host -smp 4 -m 4096 -boot d -cdrom $latest_iso_name -vnc :0,password -monitor stdio -no-reboot"
    for disk in "${hard_disks[@]}"; do
        qemu_command+=" -drive file=$disk,format=raw,media=disk,if=virtio"
    done

    # Running QEMU
    if [ "$verbose" = true ]; then
        echo "$qemu_command"
        eval "$qemu_command"
    else
        eval "$qemu_command > /dev/null 2>&1"
    fi    
fi

# Set up bridge networking if --ovh is specified
if [ "$use_ovh" = true ]; then
  BRIDGE_NAME="br0"
  BRIDGE_IP="10.0.2.2"
  SUBNET="10.0.2.0/24"
  OUT_INTERFACE="eth0"  # Replace with actual outgoing interface

  # Create and configure bridge if it doesn't exist
  if ! ip link show $BRIDGE_NAME > /dev/null 2>&1; then
    echo "Creating bridge $BRIDGE_NAME..."
    ip link add name $BRIDGE_NAME type bridge
    ip addr add $BRIDGE_IP/24 dev $BRIDGE_NAME
    ip link set $BRIDGE_NAME up

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Set up NAT for the bridge network
    iptables -t nat -A POSTROUTING -s $SUBNET -o $OUT_INTERFACE -j MASQUERADE

    iptables -t nat -A PREROUTING -p tcp --dport 5555 -j REDIRECT --to-port 22

    # Configure bridge permissions for QEMU
    sudo mkdir -p /etc/qemu
    echo "allow $BRIDGE_NAME" | sudo tee /etc/qemu/bridge.conf
  fi

  # Construct QEMU command with bridge networking
  qemu_command="qemu-system-x86_64 -machine $latest_machine -enable-kvm $bios -cpu host \
  -netdev bridge,id=net0,br=$BRIDGE_NAME -device virtio-net-pci,netdev=net0 -smp 4 -m 4096"
else
  # Default QEMU command with user networking
  qemu_command="qemu-system-x86_64 -machine $latest_machine -enable-kvm $bios -cpu host \
  -device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp::5555-:22 -smp 4 -m 4096"
fi

qemu_command="qemu-system-x86_64 -machine $latest_machine -enable-kvm $bios -cpu host -device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp::5555-:22 -smp 4 -m 4096"
for disk in "${hard_disks[@]}"; do
    qemu_command+=" -drive file=$disk,format=raw,media=disk,if=virtio"
done

# Running QEMU
if [ "$verbose" = true ]; then
    echo "$qemu_command"
    eval "$qemu_command &"
else
    eval "$qemu_command > /dev/null 2>&1 &"
fi  

bg_pid=$!

# Performing SSH operations
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""
fi

echo "Waiting for start SSH server on proxmox..."
check_ssh_server || echo "Fatal: Proxmox may not have started properly because SSH on socket 127.0.0.1:5555 is not working."
echo
echo "Please enter the password for the root user that you set during the Proxmox installation."
echo "Remember not to select the reboot option in the 'run_tteck_post-pve-install' plugin!"
echo

ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 root@127.0.0.1  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 127.0.0.1  -C exit  2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'

# Run enabled plugins
for plugin in $(echo "$plugin_list" | tr ',' '\n'); do
    run_plugin "$plugin"
done

# Shut down the virtual machine if --no-shutdown option is not used
if [ "$no_shutdown" = false ]; then
    echo "Shutting down the virtual machine..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 5555 root@127.0.0.1 "poweroff" 2>&1  | egrep -v '(Warning: Permanently added |Connection to 127.0.0.1 closed)'
fi
