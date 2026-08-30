[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CheckTools', 'Build', 'Run', 'Smoke', 'Test', 'Clean')]
    [string]$Action,

    [string]$LazarusDir,

    [string]$LazBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $repoRoot 'Cheat Engine\cheatengine.lpi'
$binDir = Join-Path $repoRoot 'Cheat Engine\bin'
$releaseBuildMode = 'Release 64-Bit'
$releaseBuildStamp = Join-Path $binDir 'cheatengine-x86_64.buildstamp'
$releaseBuildStampVersion = 1
$script:resolvedCompiler = $null

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

function Get-ReleaseBuildInputFiles {
    $projectDir = Split-Path -Parent $projectFile
    $inputs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $sourceExtensions = @(
        '.pas', '.pp', '.inc', '.lfm', '.lrs', '.dfm', '.res', '.rc',
        '.ico', '.manifest'
    )

    [void]$inputs.Add([System.IO.Path]::GetFullPath($projectFile))
    [void]$inputs.Add([System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot 'build.ps1')))

    [xml]$project = Get-Content -LiteralPath $projectFile -Raw
    foreach ($unitNode in $project.SelectNodes('//ProjectOptions/Units/*/Filename')) {
        $filename = $unitNode.GetAttribute('Value')
        if ([string]::IsNullOrWhiteSpace($filename)) {
            continue
        }

        $unitPath = [System.IO.Path]::GetFullPath((Join-Path $projectDir $filename))
        if (Test-Path -LiteralPath $unitPath -PathType Leaf) {
            [void]$inputs.Add($unitPath)
        }
    }

    # Units in the project root can be found through Pascal's default search
    # path without appearing in the Lazarus unit list.
    foreach ($file in Get-ChildItem -LiteralPath $projectDir -File) {
        if ($sourceExtensions -contains $file.Extension.ToLowerInvariant()) {
            [void]$inputs.Add($file.FullName)
        }
    }

    # Include local unit-search directories while excluding Lazarus macros and
    # other absolute toolchain paths. These contain units discovered through
    # uses clauses rather than explicit project entries.
    foreach ($searchNode in $project.SelectNodes('//OtherUnitFiles')) {
        foreach ($searchPath in $searchNode.GetAttribute('Value').Split(';')) {
            $searchPath = $searchPath.Trim()
            if ([string]::IsNullOrWhiteSpace($searchPath) -or
                $searchPath.Contains('$(') -or
                [System.IO.Path]::IsPathRooted($searchPath)) {
                continue
            }

            $resolvedSearchPath = [System.IO.Path]::GetFullPath(
                (Join-Path $projectDir $searchPath))
            if (-not (Test-Path -LiteralPath $resolvedSearchPath -PathType Container)) {
                continue
            }

            foreach ($file in Get-ChildItem -LiteralPath $resolvedSearchPath -Recurse -File) {
                if ($sourceExtensions -contains $file.Extension.ToLowerInvariant()) {
                    [void]$inputs.Add($file.FullName)
                }
            }
        }
    }

    $sortedInputs = [string[]]$inputs
    [System.Array]::Sort(
        $sortedInputs,
        [System.StringComparer]::OrdinalIgnoreCase)
    return $sortedInputs
}

function Add-HashBytes(
    [System.Security.Cryptography.HashAlgorithm]$Hash,
    [byte[]]$Bytes
) {
    if ($Bytes.Length -ne 0) {
        [void]$Hash.TransformBlock($Bytes, 0, $Bytes.Length, $null, 0)
    }
}

function Get-ReleaseBuildFingerprint([string]$ResolvedLazBuild) {
    $compiler = $script:resolvedCompiler
    if ([string]::IsNullOrWhiteSpace($compiler) -or
        -not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        $compiler = Find-Tool @('ppcx64.exe', 'fpc.exe')
    }
    if ($null -eq $compiler) {
        throw 'Unable to fingerprint the x64 FPC compiler.'
    }
    $script:resolvedCompiler = $compiler

    $hash = [System.Security.Cryptography.SHA256]::Create()
    try {
        $identity = @(
            "stamp-version=$releaseBuildStampVersion",
            "build-mode=$releaseBuildMode"
        )
        foreach ($tool in @($ResolvedLazBuild, $compiler)) {
            $toolInfo = Get-Item -LiteralPath $tool
            $identity += 'tool={0}|{1}|{2}' -f `
                $toolInfo.FullName.ToLowerInvariant(),
                $toolInfo.Length,
                $toolInfo.LastWriteTimeUtc.Ticks
        }
        Add-HashBytes $hash ([System.Text.Encoding]::UTF8.GetBytes(
            (($identity -join "`n") + "`n")))

        $buffer = New-Object byte[] (1024 * 1024)
        foreach ($inputFile in Get-ReleaseBuildInputFiles) {
            $fileInfo = Get-Item -LiteralPath $inputFile
            $header = '{0}|{1}' -f $fileInfo.FullName.ToLowerInvariant(),
                $fileInfo.Length
            Add-HashBytes $hash ([System.Text.Encoding]::UTF8.GetBytes(
                ($header + "`n")))

            $stream = [System.IO.File]::Open(
                $fileInfo.FullName,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            try {
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    [void]$hash.TransformBlock($buffer, 0, $read, $null, 0)
                }
            } finally {
                $stream.Dispose()
            }
        }

        [void]$hash.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return ([System.BitConverter]::ToString($hash.Hash)).Replace('-', '')
    } finally {
        $hash.Dispose()
    }
}

function Remove-ReleaseBuildStamp {
    if (Test-Path -LiteralPath $releaseBuildStamp -PathType Leaf) {
        Remove-Item -LiteralPath $releaseBuildStamp -Force
    }
}

function Write-ReleaseBuildStamp(
    [string]$Fingerprint,
    [string]$Executable
) {
    $executableInfo = Get-Item -LiteralPath $Executable
    $stamp = [ordered]@{
        Version = $releaseBuildStampVersion
        Fingerprint = $Fingerprint
        ExecutableLength = $executableInfo.Length
        ExecutableLastWriteTimeUtcTicks = $executableInfo.LastWriteTimeUtc.Ticks
    }
    $json = $stamp | ConvertTo-Json
    [System.IO.File]::WriteAllText(
        $releaseBuildStamp,
        $json,
        [System.Text.UTF8Encoding]::new($false))
}

function Test-ReleaseBuildUpToDate(
    [string]$Executable,
    [string]$ResolvedLazBuild
) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        Write-Host 'Release executable is missing; rebuilding.'
        return $false
    }

    $currentFingerprint = Get-ReleaseBuildFingerprint $ResolvedLazBuild
    if (Test-Path -LiteralPath $releaseBuildStamp -PathType Leaf) {
        try {
            $stamp = Get-Content -LiteralPath $releaseBuildStamp -Raw |
                ConvertFrom-Json
            $executableInfo = Get-Item -LiteralPath $Executable
            if (($stamp.Version -eq $releaseBuildStampVersion) -and
                ($stamp.Fingerprint -eq $currentFingerprint) -and
                ($stamp.ExecutableLength -eq $executableInfo.Length) -and
                ($stamp.ExecutableLastWriteTimeUtcTicks -eq
                    $executableInfo.LastWriteTimeUtc.Ticks)) {
                Write-Host 'Release executable is up to date; skipping build.'
                return $true
            }
        } catch {
            Write-Host "Ignoring invalid release build stamp: $($_.Exception.Message)"
        }

        Write-Host 'Release build stamp does not match current inputs; rebuilding.'
        return $false
    }

    # Adopt a release built directly by Lazarus when it is newer than every
    # discovered source and tool input. Subsequent runs use exact fingerprints.
    $executableInfo = Get-Item -LiteralPath $Executable
    $latestInputTime = [DateTime]::MinValue
    foreach ($inputFile in Get-ReleaseBuildInputFiles) {
        $inputTime = (Get-Item -LiteralPath $inputFile).LastWriteTimeUtc
        if ($inputTime -gt $latestInputTime) {
            $latestInputTime = $inputTime
        }
    }
    foreach ($tool in @($ResolvedLazBuild, $script:resolvedCompiler)) {
        $toolTime = (Get-Item -LiteralPath $tool).LastWriteTimeUtc
        if ($toolTime -gt $latestInputTime) {
            $latestInputTime = $toolTime
        }
    }

    if ($executableInfo.LastWriteTimeUtc -ge $latestInputTime) {
        Write-ReleaseBuildStamp $currentFingerprint $Executable
        Write-Host 'Adopted up-to-date release executable; skipping build.'
        return $true
    }

    Write-Host 'Release executable predates its build inputs; rebuilding.'
    return $false
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
    $script:resolvedCompiler = $compiler

    $compilerBin = Split-Path -Parent $compiler
    $env:PATH = "$compilerBin;$LazarusDir;$env:PATH"

    Write-Host "Lazarus: $LazarusDir"
    Write-Host "lazbuild: $resolvedLazBuild"
    Write-Host "FPC: $compiler"
    return $resolvedLazBuild
}

function Invoke-LazBuild([string]$ResolvedLazBuild) {
    Assert-ExecutableNotRunning
    Remove-ReleaseBuildStamp
    $fingerprintBeforeBuild = Get-ReleaseBuildFingerprint $ResolvedLazBuild
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

    $fingerprintAfterBuild = Get-ReleaseBuildFingerprint $ResolvedLazBuild
    if ($fingerprintAfterBuild -ne $fingerprintBeforeBuild) {
        throw 'Build inputs changed during compilation. Run the build again.'
    }
    Write-ReleaseBuildStamp $fingerprintAfterBuild $executable
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

function Get-ProcessTopLevelWindows([int]$ProcessId) {
    if ($null -eq ('CheatEngineBuildWindowInspector' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class CheatEngineBuildWindowInfo
{
    public IntPtr Handle;
    public string ClassName;
    public string Title;
    public bool Visible;
}

public static class CheatEngineBuildWindowInspector
{
    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder className, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder title, int maxCount);

    public static CheatEngineBuildWindowInfo[] GetWindows(int targetProcessId)
    {
        List<CheatEngineBuildWindowInfo> windows = new List<CheatEngineBuildWindowInfo>();
        EnumWindows(delegate(IntPtr window, IntPtr parameter)
        {
            uint processId;
            GetWindowThreadProcessId(window, out processId);
            if (processId != (uint)targetProcessId)
                return true;

            StringBuilder className = new StringBuilder(256);
            StringBuilder title = new StringBuilder(512);
            GetClassName(window, className, className.Capacity);
            GetWindowText(window, title, title.Capacity);
            windows.Add(new CheatEngineBuildWindowInfo {
                Handle = window,
                ClassName = className.ToString(),
                Title = title.ToString(),
                Visible = IsWindowVisible(window)
            });
            return true;
        }, IntPtr.Zero);
        return windows.ToArray();
    }
}
'@
    }

    return [CheatEngineBuildWindowInspector]::GetWindows($ProcessId)
}

function Stop-SmokeProcess([System.Diagnostics.Process]$Process) {
    if ($Process.HasExited) {
        return
    }

    if ($Process.CloseMainWindow() -and $Process.WaitForExit(5000)) {
        return
    }

    $Process.Kill()
    $Process.WaitForExit()
}

function Invoke-StartupSmokeTest([string]$Executable) {
    Write-Host "Starting startup smoke test: $Executable"
    $process = Start-Process -FilePath $Executable -WorkingDirectory $binDir `
        -ArgumentList @('NOAUTORUN', 'NOFIRSTTIME') -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)

    try {
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($process.HasExited) {
                throw "Startup smoke test process exited with code $($process.ExitCode)."
            }

            $windows = @(Get-ProcessTopLevelWindows $process.Id | Where-Object Visible)
            $startupDialog = $windows | Where-Object ClassName -eq '#32770' |
                Select-Object -First 1
            if ($null -ne $startupDialog) {
                throw "Startup smoke test found an unexpected dialog: '$($startupDialog.Title)'."
            }

            $mainWindow = $windows | Where-Object {
                ($_.ClassName -ne '#32770') -and ($_.Title -like 'Cheat Engine*')
            } | Select-Object -First 1
            if ($null -ne $mainWindow) {
                Write-Host "Startup smoke test passed: '$($mainWindow.Title)'."
                return
            }

            Start-Sleep -Milliseconds 250
        }

        throw 'Startup smoke test timed out waiting for the Cheat Engine main window.'
    } finally {
        Stop-SmokeProcess $process
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
        if (-not (Test-ReleaseBuildUpToDate $executable $resolvedLazBuild)) {
            # A failed compilation cannot leave a valid stamp, so Run never
            # launches an older executable after detecting changed inputs.
            Invoke-LazBuild $resolvedLazBuild
        }

        Write-Host "Running $executable"
        $process = Start-Process -FilePath $executable -WorkingDirectory $binDir -ArgumentList @('NOAUTORUN', 'NOFIRSTTIME') -PassThru
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "The application exited with code $($process.ExitCode)."
        }
    }
    'Smoke' {
        $resolvedLazBuild = Assert-Tools
        Invoke-LazBuild $resolvedLazBuild
        Invoke-StartupSmokeTest (Get-ExpectedExecutable)
    }
    'Test' {
        [void](Assert-Tools)
        Invoke-Tests
    }
    'Clean' {
        $outputs = @(
            (Join-Path $binDir 'cheatengine-x86_64.exe'),
            (Join-Path $binDir 'cheatengine-x86_64.dbg'),
            $releaseBuildStamp,
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
