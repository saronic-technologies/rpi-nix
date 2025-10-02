# This file generates the commands needed to fill an RPI bootloader.
# It involves copying the kernel, ramdisk (if required), Broadcom firmware,
# dtb's, overlays, config.txt, and cmdline.txt

{ pkgs, lib, nix_config, output_directory }:
let
  kernel-params = pkgs.writeTextFile {
    name = "cmdline.txt";
    text = ''
      ${lib.strings.concatStringsSep " " nix_config.boot.kernelParams}
    '';
  };
  cfg = nix_config.raspberry-pi-nix;
  kernel = "${nix_config.system.build.kernel}/${nix_config.system.boot.loader.kernelFile}";
  
  initrd = if cfg.useRamdisk then 
    "${nix_config.system.build.initialRamdisk}/${nix_config.system.boot.loader.initrdFile}"
  else "";
in
{
  # Create our copy commands array based on our parameters
  kernelCopyCommands = [] ++
    (if cfg.uboot.enable then
       ["cp ${cfg.uboot.package}/u-boot.bin ${output_directory}/u-boot-rpi-arm64.bin"]
     else []) ++ 
    # We sometimes use custom kernels that have the needed drivers to mount the rootfs
    # compiled into it, so we can skip the ramdisk if needed
    (if cfg.useRamdisk.enable then
       [''cp ${initrd} ${output_directory}/${cfg.ramdiskFilename}'']
     else []
    ) ++ 
    [
      # Copy our kernel over
      ''cp "${kernel}" ${output_directory}/${cfg.kernelFilename}''
      # Copy our kernel parameters over
      ''cp "${kernel-params}" ${output_directory}/cmdline.txt''
    ];
  
  firmwareCopyCommands = 
    [
      # Copy all the Broadcom-specific files to the firmware directory
      "cp -r ${cfg.firmwareDerivation}/boot/{start*.elf,*.bin,*.dtb,fixup*.dat,overlays} ${output_directory}"
      # Copy our RPI bootloader config.txt file to the firmware directory
      "cp ${nix_config.hardware.raspberry-pi.config-output} ${output_directory}/config.txt"
    ];
}
