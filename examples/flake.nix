# Minimal consumer flake for the ODROID HC4.
#
# Copy this directory out of the repo, adjust the host config, then build a
# flashable SD card image:
#
#   nix build .#nixosConfigurations.hc4-image.config.system.build.sdImage
#
# The U-Boot package is cross-compiled from x86_64-linux (the Amlogic FIP
# assembly tools are x86_64-only), so the image build needs aarch64 emulation
# on an x86_64 host: set `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];`
# in the BUILD HOST's own NixOS config, or build on a native aarch64 machine /
# remote builder.
{
  description = "ODROID HC4 NixOS — example image build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixos-odroid-hc4.url = "github:selleronom/nixos-odroid-hc4";
    # Keep the HC4 flake on the same nixpkgs you build against, so U-Boot and
    # the kernel module are built once against a single libc/toolchain.
    nixos-odroid-hc4.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    nixos-hardware,
    nixos-odroid-hc4,
    ...
  }: {
    # Running system (deployed via nixos-rebuild / your GitOps tool).
    nixosConfigurations.hc4 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        nixos-hardware.nixosModules.hardkernel-odroid-hc4
        nixos-odroid-hc4.nixosModules.odroid-hc4
        ./configuration.nix
        {hardware.odroid-hc4.enable = true;}
      ];
    };

    # Flashable SD card image. Built as a separate attribute so the U-Boot
    # package can be threaded in via specialArgs (it lives on x86_64-linux).
    nixosConfigurations.hc4-image = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        ubootOdroidHC4 = nixos-odroid-hc4.packages.x86_64-linux.uboot-odroid-hc4;
      };
      modules = [
        nixos-hardware.nixosModules.hardkernel-odroid-hc4
        nixos-odroid-hc4.nixosModules.odroid-hc4
        ./configuration.nix
        ./sd-image.nix
        {hardware.odroid-hc4.enable = true;}
      ];
    };
  };
}
