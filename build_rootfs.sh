#!/bin/bash

# Bootstrapping environments

if [ -f /etc/alpine-release ]; then
    # Alpine Linux specific
    chroot_script=/opt/setup_rootfs_alpine.sh
elif [ -f /etc/debian_version ]; then
    # Debian specific
    chroot_script=/opt/setup_rootfs_debian.sh
elif [ -f /etc/arch-release ]; then
    # Arch Linux specific
    chroot_script=/opt/setup_rootfs_arch.sh
    pacstrap /mnt base
    echo "Arch Linux detected"
else
    echo "Unsupported distribution"
    exit 1
fi

# Further build process...