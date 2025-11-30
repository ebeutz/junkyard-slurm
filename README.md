# Junkyard Slurm Setup
Automated flow for
* Cloning, modifying, and building Android kernel
* Creating Debian/Ubuntu root filesystem
* Building initramfs
* TODO: etc...

## Requirements to kernel/images:
For both kernel/image building:
* [just](https://github.com/casey/just)
* rsync
* eatmydata

For only kernel building:
* [repo](https://source.android.com/docs/setup/download/source-control-tools)
* x86_64 system required to build kernel
* Patience (this takes a *while*)

For only image building:
* arm64 system can be used to build images, qemu-user-static required for x86_64 to build images
* Debian stable
* mmdebstrap
* systemd-nspawn
* btrfs-progs
* fallocate
* Kernel tar in kernel/kernel.tar (either build it or download latest kernel artifact if you're just playing with the image)

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
eatmydata just clone_kernel_source
eatmydata just build_kernel
eatmydata just update_kernel_modules_and_source
eatmydata just create_rootfs_image <size="4GiB">
eatmydata just build_rootfs <debootstrap_release="stable"> <root_password="0000"> <hostname="fold">
eatmydata just build_boot_images
```
eatmydata will speed things up greatly on any disk I/O bound operations (such as building the image). If you are building this on your own machine (and not on a container/CI environment), it's highly recommended you run `sync` after the build to ensure that all the data is written to disk. If you are on a really slow HDD, you can either build in a tmpfs or an overlay mounted with the volatile option, and then copy all your desired build artifacts to another location.

## Flashing
* Flash clean android @ _link_
* flash new boot, vendor_boot, super
* fastboot oem disable-verity && fastboot oem disable-verification
