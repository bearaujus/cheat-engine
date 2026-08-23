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

  1. Download Lazarus 2.2.2 from https://sourceforge.net/projects/lazarus/files/Lazarus%20Windows%2064%20bits/Lazarus%202.2.2/ First install lazarus-2.2.2-fpc-3.2.2-win64.exe and then lazarus-2.2.2-fpc-3.2.2-cross-i386-win32-win64.exe
  
  2. Run Lazarus and click on `Project->Open Project`. Select `cheatengine.lpi` from the `Cheat Engine` folder as the project.
  3. Click on `Run->Build` or press <kbd>SHIFT+F9</kbd>.
      * you can also click on `Run->Compile many Modes` (tip: select first three compile modes)
      * If you want to run or debug from the IDE on Windows you will need to run Lazarus as administrator.
      
  Do not forget to compile secondary projects you'd like to use:
  
     speedhack.lpr: Compile both 32- and 64-bit DLL's for speedhack capability
     luaclient.lpr: Compile both 32- and 64-bit DLL's for {$luacode} capability
     DirectXMess.sln: Compile for 32-bit and 64-bit for D3D overlay and snapshot capabilities
     DotNetcompiler.sln: for the cscompile lua command
     monodatacollector.sln: Compile both 32-bit and 64-bit dll's to get Mono features to inspect the .NET environment of the process    
     dotnetdatacollector.sln: Compile both 32- and 64-bit EXE's to get .NET symbols
     dotnetinvasivedatacollector.sln: Compile this managed .DLL to add support for runtime JIT support
     cejvmti.sln: Compile both 32- and 64-bit DLL's for Java inspection support
     tcclib.sln: Compile 32-32, 64-32 and 64-64 to add {$C} and {$CCODE} support in scripts
     vehdebug.lpr: Compile 32- and 64-bit DLL's to add support for the VEH debugger interface
     dbkkernel.sln: for kernelmode functions (settings->extra) You will need to build the no-sig version and either boot with unsigned driver support, or sign the driver yourself    
    
*.SLN files require visual studio (Usually 2017)

## Local Windows build and run

The repository includes a portable Lazarus 2.2.2/FPC 3.2.2 toolchain under `tools\lazarus`. The toolchain is used only to build the source checkout; no prebuilt Cheat Engine release is downloaded or executed.

From a Windows shell with GNU Make available:

```text
make check-tools
make build
make run
make build-32
make run ARCH=x86 BUILD_MODE="Release 32-Bit"
make clean
```

The default build is the 64-bit release and writes `Cheat Engine\bin\cheatengine-x86_64.exe`. The 32-bit release writes `Cheat Engine\bin\cheatengine-i386.exe`. `make run` starts the selected executable with `Cheat Engine\bin` as its working directory so the checked-in runtime files are used. It passes `NOAUTORUN` and `NOFIRSTTIME`, so local runs do not load autorun extensions or show first-run language/tutorial prompts; normal launches without those arguments are unchanged.

For the bundled FPC 3.2.2 compiler, the helper temporarily uses optimization level 0 for the selected build mode. This avoids an intermittent FPC internal compiler error; the committed Lazarus project file is restored byte-for-byte after each build.

The Makefile does not install files, drivers, services, or system-wide settings. The broader install/package workflow will be added separately after the complete distribution scope is defined. To use another Lazarus copy, override the path without changing project files:

```text
make LAZARUS_DIR=C:\path\to\lazarus build
```

The bundled toolchain is based on the official Lazarus 2.2.2 Windows 64-bit installer and i386 cross-compiler. Their SHA-256 checksums are listed on the official [Lazarus checksums page](https://www.lazarus-ide.org/index.php?page=checksums). The bundle includes upstream license files; review the applicable licenses before redistributing it.
