# This module provides a file that can be used in the installBootloader field
# of a NixOS configuration; for RPI we just copy our new system to the /boot/firmware
# directory, so we need to have the configuration as a parameter as well as the firmware
# used for the specific system.

# We can re-use the firmware/kernel copy commands from the SD card builder here

{ pkgs, lib, config, ... }:
let
  output_directory = "tmp_firmware";
  bootloaderCopyCommands = lib.concatStringsSep
    "\n"
    (pkgs.callPackage ./commands.nix { inherit output_directory; nix_config = config; });

  template = builtins.readFile ./install_rpi_bootloader.sh;
  # Replace the placeholder with our generated checks
  script_content = builtins.replaceStrings
    [ "@BOOTLOADER_COPY_COMMANDS@" ]
    [ bootloaderCopyCommands ]
    template;
in 
  with lib;
  {
    options = {
      boot.loader.raspberryPi = {
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

    config = {
      system.build.installBootLoader = mkIf config.boot.loader.raspberryPi.enable
        pkgs.writeShellApplication {
          name = "install-rpi-bootloader";
          text = script_content;
          runtimeInputs = [ pkgs.openssh ];
        };
    };
  }
