SHELL := cmd.exe

ROOT := $(subst /,\,$(CURDIR))
POWERSHELL ?= powershell.exe
LAZARUS_DIR ?= $(ROOT)\tools\lazarus
LAZBUILD ?= $(LAZARUS_DIR)\lazbuild.exe
ARCH ?= x64
BUILD_MODE ?= Release 64-Bit

.PHONY: all help check-tools build build-32 build-64 run clean

all: build

help:
	@echo Cheat Engine Windows build targets:
	@echo   make check-tools   Validate the repository-local Lazarus toolchain
	@echo   make build         Build the selected architecture (default: x64)
	@echo   make build-32      Build the 32-bit release
	@echo   make build-64      Build the 64-bit release
	@echo   make run           Build and run the selected architecture locally
	@echo   make clean         Remove generated main executables
	@echo.
	@echo Override paths when needed:
	@echo   make LAZARUS_DIR=C:\path\to\lazarus build

check-tools:
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action CheckTools -Architecture "$(ARCH)" -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"

build: check-tools
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action Build -Architecture "$(ARCH)" -BuildMode "$(BUILD_MODE)" -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"

build-32:
	@$(MAKE) ARCH=x86 BUILD_MODE="Release 32-Bit" build

build-64:
	@$(MAKE) ARCH=x64 BUILD_MODE="Release 64-Bit" build

run: build
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action Run -Architecture "$(ARCH)" -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"

clean:
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action Clean -Architecture "$(ARCH)" -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"
