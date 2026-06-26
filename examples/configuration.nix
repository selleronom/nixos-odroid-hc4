# Minimal HC4 host configuration shared by the running system and the SD image.
# Replace the placeholders (hostname, user, SSH key) with your own.
{...}: {
  networking.hostName = "hc4";

  # Amlogic S905X3 boots via extlinux — no GRUB/EFI.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.kernelParams = [
    "console=ttyAML0,115200n8" # Amlogic UART (serial console)
    "console=tty0"
  ];

  # Headless access. Drop your public key in here so you can reach the box
  # after first boot.
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAA... you@host"
  ];

  system.stateVersion = "25.11";
}
