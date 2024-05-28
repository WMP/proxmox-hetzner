<p align="center">
    <img src="https://github.com/WMP/proxmox-hetzner/raw/main/files/icons/proxmox.png" alt="Proxmox" height="48" />
    </br>
    <img src="https://github.com/WMP/proxmox-hetzner/raw/main/files/icons/hetzner.png" alt="Hetzner" height="38" />
    </br>
    <a href="https://github.com/chmaikos/proxmox-hetzner">
        <img src="https://img.shields.io/github/stars/WMP/proxmox-hetzner" alt="Stars"/>
        <img src="https://img.shields.io/github/watchers/WMP/proxmox-hetzner" />
        <img src="https://img.shields.io/github/forks/WMP/proxmox-hetzner" />
    </a>
</p>

---

# Install Proxmox on Hetzner Dedicated Server with QEMU

- [Install Proxmox on Hetzner Dedicated Server with QEMU](#install-proxmox-on-hetzner-dedicated-server-with-qemu)
  - [Prepare the rescue from hetzner robot manager](#prepare-the-rescue-from-hetzner-robot-manager)
    - [Install requirements and Install Proxmox](#install-requirements-and-install-proxmox)
    - [Useful network configs](#useful-network-configs)
    - [Post Install](#post-install)
    - [Login to `Web GUI`](#login-to-web-gui)
      - [Special Thanks](#special-thanks)

## Prepare the rescue from hetzner robot manager

- Select the Rescue tab for the specific server, via the hetzner robot manager
- - Operating system=Linux
- - Architecture=64 bit
- - Public key=*optional*
- --> Activate rescue system
- Select the Reset tab for the specific server,
- Check: Execute an automatic hardware reset
- --> Send
- Wait a few mins
- Connect via ssh/terminal to the rescue system running on your server

### Install requirements and Install Proxmox

```shell
wget https://github.com/WMP/proxmox-hetzner/raw/main/install-proxmox.sh
bash install-proxmox.sh --help
```

- Install Proxmox and attention to these :
  - choose `zfs` partition type
  - choose `lz4` in compress type of advanced partitioning
  - do not add real IP info in network configuration part (just leave defaults!)
  - close VNC window after system rebooted and waits for reconnect

After installer reboots QEMU, the script will automaticaly configure network vmbr0 for a bridged network. It will also run the [Post Install Script](https://github.com/tteck/Proxmox/raw/main/misc/post-pve-install.sh)

If you enable ACME make sure to pass an email with `-e, --acme-email EMAIL`

- Reboot main `rescue` ssh:

```shell
reboot
```

- After a few minutes, login again to your proxmox server with ssh on port `22` or the port you gave the install script.
- Make sure to change the hostname file to reflect your public ip from hetzner.

### Useful network configs

- For `private subnet` append these lines to interface file  :

```apacheconf
auto vmbr1
iface vmbr1 inet static
    address 192.168.20.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   iptables -t nat -A POSTROUTING -s '192.168.20.0/24' -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s '192.168.20.0/24' -o vmbr0 -j MASQUERADE
    post-up   iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
    post-down iptables -t raw -D PREROUTING -i fwbr+ -j CT --zone 1
```

- For `public subnet` append these lines to interface file (first-Usable-IP/subnet)

```apacheconf
auto vmbr2
iface vmbr2 inet static
    address first-Usable-IP/subnet
    address first-Usable-IP/subnet
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

- For `vlan support` append these lines to interface file  :
  - You have to create a vswitch with ID `4000` in your robot panel of hetzner.

```apacheconf
auto vlan4000
iface vlan4000 inet static
    address 10.0.1.5/24
    mtu 1400
    vlan-raw-device vmbr0
    up ip route add 10.0.0.0/16 via 10.0.1.1 dev vlan4000
    down ip route del 10.0.0.0/16 via 10.0.1.1 dev vlan4000
```

### Post Install

- Limit ZFS Memory Usage According to [This Link](https://pve.proxmox.com/wiki/ZFS_on_Linux#sysadmin_zfs_limit_memory_usage)

```shell
echo "options zfs zfs_arc_min=$[6 * 1024*1024*1024]" >> /etc/modprobe.d/99-zfs.conf
echo "options zfs zfs_arc_max=$[12 * 1024*1024*1024]" >> /etc/modprobe.d/99-zfs.conf
update-initramfs -u
```

### Login to `Web GUI`

`https://IP_ADDRESS:8006/`

#### Special Thanks

[Ariadata](https://github.com/ariadata)
[Tteck](https://tteck.github.io/Proxmox/)
