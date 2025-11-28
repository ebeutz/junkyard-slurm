#!/bin/bash
# This file would be executed on first boot
sudo btrfs device add /dev/disk/by-partlabel/userdata / -f
sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
sudo systemctl restart ssh
sed -i '/firstboot.sh/d' ~/.profile