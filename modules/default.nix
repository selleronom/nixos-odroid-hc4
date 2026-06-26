# NixOS module for ODROID HC4 (Amlogic S905X3) SD card boot fixes
#
# This module fixes two separate warm-reboot hang issues:
#
# 1. SD card power state (kernel module):
#    After warm reboot, BL2 firmware hangs during SD card init because
#    the card retains state from Linux. The odroid-reboot kernel module
#    registers a restart handler (priority 192, above PSCI at 128) that
#    power-cycles the SD card via three aobus GPIO pins before reset.
#
# 2. IO voltage latch (device tree overlay):
#    The SD card controller supports UHS modes and switches IO voltage
#    from 3.3V to 1.8V. The S905X3 does not clear GPIO latches on reset,
#    so U-Boot starts with 1.8V and hangs (it always inits at 3.3V).
#    The overlay disables 1.8V signalling, keeping the card at 3.3V.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.odroid-hc4;
in {
  options.hardware.odroid-hc4 = {
    enable = lib.mkEnableOption "ODROID HC4 SD card boot fixes";

    enableRebootFix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load the odroid-reboot kernel module that power-cycles the SD card
        before PSCI reset, preventing BL2 firmware hangs on warm reboot.
      '';
    };

    enableNoUhs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apply device tree overlay to disable UHS (1.8V) SD card signalling.
        Prevents U-Boot hang caused by IO voltage latch not clearing on reset.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Kernel module: SD card power-cycle on reboot
    boot.extraModulePackages = lib.mkIf cfg.enableRebootFix [
      (config.boot.kernelPackages.callPackage (
        {
          stdenv,
          kernel,
        }:
          stdenv.mkDerivation {
            pname = "odroid-reboot";
            version = "1.0";
            src = ../kernel;

            nativeBuildInputs = kernel.moduleBuildDependencies;

            makeFlags = [
              "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
            ];

            installPhase = ''
              install -D odroid-reboot.ko \
                $out/lib/modules/${kernel.modDirVersion}/extra/odroid-reboot.ko
            '';

            meta.license = lib.licenses.gpl2;
          }
      ) {})
    ];

    boot.kernelModules = lib.mkIf cfg.enableRebootFix ["odroid-reboot"];

    # Device tree overlay: disable 1.8V SD card signalling
    hardware.deviceTree.overlays = lib.mkIf cfg.enableNoUhs [
      {
        name = "hc4-sd-no-uhs";
        dtsText = ''
          /dts-v1/;
          /plugin/;
          / {
            compatible = "hardkernel,odroid-hc4";
          };
          &sd_emmc_b {
            no-1-8-v;
          };
        '';
      }
    ];

    # Point extlinux at the kernel's HC4 DTB so the overlay above is actually
    # applied at boot. Without an explicit name, U-Boot falls back to its
    # built-in DTB and the overlay is compiled but never referenced in
    # extlinux.conf — silently making the no-UHS fix a no-op. mkDefault so a
    # consumer can override (e.g. point at a patched DTB).
    hardware.deviceTree.name =
      lib.mkIf cfg.enableNoUhs
      (lib.mkDefault "amlogic/meson-sm1-odroid-hc4.dtb");
  };
}
