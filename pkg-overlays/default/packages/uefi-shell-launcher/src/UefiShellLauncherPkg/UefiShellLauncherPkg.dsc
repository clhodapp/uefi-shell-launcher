## @file
#  Platform description for the UEFI shell launcher.
#  Library mapping follows ShellPkg/ShellPkg.dsc.
#
#  SPDX-License-Identifier: MIT
##
[Defines]
  PLATFORM_NAME                  = UefiShellLauncher
  PLATFORM_GUID                  = 2a29d244-0659-4785-aa6d-b9383e672a40
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION              = 0x00010006
  OUTPUT_DIRECTORY               = Build/UefiShellLauncher
  SUPPORTED_ARCHITECTURES        = IA32|X64|AARCH64|RISCV64
  BUILD_TARGETS                  = DEBUG|RELEASE|NOOPT
  SKUID_IDENTIFIER               = DEFAULT

!include MdePkg/MdeLibs.dsc.inc

[LibraryClasses.common]
  UefiApplicationEntryPoint|MdePkg/Library/UefiApplicationEntryPoint/UefiApplicationEntryPoint.inf
  UefiBootServicesTableLib|MdePkg/Library/UefiBootServicesTableLib/UefiBootServicesTableLib.inf
  UefiRuntimeServicesTableLib|MdePkg/Library/UefiRuntimeServicesTableLib/UefiRuntimeServicesTableLib.inf
  DevicePathLib|MdePkg/Library/UefiDevicePathLib/UefiDevicePathLibOptionalDevicePathProtocol.inf
!if $(TARGET) == RELEASE
  DebugLib|MdePkg/Library/BaseDebugLibNull/BaseDebugLibNull.inf
!else
  DebugLib|MdePkg/Library/UefiDebugLibConOut/UefiDebugLibConOut.inf
!endif
  DebugPrintErrorLevelLib|MdePkg/Library/BaseDebugPrintErrorLevelLib/BaseDebugPrintErrorLevelLib.inf
  PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  MemoryAllocationLib|MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  UefiLib|MdePkg/Library/UefiLib/UefiLib.inf
  BaseLib|MdePkg/Library/BaseLib/BaseLib.inf
  BaseMemoryLib|MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  PrintLib|MdePkg/Library/BasePrintLib/BasePrintLib.inf

[PcdsFixedAtBuild]
  gEfiMdePkgTokenSpaceGuid.PcdDebugPropertyMask|0xFF
  gEfiMdePkgTokenSpaceGuid.PcdUefiLibMaxPrintBufferSize|16000

[Components]
  UefiShellLauncherPkg/UefiShellLauncher/UefiShellLauncher.inf
