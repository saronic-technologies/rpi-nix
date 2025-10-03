{ config, lib, pkgs, ... }:

{
  imports = [ ./sd-image.nix  ];

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
      # Our sd-image creates the /sbin/init binary in our root partition, so we tell the kernel
      # that's the file we want to boot when it's time to initialize officially
      "init=/sbin/init"
    ];

    sdImage =
      let
        cfg = config.raspberry-pi-nix;
        # Create our copy commands using our shared code
        copyCommands = pkgs.callPackage ../bootloader/commands.nix {
          nix_config = config;
          output_directory = "firmware";
        };
          # kernel-params = pkgs.writeTextFile {
          #   name = "cmdline.txt";
          #   text = ''
          #     ${lib.strings.concatStringsSep " " config.boot.kernelParams}
          #   '';
          # };
          # cfg = config.raspberry-pi-nix;
          # kernel = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";

          # initrd = if cfg.useRamdisk then 
          #   "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}"
          # else "";

          # # Create our copy commands array based on our parameters
          # kernelCopyCommands = [] ++
          #   (if cfg.uboot.enable then
          #      ["cp ${cfg.uboot.package}/u-boot.bin firmware/u-boot-rpi-arm64.bin"]
          #    else []) ++ 
          #   # We sometimes use custom kernels that have the needed drivers to mount the rootfs
          #   # compiled into it, so we can skip the ramdisk if needed
          #   (if cfg.useRamdisk.enable then
          #      [''cp ${initrd} firmware/${cfg.ramdiskFilename}'']
          #    else []
          #   ) ++ 
          #   [
          #     # Copy our kernel over
          #     ''cp "${kernel}" firmware/${cfg.kernelFilename}''
          #     ''cp "${kernel-params}" firmware/cmdline.txt''
          #   ];

          # firmwareCopyCommands = 
          #   [
          #     # Copy all the Broadcom-specific files to the firmware directory
          #     "cp -r ${cfg.firmwareDerivation}/boot/{start*.elf,*.bin,*.dtb,fixup*.dat,overlays} firmware"
          #     # Copy our RPI bootloader config.txt file to the firmware directory
          #     "cp ${config.hardware.raspberry-pi.config-output} firmware/config.txt"
          #   ];
      in
      {
        # Concatenate our kernel copy and our firmware copy commands as our firmware commands
        populateBootPartitionCommands = pkgs.lib.concatStringsSep "\n" (copyCommands.kernelCopyCommands ++ copyCommands.firmwareCopyCommands);
        populateRootPartitionCommands =
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
