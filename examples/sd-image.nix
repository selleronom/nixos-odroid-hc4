# Builds a flashable SD card image for the ODROID HC4.
#
# Build (on x86_64-linux with aarch64 emulation, or natively on aarch64):
#   nix build .#nixosConfigurations.hc4-image.config.system.build.sdImage
#
# Flash the result to a microSD card (replace /dev/sdX):
#   zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
#
# `ubootOdroidHC4` is threaded in from the flake's specialArgs — it is the
# x86_64-built U-Boot package, written to raw sectors below.
{
  modulesPath,
  lib,
  config,
  ubootOdroidHC4,
  ...
}: {
  imports = [
    (modulesPath + "/installer/sd-card/sd-image.nix")
  ];

  # NOTE on cross-building: this image is aarch64. To build it on an x86_64
  # host, aarch64 emulation must be enabled on the BUILD HOST (not here) — set
  # `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` in that machine's own
  # NixOS config, or use a native/remote aarch64 builder. Putting it in this
  # image config would bloat the target and fails outright on aarch64 (a host
  # cannot emulate its own architecture).

  # ── SD image layout ────────────────────────────────────────────
  # Amlogic doesn't use the FAT firmware partition (U-Boot lives in raw
  # sectors), so keep it minimal. The gap before it must fit U-Boot (~2 MiB).
  sdImage.firmwareSize = 30;
  sdImage.populateFirmwareCommands = "";

  # Populate the root filesystem with the extlinux boot config.
  sdImage.populateRootCommands = ''
    mkdir -p ./files/boot
    ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
      -c ${config.system.build.toplevel} -d ./files/boot
  '';

  # Write U-Boot to raw sectors after the image is assembled.
  # The Amlogic S905X3 boot ROM loads the bootloader from sector 1 (offset 512).
  sdImage.postBuildCommands = ''
    dd if=${ubootOdroidHC4}/u-boot.bin of=$img conv=fsync,notrunc bs=512 seek=1
  '';

  # The SD image module enables hardware.enableAllHardware, which pulls in
  # kernel modules that don't exist in the Amlogic meson kernel build.
  boot.initrd.allowMissingModules = true;
}
