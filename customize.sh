#!/bin/bash
rm -f metadata.img
truncate -s 64M metadata.img
mkfs.ext4 -F -d customize metadata.img