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

|        Name        |  Format  |     Default     | Comment                           |
| :----------------: | :------: | :-------------: | --------------------------------- |
|       `DISK`       | `string` |   `/dev/vda`    | Disk to install to.               |
|   `NEWHOSTNAME`    | `string` |    `archie`     | Hostname of installed system.     |
|     `NEWUSER`      | `string` |      `jon`      | Non-root user to create.          |
|      `LOCALE`      | `string` |  `en_GB.UTF-8`  | Locale to use.                    |
|        `TZ`        | `string` | `Europe/London` | Timezone to configure.            |
|      `KEYMAP`      | `string` |      `uk`       | Keyboard layout to configure.     |
| `ARCHITECT_BRANCH` | `string` |    `master`     | Branch of this repo to pull from. |

These should be prepended to the install command, as is shown with the `DISK` variable above, or sourced from a `dotenv` file.

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
- Update disk partitioning to include:
  - [ ] LVM/LUKS with ext4
  - [ ] btrfs
  - [ ] LVM/LUKS with btrfs
- [x] Non-EFI bootloader install with GRUB
- [x] Install and configure `yay`
- [ ] Configure a swapfile
