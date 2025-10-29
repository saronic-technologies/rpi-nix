{ ... }@inputs:
{
  nixosModules = {
    bootloader = import ./bootloader inputs;
    sd-image = import ./sd-image.nix inputs;
  };
}
