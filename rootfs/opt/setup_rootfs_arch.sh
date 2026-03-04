#!/bin/bash

#setup the arch linux rootfs
#this is meant to be run within the chroot created by build_rootfs.sh

DEBUG="$1"
set -e
if [ "$DEBUG" ]; then
  set -x
fi

release_name="$2"
packages="$3"
hostname="$4"
root_passwd="$5"
username="$6"
user_passwd="$7"
enable_root="$8"
disable_base_pkgs="$9"
arch="${10}"

#initialize pacman keyring inside chroot
pacman-key --init
pacman-key --populate archlinux

#set up mirrorlist
echo "Server = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist

#sync package database
pacman -Sy --noconfirm

#set hostname
echo "$hostname" > /etc/hostname
cat >> /etc/hosts << END
127.0.0.1 localhost
127.0.1.1 $hostname
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
END

#enable kill-frecon service
systemctl enable kill-frecon.service

#build and install a patched systemd compatible with ChromeOS kernels
patch_systemd() {
  local patch_url="https://raw.githubusercontent.com/ading2210/chromeos-systemd/main/systemd_unstable.patch"
  local build_dir="/tmp/systemd-chromeos"
  local build_user="sysbuild"

  #install build tools and asp (arch source package tool)
  pacman -S --noconfirm asp base-devel

  #makepkg cannot run as root - create a temporary build user
  useradd -m -d "$build_dir/home" -s /usr/bin/nologin "$build_user"
  echo "$build_user ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$build_user"
  chmod 0440 "/etc/sudoers.d/$build_user"

  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  chown "$build_user" "$build_dir"

  #export the official systemd PKGBUILD
  su "$build_user" -s /bin/bash -c "cd '$build_dir' && asp export systemd"

  local pkgbuild_dir="$build_dir/systemd"
  local pkgbuild="$pkgbuild_dir/PKGBUILD"

  #download the chromeos-systemd patch alongside the PKGBUILD
  wget -q "$patch_url" -O "$pkgbuild_dir/chromeos-systemd.patch"
  chown "$build_user" "$pkgbuild_dir/chromeos-systemd.patch"

  #inject the chromeos patch application into the prepare() function,
  #right after the source directory is entered (cd "$pkgbase-stable")
  sed -i '/^[[:space:]]*cd[[:space:]]*"\$pkgbase-stable"/a\  patch -Np1 -i "\$startdir/chromeos-systemd.patch"' \
    "$pkgbuild"

  #build and install the patched systemd (skip pgp since we trust the Arch mirrors)
  su "$build_user" -s /bin/bash -c \
    "cd '$pkgbuild_dir' && makepkg -si --noconfirm --skippgpcheck"

  #clean up build user and temp files
  cd /
  if id "$build_user" &>/dev/null; then
    userdel -r "$build_user"
  fi
  rm -f "/etc/sudoers.d/$build_user"
  rm -rf "$build_dir"
}
patch_systemd

#install desktop and other custom packages
if echo "$packages" | grep "task-" >/dev/null; then
  desktop="$(echo "$packages" | cut -d'-' -f2)"
  case "$desktop" in
    xfce)     pacman -S --noconfirm xfce4 xfce4-goodies ;;
    gnome)    pacman -S --noconfirm gnome ;;
    kde)      pacman -S --noconfirm plasma ;;
    lxde)     pacman -S --noconfirm lxde ;;
    mate)     pacman -S --noconfirm mate mate-extra ;;
    lxqt)     pacman -S --noconfirm lxqt ;;
    cinnamon) pacman -S --noconfirm cinnamon ;;
    *)        pacman -S --noconfirm "$desktop" ;;
  esac
else
  pacman -S --noconfirm "$packages"
fi

#install base packages
if [ -z "$disable_base_pkgs" ]; then
  pacman -S --noconfirm sudo networkmanager nano cloud-utils zram-generator

  #enable base services
  systemctl enable NetworkManager

  #configure zram
  cat > /etc/systemd/zram-generator.conf << END
[zram0]
zram-size = ram / 2
compression-algorithm = lzo
END

  #configure networkmanager
  mkdir -p /etc/NetworkManager/conf.d
  echo -e "[main]\nauth-polkit=false" > /etc/NetworkManager/conf.d/any-user.conf
fi

#set up user account
if [ -z "$username" ]; then
  read -p "Enter the username for the user account: " username
fi
useradd -m -s /bin/bash "$username"
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

set_password() {
  local user="$1"
  local password="$2"
  if [ -z "$password" ]; then
    while ! passwd "$user"; do
      echo "Failed to set password for $user, please try again."
    done
  else
    yes "$password" | passwd "$user"
  fi
}

if [ "$enable_root" ]; then
  echo "Enter a root password:"
  set_password root "$root_passwd"
else
  usermod -aG wheel "$username"
fi

echo "Enter a user password:"
set_password "$username" "$user_passwd"

#enable bash greeter
echo "/usr/local/bin/shimboot_greeter" >> "/home/$username/.bashrc"

#clean package cache
pacman -Scc --noconfirm
