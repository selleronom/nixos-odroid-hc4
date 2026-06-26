{
  description = "NixOS support for ODROID HC4 (Amlogic S905X3) — SD card boot fixes and U-Boot";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    # U-Boot must be cross-compiled from x86_64-linux; the FIP assembly
    # tools (meson64-tools) are x86_64 only.
    x86Pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    # NixOS module — import this in your configuration
    nixosModules = {
      default = self.nixosModules.odroid-hc4;
      odroid-hc4 = import ./modules;
    };

    # U-Boot package — needed for SD card image creation
    packages.x86_64-linux = {
      default = self.packages.x86_64-linux.uboot-odroid-hc4;
      uboot-odroid-hc4 = import ./uboot {
        pkgs = x86Pkgs.pkgsCross.aarch64-multiplatform;
      };
    };

    # Also expose for native aarch64 builds
    packages.aarch64-linux = {
      default = self.packages.aarch64-linux.uboot-odroid-hc4;
      uboot-odroid-hc4 = import ./uboot {
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
      };
    };

    # `nix fmt` for contributors.
    formatter.x86_64-linux = x86Pkgs.alejandra;
    formatter.aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.alejandra;
  };
}
