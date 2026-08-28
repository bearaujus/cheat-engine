# Bundled Windows build tools

`lazarus\` contains the portable Lazarus 2.2.2 and FPC 3.2.2 Windows x64 toolchain used by the root `Makefile`. The supported build uses only the x86-64 compiler from the official Lazarus Windows 64-bit release:

- `lazarus-2.2.2-fpc-3.2.2-win64.exe`

The installers were checksum-verified against the official Lazarus checksums page before extraction. The installers are intentionally not retained in this repository; `lazarus\` is the portable build tree.

The bundle includes upstream license files. Review the Lazarus and Free Pascal licensing terms before redistributing this directory.
