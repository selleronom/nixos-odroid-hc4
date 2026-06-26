# nixos-odroid-hc4

NixOS support for the [Hardkernel ODROID HC4](https://wiki.odroid.com/odroid-hc4/odroid-hc4) (Amlogic S905X3, aarch64).

Provides a complete SD card boot solution: U-Boot build with Amlogic FIP assembly, plus kernel-level fixes for two warm-reboot hang bugs that affect all HC4 units booting from SD.

## The problem

The ODROID HC4 hangs on warm reboot when booting from SD card. There are two independent causes:

### 1. SD card power state (kernel module fix)

After a warm reboot, the Amlogic S905X3 BL2 firmware hangs during SD card initialisation because the card retains electrical state from Linux. The `odroid-reboot` kernel module registers a restart handler (priority 192, above PSCI at 128) that power-cycles the SD card via three aobus GPIO pins just before the PSCI SYSTEM_RESET call, forcing a clean card state for firmware.

Based on [Armbian's odroid-reboot driver](https://github.com/armbian/linux-rockchip), simplified for out-of-tree use with hardcoded HC4 GPIO offsets.

### 2. IO voltage latch (device tree overlay fix)

The SD card controller supports UHS modes and switches IO voltage from 3.3V to 1.8V via a GPIO regulator. The S905X3 does not clear GPIO latches on PSCI SYSTEM_RESET, so U-Boot starts with 1.8V on the SD card and hangs (U-Boot always initialises at 3.3V). A device tree overlay disables 1.8V signalling, keeping the card at 3.3V permanently.

## What you get

| Output                                                  | Purpose                                                          |
| ------------------------------------------------------- | --------------------------------------------------------------- |
| `nixosModules.odroid-hc4`                               | NixOS module applying both warm-reboot fixes (`default` aliases it) |
| `packages.x86_64-linux.uboot-odroid-hc4`                | U-Boot, cross-compiled + Amlogic FIP assembled (for image builds)  |
| `packages.aarch64-linux.uboot-odroid-hc4`               | Same, built natively on aarch64                                 |
| `formatter.{x86_64,aarch64}-linux`                      | `nix fmt` (alejandra)                                           |

A complete, copy-pasteable consumer flake lives in [`examples/`](./examples) —
`flake.nix`, a minimal `configuration.nix`, and an `sd-image.nix` that produces
a flashable image.

## Prerequisites

- **NixOS unstable.** U-Boot is built from `odroid-hc4_defconfig`, which only
  exists in recent nixpkgs. Pin `nixos-unstable` (or a recent release that
  carries the defconfig).
- **aarch64 build capability.** U-Boot's FIP assembly tools are x86_64-only, so
  that package always builds on x86_64; the kernel module and SD image are
  aarch64. To build the image on an x86_64 host you need aarch64 emulation —
  set `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` on the build host
  (the example image module does this), or use a native/remote aarch64 builder.
- **Pair with [nixos-hardware](https://github.com/NixOS/nixos-hardware).** Its
  `hardkernel-odroid-hc4` module provides the DTB, fan control, and other
  board wiring. This flake only adds the two SD-boot fixes on top.

## Quick start

### 1. Add to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixos-odroid-hc4.url = "github:selleronom/nixos-odroid-hc4";
    nixos-odroid-hc4.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixos-hardware, nixos-odroid-hc4, ... }: {
    nixosConfigurations.my-hc4 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        nixos-hardware.nixosModules.hardkernel-odroid-hc4
        nixos-odroid-hc4.nixosModules.odroid-hc4
        {
          hardware.odroid-hc4.enable = true;
        }
      ];
    };
  };
}
```

> **The no-UHS overlay needs the kernel DTB selected in `extlinux.conf`.** With
> `enableNoUhs` on (the default), this module sets
> `hardware.deviceTree.name = "amlogic/meson-sm1-odroid-hc4.dtb"` for you via
> `mkDefault`. If you point `hardware.deviceTree.name` at a different (e.g.
> patched) DTB, make sure it is still the HC4 one — otherwise U-Boot uses its
> built-in DTB and the overlay is compiled but never applied, silently
> reintroducing the warm-reboot hang.

### 2. Build a flashable SD image

The cleanest path is a dedicated image attribute that threads in the U-Boot
package via `specialArgs` — see [`examples/`](./examples) for the full set.
Then:

```bash
nix build .#nixosConfigurations.my-hc4-image.config.system.build.sdImage
```

### 3. Flash it

```bash
# Result is a zstd-compressed raw image. Replace /dev/sdX with your card.
zstdcat result/sd-image/*.img.zst \
  | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Insert the card and power on. The board boots from raw-sector U-Boot →
extlinux → NixOS, and warm reboots no longer hang.

### Options

| Option                                | Type | Default | Description                                          |
| ------------------------------------- | ---- | ------- | ---------------------------------------------------- |
| `hardware.odroid-hc4.enable`          | bool | `false` | Enable all HC4 SD card boot fixes                    |
| `hardware.odroid-hc4.enableRebootFix` | bool | `true`  | Load the odroid-reboot kernel module                 |
| `hardware.odroid-hc4.enableNoUhs`     | bool | `true`  | Apply device tree overlay to disable 1.8V signalling |

### Building U-Boot on its own

If you only want the bootloader (e.g. to repair an existing card without
reflashing the whole image), build the package directly:

```bash
nix build github:selleronom/nixos-odroid-hc4#uboot-odroid-hc4
```

and write it to raw sectors — the Amlogic boot ROM loads the bootloader from
sector 1 (byte offset 512):

```bash
sudo dd if=result/u-boot.bin of=/dev/sdX conv=fsync,notrunc bs=512 seek=1
```

The same `dd` runs inside `sdImage.postBuildCommands` in
[`examples/sd-image.nix`](./examples/sd-image.nix) so the full image ships
with U-Boot already in place.

## Compatibility

- Tested on ODROID HC4 with NixOS unstable
- Works alongside [nixos-hardware](https://github.com/NixOS/nixos-hardware) `hardkernel-odroid-hc4` module (provides fan control, DTB selection, etc.)
- The kernel module checks `of_machine_is_compatible("hardkernel,odroid-hc4")` at init and exits cleanly on non-HC4 hardware

## Upstreaming

This fix would ideally be upstreamed to [nixos-hardware](https://github.com/NixOS/nixos-hardware). Contributions welcome.

## License

- Kernel module: GPL-2.0 (required for Linux kernel modules)
- Nix packaging: MIT
- U-Boot firmware blobs: unfree-redistributable (from [LibreELEC/amlogic-boot-fip](https://github.com/LibreELEC/amlogic-boot-fip))
