{ config, lib, pkgs, ... }:

{
  imports = [ ./sd-image.nix ];

  config = {
    boot.loader.grub.enable = false;

    boot.consoleLogLevel = lib.mkDefault 7;

    boot.kernelParams = [
      # This is ugly and fragile, but the sdImage image has an msdos
      # table, so the partition table id is a 1-indexed hex
      # number. So, we drop the hex prefix and stick on a "02" to
      # refer to the root partition.

      # !!! The Linux kernel does something with this when it handles its initrd;
      # !!! this is pointing to the boot partition
      # !!! Nix checks the cmdline and links /dev/root if we specify a UUID instead of a PARTUUID
      "root=PARTUUID=${lib.strings.removePrefix "0x" config.sdImage.firmwarePartitionID}-02"
      "rootfstype=ext4"
      "fsck.repair=yes"
      "rootwait"
    ];

    sdImage =
      let
        kernel-params = pkgs.writeTextFile {
          name = "cmdline.txt";
          text = ''
            ${lib.strings.concatStringsSep " " config.boot.kernelParams}
          '';
        };
        cfg = config.raspberry-pi-nix;
        kernel = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
        initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
        populate-kernel =
          if cfg.uboot.enable
          then ''
            cp ${cfg.uboot.package}/u-boot.bin firmware/u-boot-rpi-arm64.bin
          ''
          else ''
            cp "${kernel}" firmware/${cfg.firmwareKernelFilename}
            cp "${initrd}" firmware/initrd
            cp "${kernel-params}" firmware/cmdline.txt
          '';
      in
      {
        populateFirmwareCommands = ''
          ${populate-kernel}
          cp -r ${cfg.firmwareDerivation}/boot/{start*.elf,*.dtb,bootcode.bin,fixup*.dat,overlays} firmware
          cp ${config.hardware.raspberry-pi.config-output} firmware/config.txt
        '';
        populateRootCommands =
          if cfg.uboot.enable
          then ''
            mkdir -p ./files/boot
            ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
          ''
          else ''
            mkdir -p ./files/sbin
            # Write a script that executes the Nix stage 2, as we know its
            # exact path in the toplevel that we have configured
            content="$(
              echo "#!${pkgs.bash}/bin/bash"
              echo "exec ${config.system.build.toplevel}/init"
            )"
            echo "$content" > ./files/sbin/init
            chmod 744 ./files/sbin/init
          '';
      };
  };
}
