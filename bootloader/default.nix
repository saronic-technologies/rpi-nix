# This module provides a file that can be used in the installBootloader field
# of a NixOS configuration; for RPI we just copy our new system to the /boot/firmware
# directory, so we need to have the configuration as a parameter as well as the firmware
# used for the specific system.

# We can re-use the firmware/kernel copy commands from the SD card builder here

{ pkgs, lib, config, ... }:
let
  # Our output directory is a BASH variable that is filled in when the script
  # is executed
  output_directory = "\"$BOOTLOADER_STAGING_DIRECTORY\"";

  # Create our copy commands

  # We can use our toplevel config to generate the commands, as our config contains our firmwareDerivation
  # as well as the standard kernel/initrd, alongside our generators for cmdline.txt and config.txt, which are
  # RPI-specific
  copyCommands = pkgs.callPackage ./commands.nix { inherit output_directory; nix_config = config; };
  bootloaderCopyCommands = lib.concatStringsSep "\n"
    (copyCommands.kernelCopyCommands ++ copyCommands.firmwareCopyCommands);

  # Build our templace, replacing the required strings
  template = builtins.readFile ./install_rpi_bootloader.sh;
  script_content = builtins.replaceStrings
    [
      "@BOOTLOADER_COPY_COMMANDS@"
      "@DISTRO_NAME@"
      "@BOOTLOADER_COPY_COMMANDS_START@"
      "@BOOTLOADER_COPY_COMMANDS_END@"
    ]
    [
      bootloaderCopyCommands
      # Use our NixOS distro name
      config.system.nixos.distroName
      "### BOOTLOADER COPY COMMANDS START ###"
      "### BOOTLOADER COPY COMMANDS END ###"
    ]
    template;
in 
  with lib;
  {
    options = {
      boot.loader.rpi = {
        enable = mkOption {
          default = false;
          type = types.bool;
          description = ''
            Raspberry PI bootloader installer that overwrites the /boot/firmware directory 
            with every "boot" switch.
          '';
        };
      };
    };

    config = mkIf config.boot.loader.rpi.enable {
      system.build.installBootLoader =
      let
        installRPIBootloader = pkgs.writeShellApplication {
          name = "install-rpi-bootloader";
          text = script_content;
          runtimeInputs = [ pkgs.openssh pkgs.gawk ];
        };
      in 
        "${installRPIBootloader}/bin/install-rpi-bootloader";
    };
  }
