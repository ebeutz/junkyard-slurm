# Junkyard Slurm Setup
Automated flow for
* Cloning, modifying, and building Android kernel
* Creating Debian/Ubuntu root filesystem
* Building initramfs
* TODO: etc...

## Requirements
* [just](https://github.com/casey/just)
* [repo](https://source.android.com/docs/setup/download/source-control-tools)
* qemu-user-static

## TODO
* Proper fstab
* Dedicated phone/server for automatically building everything natively
* Mount vendor partition (and other partitions by label)
* DISABLE SLEEP WHEN SHUT
* Module blacklisting

## Customizing Kernel
Add/remove kernel modules in the defconfig fragment [custom_defconfig](kernel/custom_defconfig_mod/custom_defconfig). You may have to first add/remove modules manually with something like `nconfig` to see which other dependent modules also need to be added.

## Installing Additional Debian/Ubuntu Apt Packages
Add/remove packages in [packages.txt](rootfs/packages.txt). **Specify one package per-line**.

## Building
```shell
just clone_kernel_source
just build_kernel
just build_rootfs <debootstrap_release="stable"> <root_password="0000"> <hostname="fold">
just install_apt_packages
just update_kernel_modules_and_source
just update_initramfs
just create_rootfs_image <size="4GiB">
just build_boot_images
```

## Flashing
* Flash clean android @ _link_
* flash new boot, vendor_boot, super
* fastboot oem disable-verity && fastboot oem disable-verification
