#!/bin/bash
# This file would be executed on first boot
echo TODO: write first boot script
sudo systemctl enable adbd.service
sudo systemctl start adbd.service
sed -i '/firstboot.sh/d' ~/.profile