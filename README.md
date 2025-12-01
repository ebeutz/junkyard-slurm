# Junkyard Slurm Setup
Automated flow for
* Cloning, modifying, and building Android kernel
* Creating Debian/Ubuntu root filesystem
* Building initramfs
* TODO: etc...

## TLDR:
* Click on the `Actions` tab
* Download the artifacts for the latest `build-image` run.
* Download the metadata.img from the root of this repo if you're not applying customizations.
* `fastboot flash` boot, vendor_boot, super (rootfs.img), metadata
* Reboot phone and use `adb shell` to setup Wi-Fi/networking/etc.
* Or, alternatively connect a keyboard and use that (a console is included).
* Or, connect a network adapter and ssh to the phone. Add network configuations to your customization script or use tools like `nmap`, `arp -a`, or your router's configuration page to find out what IP it was assigned by DHCP.

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
* btrfs-progs
* fallocate
* Kernel tar in kernel/kernel.tar (either build it or download latest kernel artifact if you're just playing with the image)

## TODO
* Module blacklisting

## Customizing image
On first boot, the `setup` program will be ran once. By default, it does nothing. However, you can change the contents of the `customize` folder and then run the `customize.sh` to regenerate the `metadata.img`, without having to (re)build images. You can then flash it using `fastboot flash metadata metadata.img` and all your customizations will be ran on first boot. This is useful for provisioning multiple devices with unique  configuations, keys, hostnames, etc out of one system and kernel image. If the setup program is ran, the partiton will remain mounted read-only in `/mnt/metadata`.

## Customizing Kernel
Add/remove kernel modules in the defconfig fragment [custom_defconfig](kernel/custom_defconfig_mod/custom_defconfig). You may have to first add/remove modules manually with something like `nconfig` to see which other dependent modules also need to be added.

## Installing Additional Debian/Ubuntu Apt Packages
Add/remove packages in [packages.txt](rootfs/packages.txt). **Specify one package per-line**. You can alternatively use a customization script to setup networking and automatically install packages, without having to (re)build an image.

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
* flash new boot, vendor_boot, super, metadata
* fastboot oem disable-verity && fastboot oem disable-verification
