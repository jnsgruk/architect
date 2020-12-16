#!/bin/bash
set -euxo pipefail
# Output green message prefixed with [+]
_info() { echo -e "\e[92m[+] ${1:-}\e[0m"; }
# Output orange message prefixed with [-]
_warn() { echo -e "\e[33m[-] ${1:-}\e[0m"; }
# Output red message prefixed with [!] and exit
_error() { echo -e >&2 "\e[31m[!] ${1:-}\e[0m"; exit 1; }

_main() {
  _set_locale
  _set_hostname

  _info "Running mkinitcpio"
  mkinitcpio -P
  
  _warn "Changing root password; enter below:"
  passwd

  _install_microcode
  _install_bootloader
  _create_user
  _setup_boot
}

_set_locale() {
  _info "Setup locale details and timezone"
  # Setup the timezone
  ln -sf "/usr/share/zoneinfo/${TZ:-Europe/London}" /etc/localtime
  hwclock --systohc
  # Uncomment the selected locale from the locale.gen file
  sed -i "s/#${LOCALE:-en_GB.UTF-8}/${LOCALE:-en_GB.UTF-8}/g" /etc/locale.gen
  # Regenerate the locales
  locale-gen
  # Set the default language and keymaps
  echo "LANG=${LOCALE:-en_GB.UTF-8}" > /etc/locale.conf
  echo "KEYMAP=uk" > /etc/vconsole.conf
}

_set_hostname() {
  _info "Configuring hostname"
  echo "${NEWHOSTNAME:-archie}" > /etc/hostname
  # Get the template hosts file
  curl -sLo /etc/hosts https://raw.githubusercontent.com/jnsgruk/architect/master/templates/hosts 
  # Update the template hosts file with selected hostname
  sed -i -e "s/:HOSTNAME:/${NEWHOSTNAME:-archie}/g" /etc/hosts
}

_install_microcode() {
  if systemd-detect-virt; then
    _info "Virtualisation detected, skipping ucode installation"
    return
  elif grep -q "GenuineIntel" /proc/cpuinfo; then
    _info "Intel CPU detected, installing intel-ucode"
    pacman -S --noconfirm intel-ucode
  elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    _info "AMD CPU detected, installing amd-ucode"
    pacman -S --noconfirm amd-ucode
  fi
}

_install_bootloader() {
  if _check_efi; then
    _info "EFI mode detected; installing and configuring systemd-boot"
    # Install systemd-boot with default options
    bootctl install
    # Get the template bootloader config
    curl -sLo /boot/loader/entries/arch.conf https://raw.githubusercontent.com/jnsgruk/architect/master/templates/arch.conf
    # Add the microcode to the bootloader config if required
    if pacman -Qqe | grep -q intel-ucode; then 
      sed -i '2 a initrd  /intel-code.img' /boot/loader/entries/arch.conf
    elif pacman -Qqe | grep -q amd-ucode; then 
      sed -i '2 a initrd  /amd-code.img' /boot/loader/entries/arch.conf
    fi
  else
    _error "EFI install only supported at the moment"
    # TODO: Implement GRUB installation
  fi
}

_create_user() {
  _info "Creating a non-root user: ${NEWUSER:-jon}"
  # Create a new default user
  useradd -m -s /bin/bash -G wheel "${NEWUSER:-jon}"
  _warn "Enter password for ${NEWUSER:-jon}"
  passwd "${NEWUSER:-jon}"
  # Uncomment a line from the /etc/sudoers file
  _info "Configuring sudo access for the wheel group"
  sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" /etc/sudoers
}

_setup_boot() {
  _info "Enabling NetworkManager"
  systemctl enable NetworkManager
}

_check_efi() {
  # Check if there are any efi variables
  if [[ -d /sys/firmware/efi ]]; then
    return 0
  else
    return 1
  fi
}

_main