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
# Set a disk to install to, and run the installer
$ DISK=/dev/vda /bin/bash architect.sh
```

Additional options can be specified as environment variables:

|        Name        |  Format  |     Default     | Comment                                                  |
| :----------------: | :------: | :-------------: | -------------------------------------------------------- |
|       `DISK`       | `string` |   `/dev/vda`    | Disk to install to.                                      |
|   `NEWHOSTNAME`    | `string` |    `archie`     | Hostname of installed system.                            |
|     `NEWUSER`      | `string` |      `jon`      | Non-root user to create.                                 |
|      `LOCALE`      | `string` |  `en_GB.UTF-8`  | Locale to use.                                           |
|        `TZ`        | `string` | `Europe/London` | Timezone to configure.                                   |
|      `KEYMAP`      | `string` |      `uk`       | Keyboard layout to configure.                            |
| `ARCHITECT_BRANCH` | `string` |    `master`     | Branch of this repo to pull from.                        |
|  `DISABLE_STAGE3`  | `string` |                 | Disable stage 3 of installer. Set to `true` if required  |
|    `ENCRYPTED`     | `string` |     `false`     | Set to `true` to enable disk encryption                  |
|    `FILESYSTEM`    | `string` |     `ext4`      | Select install filesystem. Supported options are: `ext4` |

These should be prepended to the install command, as is shown with the `DISK` variable above, or sourced from a `dotenv` file.

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

- [ ] Enable option settings with a JSON/YAML file
- [ ] Enable customisation of installed packages
- [ ] Add option to provide URL to post-provision script
- [ ] Presets for desktop environments:
  - [ ] Gnome
  - [ ] Plasma
  - [ ] XFCE
  - [ ] MATE
- [ ] Update disk partitioning to include:
  - [x] LVM/LUKS with ext4
  - [ ] btrfs
  - [ ] LVM/LUKS with btrfs
- [x] Non-EFI bootloader install with GRUB
- [x] Install and configure `yay`
- [ ] Configure a swapfile
