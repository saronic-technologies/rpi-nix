{
  description = "raspberry-pi nixos configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    rpi-firmware-src = {
      flake = false;
      url = "github:raspberrypi/firmware/1.20241008";
    };
  };

  outputs = srcs@{ flake-utils, ... }:
    flake-utils.lib.meld srcs [
      ./nix/modules
    ];
}
