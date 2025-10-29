{ ... }:
{
  mkPopulateRPIBootPartitionCommands = { pkgs, config }:
    let
      kernelParamsFile = pkgs.writeTextFile {
        name = "cmdline.txt";
        text = ''
          ${pkgs.lib.strings.concatStringsSep " " config.boot.kernelParams}
        '';
      };
    
      output_directory = "firmware";
      populateCommands = 
        # Copy either our kernel image over or our uboot image over, depending on what's enabled
        # If uboot is enabled, then extlinux is enabled as well, which handles copying our initrd
        # and kernel and cmdline.txt
        (if config.boot.loader.rpi-uboot.enable then
          ["cp ${config.boot.loader.rpi-uboot.package}/u-boot.bin ${output_directory}/${config.rpi-nix.rpi-partition.kernelFilename}"]
        else [
          # Copy our kernel over
          ''cp "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" ${output_directory}/${config.rpi-nix.rpi-partition.kernelFilename}''
          # Copy our kernel parameters over
          ''cp "${kernelParamsFile}" ${output_directory}/cmdline.txt''
          # We sometimes use custom kernels that have the needed drivers to mount the rootfs
          # compiled into it, so we can skip the ramdisk if needed
          (if config.boot.loader.rpi.useRamdisk then
             ''cp "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}" ${output_directory}/${config.boot.loader.rpi.ramdiskFilename}''
          else '''')
        ]) ++
        [
          # Copy all the Broadcom-specific files to the firmware directory
          # We need to use nullglob here as we want BASH to try to expand the wildcards and not
          # leave them as-is (*.bin) if they don't exist, so we include the set and disable
          # here
          "shopt -s nullglob"
          "cp -r ${config.rpi-nix.rpi-partition.firmware}/boot/{start*.elf,*.bin,*.dtb,fixup*.dat,overlays} ${output_directory}"
          "shopt -u nullglob"
          # Copy our RPI bootloader config.txt file to the firmware directory
          "cp ${config.rpi-nix.rpi-partition.configFile} ${output_directory}/config.txt"
        ];
    in
      pkgs.lib.concatStringsSep "\n" populateCommands;
}
