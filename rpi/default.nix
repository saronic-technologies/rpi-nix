{ pinned, core-overlay, libcamera-overlay, rpi-firmware-src }:
{ lib, pkgs, config, ... }:

let
  cfg = config.raspberry-pi-nix;
  # version = cfg.kernel-version;
  # board = cfg.board;

  # Build the default firmware to be used for our RPI image.
  # We set our "firmwareDerivation" parameter to this, but
  # it can be overridden by the caller to provide a custom firmware set,
  # such as including specific DTO's and DTB's
in
{
  # Include the bootloader so we can set the "rpi" option for our installBootloader
  # parameter
  imports = [ ./config.nix ./i2c.nix ../bootloader ];

  options = with lib; {
    raspberry-pi-nix = {
        # kernel-version = mkOption {
        #   default = "v6_6_51";
        #   type = types.str;
        #   description = "Kernel version to build.";
        # };
        # board = mkOption {
        #   type = types.enum [ "bcm2711" "bcm2712" ];
        #   description = ''
        #     The kernel board version to build.
        #     Examples at: https://www.raspberrypi.com/documentation/computers/linux_kernel.html#native-build-configuration
        #     without the _defconfig part.
        #   '';
        # };

        # kernelFilename = mkOption {
        #   type = types.string;
        #   default = "kernel.img";
        #   description = ''
        #     Filename of the kernel image in the boot partition.
        #   '';
        # };

      # !!! We need to do this in the RPI config, as the config needs this filename
      # !!! as one of its parameters.  We are just hard-injecting it for now in our
      # !!! pre-rendered config for the RevPi
      ramdiskFilename = mkOption {
        type = types.string;
        default = "initrd";
        description = "Filename of the initrd in the boot partition.";
      };
        # firmwareDerivation = mkOption {
        #   type = types.package;
        #   default = defaultFirmware;
        #   description = ''Firmware derivation to use.  Defaults to github:raspberrypi/firmware/1.20241008'';
        # };
        # firmware-partition-label = mkOption {
        #   default = "FIRMWARE";
        #   type = types.str;
        #   description = "label of rpi firmware partition";
        # };
      pin-inputs = {
        enable = mkOption {
          default = true;
          type = types.bool;
          description = ''
            Whether to pin the kernel to the latest cachix build.
          '';
        };
      };
      libcamera-overlay = {
        enable = mkOption {
          default = true;
          type = types.bool;
          description = ''
            If enabled then the libcamera overlay is applied which
            overrides libcamera with the rpi fork.
          '';
        };
      };
        # uboot = {
        #   enable = mkOption {
        #     default = false;
        #     type = types.bool;
        #     description = ''
        #       If enabled then uboot is used as the bootloader. If disabled
        #       then the linux kernel is installed directly into the
        #       firmware directory as expected by the raspberry pi boot
        #       process.

        #       This can be useful for newer hardware that doesn't yet have
        #       uboot compatibility or less common setups, like booting a
        #       cm4 with an nvme drive.
        #     '';
        #   };

        #   package = mkPackageOption pkgs "uboot-rpi-arm64" { };
        # };
      serial-console = {
        enable = mkOption {
          default = true;
          type = types.bool;
          description = ''
            Whether to enable a console on serial0.

            Corresponds with raspi-config's setting
            "Would you like a login shell to be accessible over serial?"
          '';
        };
      };
      extraUDEVRules = {
        enable = mkOption {
          default = true;
          type = types.bool;
          description = ''
            Whether we need the extra udev rules for the RPI.
          '';
        };
      };
        # useRamdisk = {
        #   enable = mkOption {
        #     default = true;
        #     type = types.bool;
        #     description = ''
        #       whether we want to use a ramdisk.  if we compile all our modules straight into
        #       our kernel, we don't require it.
        #     '';
        #   };
        # };
    };
  };

  config = {
    # Default config.txt on Raspberry Pi OS:
    # https://github.com/RPi-Distro/pi-gen/blob/master/stage1/00-boot-files/files/config.txt
    hardware.raspberry-pi.config = {
      cm4 = {
        options = {
          otg_mode = {
            enable = lib.mkDefault true;
            value = lib.mkDefault true;
          };
        };
      };
      pi4 = {
        options = {
          arm_boost = {
            enable = lib.mkDefault true;
            value = lib.mkDefault true;
          };
        };
      };
      all = {
        options = {
          # The firmware will start our u-boot binary rather than a
          # linux kernel if we have uboot enabled.
          kernel = {
            enable = true;
            value = if cfg.uboot.enable then "u-boot-rpi-arm64.bin" else cfg.kernelFilename;
          };
          ramfsfile = {
            enable = !cfg.uboot.enable;
            value = "initrd";
          };
          ramfsaddr = {
            enable = !cfg.uboot.enable;
            value = -1;
          };
          arm_64bit = {
            enable = true;
            value = true;
          };
          enable_uart = {
            enable = true;
            value = true;
          };
          avoid_warnings = {
            enable = lib.mkDefault true;
            value = lib.mkDefault true;
          };
          camera_auto_detect = {
            enable = lib.mkDefault true;
            value = lib.mkDefault true;
          };
          display_auto_detect = {
            enable = lib.mkDefault true;
            value = lib.mkDefault true;
          };
          disable_overscan = {
            enable = lib.mkDefault true;
            value = lib.mkDefault true;
          };
        };
        dt-overlays = {
          vc4-kms-v3d = {
            enable = lib.mkDefault true;
            params = { };
          };
        };
      };
    };

    nixpkgs = {
      overlays =
        let
          rpi-overlays = [ core-overlay ]
            ++ (if config.raspberry-pi-nix.libcamera-overlay.enable
          then [ libcamera-overlay ] else [ ]);
          rpi-overlay = lib.composeManyExtensions rpi-overlays;
          pin-prev-overlay = overlay: pinned-prev: final: prev:
            let
              # apply the overlay to pinned-prev and fix that so no references to the actual final
              # and prev appear in applied-overlay
              applied-overlay =
                lib.fix (final: pinned-prev // overlay final pinned-prev);
              # We only want to set keys that appear in the overlay, so restrict applied-overlay to
              # these keys
              restricted-overlay = lib.getAttrs (builtins.attrNames (overlay { } { })) applied-overlay;
            in
            prev // restricted-overlay;
        in
        if cfg.pin-inputs.enable
        then [ (pin-prev-overlay rpi-overlay pinned) ]
        else [ rpi-overlay ];
    };
    boot = {
      kernelParams =
        if cfg.uboot.enable then [ ]
        else builtins.concatLists [
          # If we have a console, we have to make sure to declare tty1 first to avoid it overriding
          # the console we declare.  If we declare tty1 after our actual console, then we will never get
          # messages over the serial connection
          (if cfg.serial-console.enable then [
            "console=tty1"
            # https://github.com/raspberrypi/firmware/issues/1539#issuecomment-784498108
            "console=serial0,115200n8"
          ] else [ ]
          )
        ];
      initrd = if cfg.useRamdisk.enable then {
        availableKernelModules = [
          "usbhid"
          "usb_storage"
          "vc4"
          "pcie_brcmstb" # required for the pcie bus to work
          "reset-raspberrypi" # required for vl805 firmware to load
        ];
      } else { includeDefaultModules = false; availableKernelModules = []; kernelModules = []; };
      # !!! I don't feel this is correct; the user should pass the kernel and configuration
      # !!! that they want, as opposed to it being forced here.  Any pre-made kernels should
      # !!! be available for use, but this shouldn't be thrown into the module here
      # kernelPackages = pkgs.linuxPackagesFor pkgs.rpi-kernels."${version}"."${board}";
      loader = {
        grub.enable = lib.mkDefault false;
        # If we are using uboot, it uses generic-ext-linux, but otherwise we need to
        # use our custom bootloader.
        rpi.enable = !cfg.uboot.enable;
        # If we want to use a script that modifies /sbin/init when we switch
        # to a configuration.
        # !!! This script does not modify the kernel/initrd/dtbs/firmware on the boot sector,
        # !!! so I have no idea why it's an "installBootloader" script
        initScript.enable = lib.mkDefault false;# !cfg.uboot.enable;
        generic-extlinux-compatible = {
          # extlinux puts all our information into a configuration file that is read when
          # extlinux is called by uboot
          enable = lib.mkDefault cfg.uboot.enable;
          # We want to use the device tree provided by firmware, so don't
          # add FDTDIR to the extlinux conf file.
          useGenerationDeviceTree = lib.mkDefault false;
        };
      };
    };
    # hardware.enableRedistributableFirmware = true;

    # users.groups = builtins.listToAttrs (map (k: { name = k; value = { }; })
    #   [ "input" "sudo" "plugdev" "games" "netdev" "gpio" "i2c" "spi" ]);
    # services = {
    #   # Only provide the extra rules if we configure it
    #   udev.extraRules = if cfg.extraUDEVRules.enable then
    #     let shell = "${pkgs.bash}/bin/bash";
    #     in ''
    #       # https://raw.githubusercontent.com/RPi-Distro/raspberrypi-sys-mods/master/etc.armhf/udev/rules.d/99-com.rules
    #       SUBSYSTEM=="input", GROUP="input", MODE="0660"
    #       SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
    #       SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"
    #       SUBSYSTEM=="*gpiomem*", GROUP="gpio", MODE="0660"
    #       SUBSYSTEM=="rpivid-*", GROUP="video", MODE="0660"

    #       KERNEL=="vcsm-cma", GROUP="video", MODE="0660"
    #       SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"

    #       SUBSYSTEM=="gpio", GROUP="gpio", MODE="0660"
    #       SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", PROGRAM="${shell} -c 'chgrp -R gpio /sys/class/gpio && chmod -R g=u /sys/class/gpio'"
    #       SUBSYSTEM=="gpio", ACTION=="add", PROGRAM="${shell} -c 'chgrp -R gpio /sys%p && chmod -R g=u /sys%p'"

    #       # PWM export results in a "change" action on the pwmchip device (not "add" of a new device), so match actions other than "remove".
    #       SUBSYSTEM=="pwm", ACTION!="remove", PROGRAM="${shell} -c 'chgrp -R gpio /sys%p && chmod -R g=u /sys%p'"

    #       KERNEL=="ttyAMA[0-9]*|ttyS[0-9]*", PROGRAM="${shell} -c '\
    #               ALIASES=/proc/device-tree/aliases; \
    #               TTYNODE=$$(readlink /sys/class/tty/%k/device/of_node | sed 's/base/:/' | cut -d: -f2); \
    #               if [ -e $$ALIASES/bluetooth ] && [ $$TTYNODE/bluetooth = $$(strings $$ALIASES/bluetooth) ]; then \
    #                   echo 1; \
    #               elif [ -e $$ALIASES/console ]; then \
    #                   if [ $$TTYNODE = $$(strings $$ALIASES/console) ]; then \
    #                       echo 0;\
    #                   else \
    #                       exit 1; \
    #                   fi \
    #               elif [ $$TTYNODE = $$(strings $$ALIASES/serial0) ]; then \
    #                   echo 0; \
    #               elif [ $$TTYNODE = $$(strings $$ALIASES/serial1) ]; then \
    #                   echo 1; \
    #               else \
    #                   exit 1; \
    #               fi \
    #       '", SYMLINK+="serial%c"

    #       ACTION=="add", SUBSYSTEM=="vtconsole", KERNEL=="vtcon1", RUN+="${shell} -c '\
    #       	if echo RPi-Sense FB | cmp -s /sys/class/graphics/fb0/name; then \
    #       		echo 0 > /sys$devpath/bind; \
    #       	fi; \
    #       '"
    #     ''
    #     else '''';
    # };
  };

}
