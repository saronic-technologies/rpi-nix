# This module provides a file that can be used in the installBootloader field
# of a NixOS configuration; for RPI we just copy our new system to the /boot/firmware
# directory, so we need to have the configuration as a parameter as well as the firmware
# used for the specific system.

# We can re-use the firmware/kernel copy commands from the SD card builder here

{ pkgs, lib, config, ... }:
let
  output_directory = "\"$BOOTLOADER_STAGING_DIRECTORY\"";
  copyCommands = pkgs.callPackage ./commands.nix { inherit output_directory; nix_config = config; };
  bootloaderCopyCommands = lib.concatStringsSep "\n"
    (copyCommands.kernelCopyCommands ++ copyCommands.firmwareCopyCommands);

  template = builtins.readFile ./install_rpi_bootloader.sh;
  script_content = builtins.replaceStrings
    [
      "@BOOTLOADER_COPY_COMMANDS@"
      "@DISTRO_NAME@"
    ]
    [
      bootloaderCopyCommands
      "Saronic RevPi NixOS"
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
          runtimeInputs = [ pkgs.openssh ];
        };
      in 
        "${installRPIBootloader}/bin/install-rpi-bootloader";
    };
  }
