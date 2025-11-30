#!/bin/bash
# This file would be executed on first boot
echo Setting up device...
sudo btrfs filesystem resize max /
sudo btrfs device add /dev/disk/by-partlabel/userdata / -f
rm firstboot.sh
sed -i '/firstboot.sh/d' ~/.profile
sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
sudo systemctl restart ssh
sudo mkdir -p /mnt/metadata
echo "Attempting to mount and run customizations"
if sudo mount -t ext4 -o ro /dev/disk/by-partlabel/metadata /mnt/metadata; then
    echo "Mount successful."
    if [ -x /mnt/metadata/setup ]; then
        echo "Running customizations"
        echo "/dev/disk/by-partlabel/metadata /mnt/metadata ext4 ro,defaults 0 0" | sudo tee -a /etc/fstab
        /mnt/metadata/setup
    else
        echo "Setup script not found or not executable. Cleaning up..."
        sudo umount /mnt/metadata
        sudo rmdir /mnt/metadata
    fi
else
    echo "Mount failed. Cleaning up..."
    sudo rmdir /mnt/metadata
fi
echo Setup complete!