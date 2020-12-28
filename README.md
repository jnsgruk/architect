## Architect

> Yet-Another-Arch-Installer

This project not finished, but currently a simple set of shell scripts/templated files to bootstrap an Arch Linux system. It is currently **very** minimal. By default, the script will:

- Partition a disk (basic partitioning with a single boot partition and a large ext4 root)
- Install very few basic packages
- Install and configure `systemd-boot` (UEFI systems) or `grub` (BIOS systems)
- Configure locale/timezone/keyboard layout
- Detect requirement for, and if necessary install microcode packages
- Create a non-root user and enable `sudo` access
- Install and enable NetworkManager
- Install [yay](https://gtihub.com/Jguer/yay)

## Getting Started

To use this script, boot into the Arch ISO and run:

```bash
# Download the stage1.sh script
$ curl -sLo architect.sh https://jnsgr.uk/architect
# Install using defaults
$ /bin/bash architect.sh
```

To install with other configuration files or presets:

```bash
# Install using config file downloaded to live ISO environment
$ /bin/bash architect.sh /path/to/config.yml

# Install using config file available at a URL
$ /bin/bash architect.sh https://somedomain.com/your_config.yml
```

With no arguments, the installer will use the [default preset](./presets/default.yml). Default values are:

```yml
---
hostname: archie
username: user

regional:
  locale: en_GB.UTF-8
  timezone: Europe/London
  keymap: uk

partitioning:
  disk: /dev/vda
  # Currently, only ext4 is supported
  filesystem: ext4
  # If set to true, disk is encrypted with LVM-on-LUKS
  encrypted: false

provisioning:
  # List of packages to install
  packages:
    - git
    - htop
    - wget
    - curl
    - base-devel
    - vim

architect:
  # Choose the branch of Architect to clone during install
  branch: master
  # Option to disable the provisioning stage
  disable_stage3: false
```

It is possible to specify a smaller config file to just override specific values in the defaults, for example:

```yml
---
username: bob
hostname: archbox
```

## Install Stages Description

### Stage 1

Stage 1 is the pre-chroot setup. It includes the following:

- Keyboard layout setup
- Partitioning and disk encryption if enabled
- Mounting new filesystem under `/mnt`
- Running `pacstrap` to install base packages into new filesystem
- Runs `arch-chroot` and invokes stage 2

### Stage 2

Stage 2 happens inside the `chroot` environment. It includes the following:

- Setup locale
- Set hostname
- Configure and generate `initramfs`
- Install processor microcode if required
- Install and configure bootloader
- Change root password
- Create a non-root user
- Configure `sudo` for non-root user
- Invoke stage 3 if enabled

Once stage 2 is complete, the bare minimum install is complete. You can disable stage 3, reboot and enjoy your very minimal Arch Linux setup.

### Stage 3

Stage 3 aims to raise the install from "minimum viable arch" to a more usable system:

- Install more packages
- Install and configure the `yay` AUR helper
- More soon!

## TODO/Contributing

Coming soon...

- [ ] Configure a swapfile
- [ ] Add option to provide URL to post-provision script
- [ ] Migrate to `systemd` hooks in `mkinitcpio`?
- [ ] Configure TRIM properly if on a supported SSD
- [ ] Install and configure Plymouth with flicker-free boot
- Presets for desktop environments:
  - [ ] Prereq: Configure Xorg and display drivers
  - [ ] Gnome
  - [ ] Plasma
  - [ ] XFCE
  - [ ] MATE
- Update disk partitioning to include:
  - [ ] btrfs
  - [ ] LVM/LUKS with btrfs
  - [x] LVM/LUKS with ext4
- [x] Non-EFI bootloader install with GRUB
- [x] Enable option settings with a JSON/YAML file
- [x] Enable customisation of installed packages
- [x] Install and configure `yay`
