# U-Boot build for ODROID HC4 (Amlogic S905X3)
#
# Cross-compiles U-Boot and assembles the Amlogic FIP (Firmware Image Package)
# using open-source meson64-tools with pre-built firmware blobs from LibreELEC.
#
# The resulting u-boot.bin must be written to raw sectors on the SD card:
#   dd if=u-boot.bin of=/dev/sdX conv=fsync,notrunc bs=512 seek=1
#
# No upstream nixpkgs package exists for HC4 (PR #101454 never merged).
# FIP assembly follows the approach from:
#   https://git.p2502.net/max/odroid-hc4-uboot
{pkgs}: let
  # Open-source Amlogic Meson64 FIP tools (replaces proprietary aml_encrypt_g12a)
  meson64-tools = pkgs.stdenv.mkDerivation {
    pname = "meson64-tools";
    version = "unstable-2020-08-03";
    src = pkgs.fetchFromGitHub {
      owner = "angerman";
      repo = "meson64-tools";
      rev = "a2d57d11fd8b4242b903c10dca9d25f7f99d8ff0";
      hash = "sha256-Wyx4ngfDN6jSEBwrgH8z44wntJEKMuCQz56MrU9mB5E=";
    };
    buildInputs = [pkgs.openssl];
    nativeBuildInputs = [pkgs.python3];
    postPatch = ''
      patchShebangs .
      substituteInPlace mbedtls/programs/fuzz/Makefile --replace "python2" "python"
      substituteInPlace mbedtls/tests/Makefile --replace "python2" "python"
    '';
    env.NIX_CFLAGS_COMPILE = "-Wno-error=implicit-function-declaration -Wno-error=builtin-declaration-mismatch -Wno-error=unused-result";
    makeFlags = ["PREFIX=$(out)/bin"];
    meta = {
      description = "Tools for Amlogic Meson ARM64 platforms";
      license = pkgs.lib.licenses.mit;
    };
  };

  # Pre-built Amlogic firmware blobs (acs.bin, bl2, bl30, bl31, DDR fw)
  amlogicFirmware = pkgs.fetchFromGitHub {
    owner = "LibreELEC";
    repo = "amlogic-boot-fip";
    rev = "4369a138ca24c5ab932b8cbd1af4504570b709df";
    sha256 = "sha256-mGRUwdh3nW4gBwWIYHJGjzkezHxABwcwk/1gVRis7Tc=";
    meta.license = pkgs.lib.licenses.unfreeRedistributableFirmware;
  };

  FIP = "${amlogicFirmware}/odroid-hc4";
in
  pkgs.buildUBoot {
    defconfig = "odroid-hc4_defconfig";

    # odroid-hc4_defconfig names no filesystem; U-Boot's BOOT_DEFAULTS_CMDS
    # brings in ext2/ext4/FAT only, and FS_BTRFS has no default — it is
    # selected by CMD_BTRFS alone. Without this a btrfs root is invisible to
    # U-Boot, which then falls through to network boot: a board that answers
    # ping and never starts a kernel (nas1, 2026-09-22).
    extraConfig = ''
      CONFIG_CMD_BTRFS=y
    '';

    # buildUBoot appends extraConfig to .config and does not re-run Kconfig,
    # so nothing would resolve CMD_BTRFS's `select` of FS_BTRFS, ZSTD, LZO
    # and the rest. olddefconfig does.
    postConfigure = ''
      make olddefconfig
    '';
    extraMeta = {
      platforms = ["aarch64-linux"];
      license = pkgs.lib.licenses.unfreeRedistributableFirmware;
    };
    filesToInstall = ["u-boot.bin"];
    postBuild = ''
      # Merge bl30+bl301 and bl2+acs
      ${meson64-tools}/bin/pkg --type bl30 --output bl30_new.bin \
        ${FIP}/bl30.bin ${FIP}/bl301.bin
      ${meson64-tools}/bin/pkg --type bl2 --output bl2_new.bin \
        ${FIP}/bl2.bin ${FIP}/acs.bin

      # Sign and encrypt
      ${meson64-tools}/bin/bl30sig --input bl30_new.bin \
        --output bl30_new.bin.g12a.enc --level v3
      ${meson64-tools}/bin/bl3sig --input bl30_new.bin.g12a.enc \
        --output bl30_new.bin.enc --level v3 --type bl30
      ${meson64-tools}/bin/bl3sig --input ${FIP}/bl31.img \
        --output bl31.img.enc --level v3 --type bl31
      ${meson64-tools}/bin/bl3sig --input u-boot.bin --compress lz4 \
        --output bl33.bin.enc --level v3 --type bl33 --compress lz4
      ${meson64-tools}/bin/bl2sig --input bl2_new.bin \
        --output bl2.n.bin.sig

      # Assemble final bootloader image
      ${meson64-tools}/bin/bootmk --output u-boot.bin \
        --bl2 bl2.n.bin.sig --bl30 bl30_new.bin.enc \
        --bl31 bl31.img.enc --bl33 bl33.bin.enc \
        --ddrfw1 ${FIP}/ddr4_1d.fw \
        --ddrfw2 ${FIP}/ddr4_2d.fw \
        --ddrfw3 ${FIP}/ddr3_1d.fw \
        --ddrfw4 ${FIP}/piei.fw \
        --ddrfw5 ${FIP}/lpddr4_1d.fw \
        --ddrfw6 ${FIP}/lpddr4_2d.fw \
        --ddrfw7 ${FIP}/diag_lpddr4.fw \
        --ddrfw8 ${FIP}/aml_ddr.fw \
        --ddrfw9 ${FIP}/lpddr3_1d.fw \
        --level v3
    '';
  }
