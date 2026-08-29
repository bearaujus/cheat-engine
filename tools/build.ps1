[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CheckTools', 'Build', 'Run', 'Test', 'Clean')]
    [string]$Action,

    [string]$LazarusDir,

    [string]$LazBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $repoRoot 'Cheat Engine\cheatengine.lpi'
$binDir = Join-Path $repoRoot 'Cheat Engine\bin'
$releaseBuildMode = 'Release 64-Bit'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This product supports Windows x64 only.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This product requires a 64-bit Windows operating system.'
}

if ([string]::IsNullOrWhiteSpace($LazarusDir)) {
    $LazarusDir = Join-Path $repoRoot 'tools\lazarus'
}

function Resolve-LazBuild {
    if (-not [string]::IsNullOrWhiteSpace($LazBuild) -and (Test-Path -LiteralPath $LazBuild -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $LazBuild).Path
    }

    $candidates = @(
        (Join-Path $LazarusDir 'lazbuild.exe'),
        (Join-Path $LazarusDir 'lazbuild.bat'),
        (Join-Path $LazarusDir 'lazbuild.cmd')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command lazbuild.exe, lazbuild.bat, lazbuild.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    throw "Unable to find lazbuild. Put Lazarus under '$LazarusDir' or pass LAZBUILD=<path>."
}

function Find-Tool([string[]]$Names) {
    foreach ($name in $Names) {
        $direct = Join-Path $LazarusDir $name
        if (Test-Path -LiteralPath $direct -PathType Leaf) {
            return (Resolve-Path -LiteralPath $direct).Path
        }
    }

    foreach ($name in $Names) {
        $found = Get-ChildItem -LiteralPath $LazarusDir -Recurse -File -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $found) {
            return $found.FullName
        }
    }

    return $null
}

function Get-ExpectedExecutable {
    return Join-Path $binDir 'cheatengine-x86_64.exe'
}

function Get-GeneratedUnitDirectory {
    return Join-Path $repoRoot 'Cheat Engine\lib\x86_64-win64'
}

function Assert-ExecutableNotRunning {
    $executable = Get-ExpectedExecutable
    $expectedPath = [System.IO.Path]::GetFullPath($executable)
    $expectedProcessName = [System.IO.Path]::GetFileNameWithoutExtension($expectedPath)

    foreach ($process in Get-Process -Name $expectedProcessName -ErrorAction SilentlyContinue) {
        $processPath = $null
        try {
            $processPath = $process.Path
        } catch [System.ComponentModel.Win32Exception] {
            # Elevated processes may hide their executable path from this shell.
        } catch [System.InvalidOperationException] {
            # The process exited while it was being inspected.
            continue
        }

        if ([string]::IsNullOrWhiteSpace($processPath)) {
            throw "Close the running '$($process.ProcessName)' instance (PID $($process.Id)) before building '$expectedPath'. Its executable path could not be inspected, usually because it is elevated."
        }

        if ([System.IO.Path]::GetFullPath($processPath).Equals(
                $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Close the running '$($process.ProcessName)' instance (PID $($process.Id)) before building '$expectedPath'."
        }
    }
}

function Clear-GeneratedUnits {
    $generatedDirectory = Get-GeneratedUnitDirectory
    if (-not (Test-Path -LiteralPath $generatedDirectory -PathType Container)) {
        return
    }

    $resolvedRepo = [System.IO.Path]::GetFullPath($repoRoot)
    $resolvedTarget = [System.IO.Path]::GetFullPath($generatedDirectory)
    $safePrefix = Join-Path $resolvedRepo 'Cheat Engine\lib\'
    if (-not $resolvedTarget.StartsWith(
        $safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unexpected generated-unit path: $resolvedTarget"
    }

    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    Write-Host "Removed stale generated units: $resolvedTarget"
}

function Write-CompilerOutputAndAssertClean(
    [object[]]$Output,
    [int]$ExitCode,
    [string]$CommandName
) {
    foreach ($line in $Output) {
        Write-Host "$line"
    }

    if ($ExitCode -ne 0) {
        throw "$CommandName failed with exit code $ExitCode."
    }

    $diagnostics = @($Output | Where-Object {
        "$_" -match '(?i)\b(note|warning|error|fatal):'
    })
    if ($diagnostics.Count -ne 0) {
        throw "$CommandName completed with $($diagnostics.Count) compiler diagnostic line(s)."
    }
}

function Assert-Project {
    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        throw "The Lazarus project was not found: $projectFile"
    }
}

function Assert-Tools {
    Assert-Project

    if (-not (Test-Path -LiteralPath $LazarusDir -PathType Container)) {
        throw "The Lazarus directory was not found: $LazarusDir"
    }

    $resolvedLazBuild = Resolve-LazBuild
    $compilerNames = @('ppcx64.exe', 'fpc.exe')
    $compiler = Find-Tool $compilerNames
    if ($null -eq $compiler) {
        throw "Unable to find an x64 FPC compiler under '$LazarusDir'."
    }

    $compilerBin = Split-Path -Parent $compiler
    $env:PATH = "$compilerBin;$LazarusDir;$env:PATH"

    Write-Host "Lazarus: $LazarusDir"
    Write-Host "lazbuild: $resolvedLazBuild"
    Write-Host "FPC: $compiler"
    return $resolvedLazBuild
}

function Invoke-LazBuild([string]$ResolvedLazBuild) {
    Assert-ExecutableNotRunning
    # FPC 3.2.2 can crash internally when this project incrementally reuses
    # units after widely referenced declarations change. A clean unit build is
    # slower but deterministic and avoids presenting compiler AVs to users.
    Clear-GeneratedUnits

    $projectBytes = [System.IO.File]::ReadAllBytes($projectFile)
    $projectText = [System.Text.Encoding]::UTF8.GetString($projectBytes)
    $buildModePattern = '(?s)(</ProjectOptions>\s*<CompilerOptions>.*?<OptimizationLevel Value=")3(")'
    $buildProjectText = [regex]::Replace($projectText, $buildModePattern, '${1}0${2}', 1)
    Write-Host "Building Windows x64 with mode '$releaseBuildMode'..."
    try {
        if ($buildProjectText -ne $projectText) {
            [System.IO.File]::WriteAllText($projectFile, $buildProjectText, [System.Text.UTF8Encoding]::new($false))
            Write-Host "Using optimization level 0 for FPC 3.2.2 compatibility."
        }

        $buildOutput = @(& $ResolvedLazBuild $projectFile "--build-mode=$releaseBuildMode" 2>&1)
        $buildExitCode = $LASTEXITCODE
        Write-CompilerOutputAndAssertClean $buildOutput $buildExitCode 'lazbuild'

        $executable = Get-ExpectedExecutable
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "Build completed but the expected executable was not created: $executable"
        }
    } finally {
        [System.IO.File]::WriteAllBytes($projectFile, $projectBytes)
    }

    Write-Host "Built: $executable"
}

function Invoke-Tests {
    $compilerNames = @('ppcx64.exe')
    $compiler = Find-Tool $compilerNames
    if ($null -eq $compiler) {
        throw 'Unable to find the x64 FPC test compiler.'
    }

    $testSource = Join-Path $repoRoot 'Cheat Engine\tests\memoryrecorddropdowntests.lpr'
    $unitPath = Join-Path $repoRoot 'Cheat Engine'
    $testOutput = Join-Path ([System.IO.Path]::GetTempPath()) (
        'cheat-engine-tests-x64-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testOutput -Force | Out-Null

    try {
        Write-Host 'Building dropdown tests for Windows x64...'
        $compilerOutput = @(& $compiler '-Mdelphi' '-Sew' "-Fu$unitPath" `
            "-FE$testOutput" "-FU$testOutput" $testSource 2>&1)
        $compilerExitCode = $LASTEXITCODE
        Write-CompilerOutputAndAssertClean $compilerOutput $compilerExitCode 'Test compilation'

        $testExecutable = Join-Path $testOutput 'memoryrecorddropdowntests.exe'
        & $testExecutable '--all'
        if ($LASTEXITCODE -ne 0) {
            throw "Tests failed with exit code $LASTEXITCODE."
        }
    } finally {
        if (Test-Path -LiteralPath $testOutput -PathType Container) {
            Remove-Item -LiteralPath $testOutput -Recurse -Force
        }
    }
}

switch ($Action) {
    'CheckTools' {
        [void](Assert-Tools)
    }
    'Build' {
        $resolvedLazBuild = Assert-Tools
        Invoke-LazBuild $resolvedLazBuild
    }
    'Run' {
        $resolvedLazBuild = Assert-Tools
        $executable = Get-ExpectedExecutable
        # Run always builds first. Never launch an older executable after a
        # failed compilation merely because a stale output file still exists.
        Invoke-LazBuild $resolvedLazBuild

        Write-Host "Running $executable"
        $process = Start-Process -FilePath $executable -WorkingDirectory $binDir -ArgumentList @('NOAUTORUN', 'NOFIRSTTIME') -PassThru
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "The application exited with code $($process.ExitCode)."
        }
    }
    'Test' {
        [void](Assert-Tools)
        Invoke-Tests
    }
    'Clean' {
        $outputs = @(
            (Join-Path $binDir 'cheatengine-x86_64.exe'),
            (Join-Path $binDir 'cheatengine-x86_64.dbg'),
            (Join-Path $binDir 'cheatengine-x86_64-debug.exe'),
            (Join-Path $binDir 'cheatengine-x86_64-debug.dbg'),
            (Join-Path $binDir 'cheatengine-i386.exe'),
            (Join-Path $binDir 'cheatengine-i386.dbg'),
            (Join-Path $binDir 'cheatengine-x86_64-SSE4-AVX2.exe'),
            (Join-Path $binDir 'cheatengine-x86_64-SSE4-AVX2.dbg')
        )
        foreach ($output in $outputs) {
            if (Test-Path -LiteralPath $output -PathType Leaf) {
                Remove-Item -LiteralPath $output -Force
                Write-Host "Removed: $output"
            }
        }

        $generatedDirectories = @(
            (Join-Path $repoRoot 'Cheat Engine\lib\x86_64-win64'),
            (Join-Path $repoRoot 'Cheat Engine\lib\x86_64-win64-debug'),
            (Join-Path $repoRoot 'Cheat Engine\lib\i386-win32'),
            (Join-Path $repoRoot 'Cheat Engine\lib\x86_64-SSE4-AVX-win64')
        )
        foreach ($generatedDirectory in $generatedDirectories) {
            if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
                Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
                Write-Host "Removed: $generatedDirectory"
            }
        }
    }
}
