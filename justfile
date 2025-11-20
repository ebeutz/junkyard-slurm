# Config

[private]
_apt_packages := replace(read(join("rootfs", "packages.txt")), "\n", " ")

# Tools

[private]
_repo := require("repo")
[private]
_debootstrap := require("debootstrap")
[private]
_rsync := require("rsync")
[private]
_fallocate := require("fallocate")
[private]
_mkfs_btrfs := require("mkfs.btrfs")
[private]
_mkbootimg := join(justfile_directory(), "tools", "mkbootimg", "mkbootimg.py")
[private]
_bazel := join(justfile_directory(), "kernel", "source", "tools", "bazel")

default:
    just --list

# Will take around 1hr
[group('kernel')]
[working-directory('kernel/source')]
clone_kernel_source android_kernel_branch="android-gs-felix-6.1-android16":
    @echo "Cloning Android kernel from branch: {{ android_kernel_branch }}"
    {{ _repo }} init \
      --depth=1 \
      -u https://android.googlesource.com/kernel/manifest \
      -b {{ android_kernel_branch }}
    {{ _repo }} sync -j {{ num_cpus() }}

[private]
_kernel_build_dir := join(justfile_directory(), "kernel", "source", "out", "felix", "dist")
[private]
_kernel_version := trim(read(join("kernel", "kernel_version")))

[group('kernel')]
[working-directory('kernel/source')]
clean_kernel: clone_kernel_source
    {{ _bazel }} clean --expunge

[group('kernel')]
[working-directory('kernel/source')]
build_kernel: clone_kernel_source
    cp -r ../custom_defconfig_mod .
    {{ _bazel }} run \
      --config=use_source_tree_aosp \
      --config=stamp \
      --config=felix \
      --defconfig_fragment=//custom_defconfig_mod:custom_defconfig \
      //private/devices/google/felix:gs201_felix_dist

    @echo "Updating kernel version string"
    strings {{ join(_kernel_build_dir, "Image") }} \
      | grep "Linux version" \
      | head -n 1 \
      | awk '{print $3}' > kernel_version

[private]
_sysroot_img := join(justfile_directory(), "boot", "rootfs.img")
[private]
_sysroot_dir := join(justfile_directory(), "rootfs", "sysroot")
[private]
_user := env("USER")
[private]
_rootfs_built_sentinel := join(justfile_directory(), ".rootfs_built")
[private]
_create_rootfs_sentinel := join(justfile_directory(), ".create_rootfs")

[working-directory('rootfs')]
_mount_rootfs: _unmount_rootfs
    if [ ! -d {{ _sysroot_dir }} ]; then \
      mkdir {{ _sysroot_dir }}; \
    fi
    if ! mountpoint -q {{ _sysroot_dir }}; then \
      sudo mount {{ _sysroot_img }} {{ _sysroot_dir }}; \
    fi

[working-directory('rootfs')]
_unmount_rootfs:
    if mountpoint -q {{ _sysroot_dir }}; then \
      sudo umount {{ _sysroot_dir }}; \
    fi

[group('rootfs')]
[working-directory('rootfs')]
clean_rootfs: _unmount_rootfs
    rm -f {{ _rootfs_built_sentinel }} {{ _create_rootfs_sentinel }} {{ _sysroot_img }}

[group('rootfs')]
[working-directory('rootfs')]
_build_rootfs debootstrap_release root_password hostname size:
    # First stage
    sudo debootstrap \
      --variant=minbase \
      --include=symlinks \
      --arch=arm64 --foreign {{ debootstrap_release }} \
      {{ _sysroot_dir }}

    # Second stage
    sudo systemd-nspawn -D {{ _sysroot_dir }} debootstrap/debootstrap --second-stage
    sudo systemd-nspawn -D {{ _sysroot_dir }} symlinks -cr .

    # Set password
    sudo systemd-nspawn -D {{ _sysroot_dir }} sh -c "echo root:{{ root_password }} | chpasswd"
    # Set hostname
    sudo systemd-nspawn -D {{ _sysroot_dir }} sh -c "echo {{ hostname }} > /etc/hostname"

    touch {{ _rootfs_built_sentinel }}

[group('rootfs')]
[working-directory('rootfs')]
build_rootfs debootstrap_release="stable" root_password="0000" hostname="fold" size="4GiB": (create_rootfs_image size) _mount_rootfs && _unmount_rootfs
    # First stage
    @if [ ! -f {{ _rootfs_built_sentinel }} ]; then \
      just _build_rootfs {{ debootstrap_release }} {{ root_password }} {{ hostname }} {{ size }}; \
    fi

[group('rootfs')]
[working-directory('rootfs')]
install_apt_packages: _mount_rootfs && _unmount_rootfs
    # Setup locale
    sudo systemd-nspawn -D {{ _sysroot_dir }} sh -c \
      "DEBIAN_FRONTEND=noninteractive apt-get -y install locales apt-utils"
    sudo systemd-nspawn -D {{ _sysroot_dir }} sh -c \
      "export DEBIAN_FRONTEND=noninteractive; \
      sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
      && dpkg-reconfigure locales \
      && update-locale en_US.UTF-8"

    # Actually install packages
    sudo systemd-nspawn -D {{ _sysroot_dir }} sh -c \
      "DEBIAN_FRONTEND=noninteractive apt-get -y install {{ _apt_packages }}"

[private]
_module_order_path := join(justfile_directory(), "rootfs", "module_order.txt")

# TODO: Download factory image and copy firmware
[group('rootfs')]
[working-directory('rootfs')]
update_kernel_modules_and_source: build_kernel _mount_rootfs && _unmount_rootfs
    sudo mkdir -p {{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}
    sudo cp {{ _kernel_build_dir }}/modules.builtin {{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/
    sudo cp {{ _kernel_build_dir }}/modules.builtin.modinfo {{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/

    sudo rm -f {{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/modules.order
    sudo touch {{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/modules.order

    @echo "Copying modules"
    for staging in vendor_dlkm system_dlkm; \
    do \
      mkdir -p unpack/"$staging" && \
      tar \
        -xvzf {{ _kernel_build_dir }}/"$staging"_staging_archive.tar.gz \
        -C unpack/"$staging"; \
      sudo {{ _rsync }} -avK --ignore-existing  --include='*/' --include='*.ko' --exclude='*' unpack/"$staging"/ {{ _sysroot_dir }}/; \
      sudo sh -c "cat unpack/\"$staging\"/lib/modules/{{ _kernel_version }}/modules.order \
        >> {{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/modules.order"; \
    done

    @echo "Updating System.map"
    sudo cp {{ _kernel_build_dir }}/System.map {{ _sysroot_dir }}/boot/System.map-{{ _kernel_version }}

    @echo "Updating module dependencies"
    sudo systemd-nspawn -D {{ _sysroot_dir }} depmod \
      --errsyms \
      --all \
      --filesyms /boot/System.map-{{ _kernel_version }} \
      {{ _kernel_version }}

    @echo "Copying kernel headers"
    mkdir -p unpack/kernel_headers
    tar \
      -xvzf {{ _kernel_build_dir }}/kernel-headers.tar.gz \
      -C unpack/kernel_headers
    sudo cp -r unpack/kernel_headers {{ _sysroot_dir }}/usr/src/linux-headers-{{ _kernel_version }}
    sudo ln -rsf {{ _sysroot_dir }}/usr/src/linux-headers-{{ _kernel_version }} {{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/build
    sudo cp {{ _kernel_build_dir }}/kernel_aarch64_Module.symvers {{ _sysroot_dir }}/usr/src/linux-headers-{{ _kernel_version }}/
    sudo cp {{ _kernel_build_dir }}/vmlinux.symvers {{ _sysroot_dir }}/usr/src/linux-headers-{{ _kernel_version }}/

    @echo "Setting systemd module load order"
    rm -f {{ _module_order_path }}

    cat {{ _kernel_build_dir }}/vendor_kernel_boot.modules.load | xargs -I {} \
      modinfo -b {{ _sysroot_dir }} -k {{ _kernel_version }} -F name "{{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/{}" \
      > {{ _module_order_path }}
    cat {{ _kernel_build_dir }}/vendor_dlkm.modules.load | xargs -I {} \
      modinfo -b {{ _sysroot_dir }} -k {{ _kernel_version }} -F name "{{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/{}" \
      >> {{ _module_order_path }}
    cat {{ _kernel_build_dir }}/system_dlkm.modules.load | xargs -I {} \
      modinfo -b {{ _sysroot_dir }} -k {{ _kernel_version }} -F name "{{ _sysroot_dir }}/lib/modules/{{ _kernel_version }}/{}" \
      >> {{ _module_order_path }}

[private]
_initramfs_path := join(_sysroot_dir, "boot", "initrd.img-" + _kernel_version)
[private]
_module_order := replace(read(_module_order_path), "\n", " ")

# TODO: Fix for proper root password (/etc/shadow) maybe with some post service
# Add other user (kalm)
# Add sudo and add user to sudo...
# sudo adduser <username> sudo.
# cat /sys/class/power_supply/battery/capacity
# ADD AOC.bin thing...
# userdata fstab? mkfs if it doesn't have an image...

[group('rootfs')]
[working-directory('rootfs')]
update_initramfs: _mount_rootfs && _unmount_rootfs
    sudo systemd-nspawn -D {{ _sysroot_dir }} dracut \
      --kver {{ _kernel_version }} \
      --lz4 \
      --show-modules \
      --force \
      --add "rescue bash" \
      --kernel-cmdline "rd.shell" \
      --force-drivers "{{ _module_order }}"

[group('rootfs')]
[working-directory('boot')]
create_rootfs_image size="4GiB": _unmount_rootfs
    @if [ ! -f {{ _create_rootfs_sentinel }} ]; then \
      just _create_rootfs_image {{ size }}; \
    fi

[group('rootfs')]
[working-directory('boot')]
_create_rootfs_image size="4GiB":
    sudo rm -f {{ _sysroot_img }}
    sudo {{ _fallocate }} -l {{ size }} {{ _sysroot_img }}
    sudo {{ _mkfs_btrfs }} {{ _sysroot_img }}
    touch {{ _create_rootfs_sentinel }}

[group('boot')]
[working-directory('boot')]
build_boot_images: _mount_rootfs && _unmount_rootfs
    sudo {{ _mkbootimg }} \
      --kernel {{ _kernel_build_dir }}/Image.lz4 \
      --cmdline "root=/dev/disk/by-partlabel/super" \
      --header_version 4 \
      -o boot.img \
      --pagesize 2048 \
      --os_version 15.0.0 \
      --os_patch_level 2025-02

    sudo {{ _mkbootimg }} \
      --ramdisk_name "" \
      --vendor_ramdisk_fragment {{ _initramfs_path }} \
      --dtb {{ _kernel_build_dir }}/dtb.img \
      --header_version 4 \
      --vendor_boot vendor_boot.img \
      --pagesize 2048 \
      --os_version 15.0.0 \
      --os_patch_level 2025-02
