# This file generates the commands needed to fill an RPI bootloader.
# It involves copying the kernel, ramdisk (if required), Broadcom firmware,
# dtb's, overlays, config.txt, and cmdline.txt
# It uses the current nix configuration to get the parameters of the system being
# built to generate the commands for that system.

{ pkgs, lib, nix_config, output_directory }:
let
  kernel-params = pkgs.writeTextFile {
    name = "cmdline.txt";
    text = ''
      ${lib.strings.concatStringsSep " " nix_config.boot.kernelParams}
    '';
  };
  cfg = nix_config.raspberry-pi-nix;
in
{
  # Create our copy commands array based on our parameters
  kernelCopyCommands = [] ++
    # Copy either our kernel image over or our uboot image over, depending on what's enabled
    # If uboot is enabled, then extlinux is enabled as well, which handles copying our initrd
    # and kernel and cmdline.txt
    (if cfg.uboot.enable then
       ["cp ${cfg.uboot.package}/u-boot.bin ${output_directory}/${cfg.kernelFilename}"]
     else [
       # Copy our kernel over
       ''cp "${nix_config.system.build.kernel}/${nix_config.system.boot.loader.kernelFile}" ${output_directory}/${cfg.kernelFilename}''
       # Copy our kernel parameters over
       ''cp "${kernel-params}" ${output_directory}/cmdline.txt''
       # We sometimes use custom kernels that have the needed drivers to mount the rootfs
       # compiled into it, so we can skip the ramdisk if needed
       (if cfg.useRamdisk.enable then
          ''cp "${nix_config.system.build.initialRamdisk}/${nix_config.system.boot.loader.initrdFile}" ${output_directory}/${cfg.ramdiskFilename}''
       else '''')
     ]);
  
  # Regardless of uboot or not, we have to copy these over as
  # they are the RPI first and second stage bootloader files 
  firmwareCopyCommands = 
    [
      # Copy all the Broadcom-specific files to the firmware directory
      "cp -r ${cfg.firmwareDerivation}/boot/{start*.elf,*.bin,*.dtb,fixup*.dat,overlays} ${output_directory}"
      # Copy our RPI bootloader config.txt file to the firmware directory
      "cp ${nix_config.hardware.raspberry-pi.config-output} ${output_directory}/config.txt"
    ];
}
