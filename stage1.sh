#!/bin/bash
set -euxo pipefail
# Output green message prefixed with [+]
_info() { echo -e "\e[92m[+] ${1:-}\e[0m"; }
# Output orange message prefixed with [-]
_warn() { echo -e "\e[33m[-] ${1:-}\e[0m"; }
# Output red message prefixed with [!] and exit
_error() { echo -e >&2 "\e[31m[!] ${1:-}\e[0m"; exit 1; }

_main() {
  # Check for internet access and bail out if there isn't any!
  if ! _check_online; then _error "Please connect to the internet"; fi

  _preamble
  _partition_and_mount
  _pacstrap

  _info "Fetching stage 2 installer"
  curl -sLo /mnt/stage2.sh https://raw.githubusercontent.com/jnsgruk/architect/master/stage2.sh
  chmod +x /mnt/stage2.sh

  _info "Chrooting and running stage 2"
  arch-chroot /mnt /stage2.sh

  _info "Cleaning up and rebooting"
  rm /mnt/stage2.sh
  umount -R /mnt
  reboot 0
}

_preamble() {
  _info "Setting up keyboard layout and timezone"
  # Load a keymap based on env variable, default to uk
  loadkeys "${KEYMAP:-uk}"
  # Enable ntp
  timedatectl set-ntp true
}

_partition_and_mount() {
  _info "Partitioning disks and generating fstab"
  if [[ -z "${DISK:-}" ]]; then
    _error "No disk specified. Set the DISK environment variable."
  fi
  # Create a new partition table
  parted "${DISK}" -s mklabel gpt
  # Create a 500MiB FAT32 Boot Partition
  parted "${DISK}" -s mkpart boot fat32 0% 500MiB
  # Set the boot/esp flags on the boot partition
  parted "${DISK}" set 1 boot on
  # Create a single ext4 root partition
  parted "${DISK}" -s mkpart root ext4 500MiB 100%
  # Format the boot partition
  mkfs.fat -F32 "${DISK}1"
  # Format the root partition
  mkfs.ext4 "${DISK}2"
  # Mount the root partition to /mnt
  mount "${DISK}2" /mnt
  # Create the mount point for boot
  mkdir -p /mnt/boot
  # Mount the boot partition
  mount "${DISK}1" /mnt/boot
  # Create the etc directory
  mkdir /mnt/etc
  # Generate the fstab file
  genfstab -U /mnt >> /mnt/etc/fstab
}

_pacstrap() {
  PACSTRAP_PACKAGES=(
    base
    base-devel
    linux
    linux-firmware
    sudo
    vim
    curl
    wget
    networkmanager
  )
  # Pacstrap the system with the base packages above
  _info "Bootstrapping baseline Arch Linux system"
  pacstrap /mnt "${PACSTRAP_PACKAGES[@]}"
}

_check_online() {
  _info "Checking for an internet connection"
  if curl -s ifconfig.co >/dev/null; then
    return 0
  else
    return 1
  fi
}

_main