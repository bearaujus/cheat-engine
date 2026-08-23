[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CheckTools', 'Build', 'Run', 'Clean')]
    [string]$Action,

    [ValidateSet('x86', 'x64')]
    [string]$Architecture = 'x64',

    [string]$BuildMode = 'Release 64-Bit',

    [string]$LazarusDir,

    [string]$LazBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $repoRoot 'Cheat Engine\cheatengine.lpi'
$binDir = Join-Path $repoRoot 'Cheat Engine\bin'

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
    if ($Architecture -eq 'x86') {
        return Join-Path $binDir 'cheatengine-i386.exe'
    }

    return Join-Path $binDir 'cheatengine-x86_64.exe'
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
    $compilerNames = if ($Architecture -eq 'x86') {
        @('ppcross386.exe', 'ppc386.exe', 'fpc.exe')
    } else {
        @('ppcx64.exe', 'fpc.exe')
    }
    $compiler = Find-Tool $compilerNames
    if ($null -eq $compiler) {
        throw "Unable to find an FPC compiler for $Architecture under '$LazarusDir'."
    }

    $compilerBin = Split-Path -Parent $compiler
    $env:PATH = "$compilerBin;$LazarusDir;$env:PATH"

    Write-Host "Lazarus: $LazarusDir"
    Write-Host "lazbuild: $resolvedLazBuild"
    Write-Host "FPC: $compiler"
    return $resolvedLazBuild
}

function Invoke-LazBuild([string]$ResolvedLazBuild) {
    $projectBytes = [System.IO.File]::ReadAllBytes($projectFile)
    Write-Host "Building $Architecture with mode '$BuildMode'..."
    try {
        & $ResolvedLazBuild $projectFile "--build-mode=$BuildMode"
        if ($LASTEXITCODE -ne 0) {
            throw "lazbuild failed with exit code $LASTEXITCODE."
        }

        $executable = Get-ExpectedExecutable
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "Build completed but the expected executable was not created: $executable"
        }
    } finally {
        [System.IO.File]::WriteAllBytes($projectFile, $projectBytes)
    }

    Write-Host "Built: $executable"
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
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            Invoke-LazBuild $resolvedLazBuild
        }

        Write-Host "Running $executable"
        $process = Start-Process -FilePath $executable -WorkingDirectory $binDir -PassThru
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "The application exited with code $($process.ExitCode)."
        }
    }
    'Clean' {
        $outputs = @(
            (Join-Path $binDir 'cheatengine-i386.exe'),
            (Join-Path $binDir 'cheatengine-x86_64.exe'),
            (Join-Path $binDir 'cheatengine-x86_64-SSE4-AVX2.exe')
        )
        foreach ($output in $outputs) {
            if (Test-Path -LiteralPath $output -PathType Leaf) {
                Remove-Item -LiteralPath $output -Force
                Write-Host "Removed: $output"
            }
        }

        $generatedDirectories = @(
            (Join-Path $repoRoot 'Cheat Engine\lib\i386-win32'),
            (Join-Path $repoRoot 'Cheat Engine\lib\x86_64-win64'),
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
