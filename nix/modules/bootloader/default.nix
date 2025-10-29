# This module provides a file that can be used in the installBootloader field
# of a NixOS configuration; for RPI we just copy our new system to the /boot/firmware
# directory, so we need to have the configuration as a parameter as well as the firmware
# used for the specific system.

# We can re-use the firmware/kernel copy commands from the SD card builder here

{ rpi-firmware-src, ... }@inputs:
{ pkgs, lib, config, ... }:
let
  # Default RPI firmware incase it's not specified
  defaultFirmware = pkgs.stdenv.mkDerivation {
    name = "default-rpi-firmware";

    # Override with the specific firmware source that we want
    src = "${pkgs.raspberrypifw.overrideAttrs (oldfw: { src = rpi-firmware-src; })}";

    buildPhase = ''
      # The RPI firmware stores its results in share/raspberrypi for some reason, so we
      # just copy it out

      mkdir -p $out
      cp -r $src/share/raspberrypi/boot $out
    '';
  };
  bootPartitionHelpers = import ../../lib/populate_boot_partition.nix inputs;
in 
  with lib;
  {
    options = {
      # Partition-specific parameters for the RPI device, independent of the actual third-stage
      # bootloader

      rpi-nix = {
        rpi-partition = {
          configFile = mkOption {
            type = types.package;
            description = "The config.txt file for the RPI boot partition";
          };

          firmware = mkOption {
            type = types.package;
            default = defaultFirmware;
            description = ''Firmware derivation to use.  Defaults to github:raspberrypi/firmware/1.20241008'';
          };

          kernelFilename = mkOption {
            type = types.string;
            default = "kernel.img";
            description = ''
              Filename of the kernel image in the boot partition.
            '';
          };
        };
      };

      # RPI bootloader, which just keeps 1 kernel image in the boot partition along with the
      # device tree and such
      boot.loader.rpi = {
        enable = mkOption {
          default = false;
          type = types.bool;
          description = ''
            Raspberry PI bootloader installer that overwrites the /boot/firmware directory 
            with every "boot" switch.
          '';
        };

        ramdiskFilename = mkOption {
          type = types.string;
          default = "initrd";
          description = "Filename of the initrd in the boot partition.";
        };

        # Nix is buggy when we use initrd.enable = false; lots of code assumes it has to be there,
        # including uboot, so with our custom bootloader we can fix this a bit.
        useRamdisk = mkOption {
          default = true;
          type = types.bool;
          description = ''
            whether we want to use a ramdisk.  if we compile all our modules straight into
            our kernel, we don't require it.
          '';
        };
      };

      # RPI uboot bootloader, which tricks the RPI second-stage bootloader into thinking it's
      # a kernel image, so when it's loaded, it uses the device tree in combination with a kernel,
      # a cmdline.txt, and optional initrd to finish the boot process.

      boot.loader.rpi-uboot = {
        enable = mkOption {
          default = false;
          type = types.bool;
          description = ''
            If enabled then uboot is used as the bootloader. If disabled
            then the linux kernel is installed directly into the
            firmware directory as expected by the raspberry pi boot
            process.

            This can be useful for newer hardware that doesn't yet have
            uboot compatibility or less common setups, like booting a
            cm4 with an nvme drive.
          '';
        };
        # The uboot package to use, which corresponds to an arm64 RPI
        package = mkPackageOption pkgs "uboot-rpi-arm64" { };
      };
    };

    config = {
      boot = {
        loader = {
          # The RPI doesn't use GRUB
          grub.enable = lib.mkDefault false;
          # The RPI doesn't use initScript, as we need to manipulate the kernel
          # file as well as /sbin/init
          initScript.enable = lib.mkDefault false;
          # If we are using rpi-uboot, then extlinux will be used alongside it
          generic-extlinux-compatible = {
            # extlinux puts all our information into a configuration file that is read when
            # extlinux is called by uboot
            enable = lib.mkDefault config.boot.loader.rpi-uboot.enable;
            # We want to use the device tree provided by firmware, so don't
            # add FDTDIR to the extlinux conf file.
            useGenerationDeviceTree = lib.mkDefault false;
          };
        };
        consoleLogLevel = lib.mkDefault 7;
      };

      # If we are using the RPI bootloader, then modify our installBootLoader script to our
      # custom one
      system.build.installBootLoader = mkIf config.boot.loader.rpi.enable (
        let
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
              bootPartitionHelpers.mkPopulateRPIBootPartitionCommands { inherit config pkgs; }
              # Use our NixOS distro name
              config.system.nixos.distroName
              "### BOOTLOADER COPY COMMANDS START ###"
              "### BOOTLOADER COPY COMMANDS END ###"
            ]
            template;

          installRPIBootloader = pkgs.writeShellApplication {
            name = "install-rpi-bootloader";
            text = script_content;
            runtimeInputs = [ pkgs.openssh pkgs.gawk ];
          };
        in 
          "${installRPIBootloader}/bin/install-rpi-bootloader"
      );

    };
  }
