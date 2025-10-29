{ config, lib, pkgs, ... }:
let
  cfg = config.raspberry-pi-nix;
in 
{
  imports = [ ../bootloader  ];

  config = {
    boot.consoleLogLevel = lib.mkDefault 7;

    boot.kernelParams = [
      # This is ugly and fragile, but the sdImage image has an msdos
      # table, so the partition table id is a 1-indexed hex
      # number. So, we drop the hex prefix and stick on a "02" to
      # refer to the root partition.

      # This is the root partition; Linux uses this to figure out which partition
      # to use as the rootfs partition
      "root=PARTUUID=${lib.strings.removePrefix "0x" config.sdImage.firmwarePartitionID}-02"
      "rootfstype=ext4"
      "fsck.repair=yes"
      "rootwait"
      # Our sd-image creates the /sbin/init binary in our root partition, so we tell the kernel
      # that's the file we want to boot when it's time to initialize officially
    ] ++ (if cfg.uboot.enable then [] else ["init=/sbin/init"]);

    sdImage =
      let
        # Create our copy commands using our shared code
        # copyCommands = pkgs.callPackage ../bootloader/commands.nix {
        #   nix_config = config;
        #   output_directory = "firmware";
        # };
      in
      {
        compressImage = true;
        rootVolumeLabel = "NIXOS_SD";
        # Concatenate our kernel copy and our firmware copy commands as our firmware commands
        # populateFirmwareCommands = pkgs.lib.concatStringsSep "\n" (copyCommands.kernelCopyCommands ++ copyCommands.firmwareCopyCommands);
        populateImageCommands =
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
