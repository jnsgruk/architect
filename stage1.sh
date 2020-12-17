#!/bin/bash

_main() {
  # Source some helper functions and config
  source /architect/architect.sh

  _preamble
  _partition_and_mount
  _pacstrap

  _info "Copying architect into chroot"
  cp -r /architect /mnt/architect

  _info "Chrooting and running stage 2"
  chmod +x /architect/stage2.sh
  arch-chroot /mnt /architect/stage2.sh

  _cleanup

  _info "Rebooting"
  umount -R /mnt
  reboot 0
}

_preamble() {
  _info "Setting up keyboard layout and timezone"
  # Load a keymap based on env variable, default to uk
  loadkeys "${KEYMAP}"
  # Enable ntp
  timedatectl set-ntp true
}

_partition_uefi_basic_ext4() {
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
}

_partition_uefi_encrypted_ext4() {
  # Create a 500MiB FAT32 Boot Partition
  parted "${DISK}" -s mkpart boot fat32 0% 500MiB
  # Set the boot/esp flags on the boot partition
  parted "${DISK}" set 1 boot on
  # Create a single ext4 root partition
  parted "${DISK}" -s mkpart root 500MiB 100%
  # Format the boot partition
  mkfs.fat -F32 "${DISK}1"
  _warn "Setting up disk encryption. Confirmation and password entry required"
  # luksFormat the root partition
  cryptsetup luksFormat "${DISK}2"
  _warn "Decrypting disk, password entry required"
  # Open the encrypted container
  cryptsetup open "${DISK}2" cryptlvm
  # Setup LVM physical volumes, volume groups and logical volumes
  _info "Setting up LVM"
  # Create a physical volume
  pvcreate /dev/mapper/cryptlvm
  vgcreate vg /dev/mapper/cryptlvm
  lvcreate -l 100%FREE vg -n root
  _info "Formatting volumes"
  # Format the root partition as ext4
  mkfs.ext4 /dev/vg/root
  # Mount the root partition to /mnt
  mount /dev/vg/root /mnt
  # Create the mount point for boot
  mkdir -p /mnt/boot
  # Mount the boot partition
  mount "${DISK}1" /mnt/boot
}

_partition_bios_basic_ext4() {
  # Create the BIOS boot partition
  parted "${DISK}" -s mkpart bios 0% 2
  # Set the bios_grub flag on the boot partition
  parted "${DISK}" set 1 bios_grub on
  # Create a single ext4 root partition
  parted "${DISK}" -s mkpart root ext4 2 100%
  # Set the boot flag on the root partition
  parted "${DISK}" set 2 boot on
  # Format the root partition
  mkfs.ext4 "${DISK}2"
  # Mount the root partition to /mnt
  mount "${DISK}2" /mnt
}

_partition_and_mount() {
  _info "Partitioning disks and generating fstab"
  if [[ -z "${DISK:-}" ]]; then
    _error "No disk specified. Set the DISK environment variable."
  fi
  # Create a new partition table
  parted "${DISK}" -s mklabel gpt
  # Check if we're on a BIOS/UEFI system
  if _check_efi; then
    if [[ "${ENCRYPTED}" == "true" ]]; then
      _partition_uefi_encrypted_ext4
    else
      _partition_uefi_basic_ext4
    fi
  else
    _partition_bios_basic_ext4
  fi
  # Create the etc directory
  mkdir /mnt/etc
  # Generate the fstab file
  genfstab -U /mnt >> /mnt/etc/fstab
}

_pacstrap() {
  PACSTRAP_PACKAGES=(base linux linux-firmware sudo networkmanager)
  # Pacstrap the system with the base packages above
  _info "Bootstrapping baseline Arch Linux system"
  pacstrap /mnt "${PACSTRAP_PACKAGES[@]}"
}

_cleanup() {
  _info "Cleaning up"
  rm -rf /mnt/architect
}

_main