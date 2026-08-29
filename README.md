<p align="center">
    <a href="https://github.com/cheat-engine/cheat-engine/raw/master/Cheat%20Engine/images">
        <img src="https://github.com/cheat-engine/cheat-engine/raw/master/Cheat%20Engine/images/celogo.png" />
    </a>
</p>

<h1 align="center">Cheat Engine</h1>

Cheat Engine is a development environment focused on modding games and applications for personal use.


# Download

  * **[Latest Version](https://github.com/cheat-engine/cheat-engine/releases/latest)**

[Older versions](https://github.com/cheat-engine/cheat-engine/releases)


# Links

  * [Website](https://www.cheatengine.org)
  * [Forum](https://forum.cheatengine.org)
  * [Forum (alternate)](https://opencheattables.com/)
  * [Forum (alternate)](https://fearlessrevolution.com/index.php)
  * [Wiki](https://wiki.cheatengine.org/index.php?title=Main_Page)

## Social Media

  * [Reddit](https://reddit.com/r/cheatengine)
  * [Twitter](https://twitter.com/_cheatengine)

## Donate

  * [Patreon](https://www.patreon.com/cheatengine)
  * [PayPal](https://www.paypal.com/xclick/business=dark_byte%40hotmail.com&no_note=1&tax=0&lc=US)


## Basic Build Instructions

This fork supports Windows x64 only.

  1. Download the 64-bit Lazarus 2.2.2/FPC 3.2.2 Windows installer from https://sourceforge.net/projects/lazarus/files/Lazarus%20Windows%2064%20bits/Lazarus%202.2.2/ or use the repository-local toolchain.

  2. Run Lazarus and click on `Project->Open Project`. Select `cheatengine.lpi` from the `Cheat Engine` folder as the project.
  3. Click on `Run->Build` or press <kbd>SHIFT+F9</kbd>.
      * Select `Release 64-Bit` or the unoptimized `Debug 64-Bit` mode.
      * If you want to run or debug from the IDE on Windows you will need to run Lazarus as administrator.

  Do not forget to compile secondary projects you'd like to use:

     speedhack.lpr: Compile the 64-bit DLL for speedhack capability
     luaclient.lpr: Compile the 64-bit DLL for {$luacode} capability
     DirectXMess.sln: Compile the 64-bit components for D3D overlay and snapshot capabilities
     DotNetcompiler.sln: for the cscompile lua command
     monodatacollector.sln: Compile the 64-bit DLL to inspect Mono/.NET environments
     dotnetdatacollector.sln: Compile the 64-bit EXE to get .NET symbols
     dotnetinvasivedatacollector.sln: Compile this managed .DLL to add support for runtime JIT support
     cejvmti.sln: Compile the 64-bit DLL for Java inspection support
     tcclib.sln: Compile the 64-64 target to add {$C} and {$CCODE} support in scripts
     vehdebug.lpr: Compile the 64-bit DLL to add support for the VEH debugger interface
     dbkkernel.sln: for kernelmode functions (settings->extra) You will need to build the no-sig version and either boot with unsigned driver support, or sign the driver yourself

*.SLN files require visual studio (Usually 2017)

## Local Windows build and run

The repository includes a portable Lazarus 2.2.2/FPC 3.2.2 toolchain under `tools\lazarus`. The toolchain is used only to build the source checkout; no prebuilt Cheat Engine release is downloaded or executed.

From a Windows shell with GNU Make available:

```text
make check-tools
make build
make run
make test
make clean
```

`make build` always writes the Release x64 executable to `Cheat Engine\bin\cheatengine-x86_64.exe`; `make run` builds and starts that same executable with `Cheat Engine\bin` as its working directory. The IDE-only `Debug 64-Bit` mode writes `Cheat Engine\bin\cheatengine-x86_64-debug.exe`. Local runs pass `NOAUTORUN` and `NOFIRSTTIME`, so they do not load autorun extensions or show first-run language/tutorial prompts; normal launches without those arguments are unchanged.

The supported release treats every compiler warning as a build failure. The documented compatibility exceptions are FPC warnings 4104/4105 at the legacy LCL UTF-8 and Windows UTF-16 boundary, plus FPC note 6058 from optional inline optimizations in the precompiled Lazarus 2.2.2 units. The string boundary requires a dedicated typed-string migration rather than potentially lossy casts; note 6058 does not affect correctness.

For the bundled FPC 3.2.2 compiler, the helper temporarily uses optimization level 0 for the Release mode. This avoids an intermittent FPC internal compiler error; the committed Lazarus project file is restored byte-for-byte after each build.

The Makefile does not install files, drivers, services, or system-wide settings. The broader install/package workflow will be added separately after the complete distribution scope is defined. To use another Lazarus copy, override the path without changing project files:

```text
make LAZARUS_DIR=C:\path\to\lazarus build
```

The bundled toolchain is based on the official Lazarus 2.2.2 Windows 64-bit installer. Its SHA-256 checksum is listed on the official [Lazarus checksums page](https://www.lazarus-ide.org/index.php?page=checksums). The bundle includes upstream license files; review the applicable licenses before redistributing it.
