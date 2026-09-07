# SPDX-License-Identifier: MIT
{ ... }:
{

  overlay = final: prev: {
    uefi-shell-launcher = prev.uefi-shell-launcher or { };
  };

}
