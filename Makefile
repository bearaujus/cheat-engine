SHELL := cmd.exe

ROOT := $(subst /,\,$(CURDIR))
POWERSHELL ?= powershell.exe
LAZARUS_DIR ?= $(ROOT)\tools\lazarus
LAZBUILD ?= $(LAZARUS_DIR)\lazbuild.exe

.PHONY: all help check-tools build run test clean

all: build

help:
	@echo Cheat Engine Windows x64 build targets:
	@echo   make check-tools   Validate the repository-local Lazarus toolchain
	@echo   make build         Build the Windows x64 release
	@echo   make run           Build and run the Windows x64 release locally
	@echo   make test          Run the Windows x64 unit tests
	@echo   make clean         Remove generated x64 build outputs
	@echo.
	@echo Override paths when needed:
	@echo   make LAZARUS_DIR=C:\path\to\lazarus build

check-tools:
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action CheckTools -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"

build: check-tools
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action Build -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"

run:
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action Run -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"

test:
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action Test -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"

clean:
	@"$(POWERSHELL)" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(ROOT)\tools\build.ps1" -Action Clean -LazarusDir "$(LAZARUS_DIR)" -LazBuild "$(LAZBUILD)"
