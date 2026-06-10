param(
    [string]$Flutter = $(if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { "C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat" }),
    [switch]$SkipAnalyze,
    [switch]$SkipTests,
    [switch]$SuiteBySuite,
    [string]$TestPattern = "*_test.dart",
    [int]$Retries = 1
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[mobile-checks] $Message"
}

function Invoke-CapturedNative {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Command
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $executable = $Command[0]
        $arguments = @()
        if ($Command.Length -gt 1) {
            $arguments = @($Command[1..($Command.Length - 1)])
        }
        $output = & $executable @arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    [PSCustomObject]@{
        Output = $output
        ExitCode = $exitCode
    }
}

function Test-InfrastructureFailure {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    return (
        $Output -match "Connection closed before test suite loaded" -or
        $Output -match "0xc0000005" -or
        $Output -match "git subprocess failed with exit code -1073741819" -or
        $Output -match "Failed to find the latest git commit date" -or
        $Output -match "ProcessException: .*Access is denied" -or
        $Output -match "Puro crashed" -or
        $ExitCode -eq -1073741819
    )
}

function Invoke-FlutterCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $Flutter)) {
        throw "Flutter launcher not found: $Flutter. Set FLUTTER_BIN to a valid flutter.bat path."
    }

    $attempt = 0
    while ($true) {
        $attempt++
        $command = @($Flutter) + $Arguments
        $result = Invoke-CapturedNative -Command $command
        $result.Output | ForEach-Object { Write-Host $_ }
        if ($result.ExitCode -eq 0) {
            return
        }
        $combinedOutput = $result.Output -join "`n"
        $isInfrastructureFailure = Test-InfrastructureFailure -Output $combinedOutput -ExitCode $result.ExitCode
        if (-not $isInfrastructureFailure -or $attempt -gt $Retries) {
            throw "Flutter command failed with exit code $($result.ExitCode): $Flutter $($Arguments -join ' ')"
        }
        Write-Step "retrying flutter $($Arguments -join ' ') after infrastructure failure"
        Start-Sleep -Seconds 2
    }
}

function Invoke-TestFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $attempt = 0
    while ($true) {
        $attempt++
        Write-Step "test $Path (attempt $attempt)"
        $result = Invoke-CapturedNative -Command @($Flutter, "test", $Path, "--concurrency=1")
        $output = $result.Output
        $exitCode = $result.ExitCode
        $output | ForEach-Object { Write-Host $_ }
        if ($exitCode -eq 0) {
            return
        }
        $combinedOutput = $output -join "`n"
        $isInfrastructureFailure = Test-InfrastructureFailure -Output $combinedOutput -ExitCode $exitCode
        if (-not $isInfrastructureFailure) {
            throw "Test suite failed with a test assertion or compile error: $Path"
        }
        if ($attempt -gt $Retries) {
            throw "Test suite failed after $attempt attempt(s): $Path"
        }
        Write-Step "retrying $Path after infrastructure failure"
        Start-Sleep -Seconds 2
    }
}

Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not $SkipAnalyze) {
    Write-Step "analyze"
    Invoke-FlutterCommand -Arguments @("analyze")
}

if (-not $SkipTests) {
    if ($SuiteBySuite) {
        $testFiles = Get-ChildItem -Path "test" -Filter $TestPattern -File |
            Sort-Object FullName |
            ForEach-Object { $_.FullName }
        foreach ($testFile in $testFiles) {
            Invoke-TestFile -Path $testFile
        }
    } else {
        Write-Step "test --concurrency=1"
        Invoke-FlutterCommand -Arguments @("test", "--concurrency=1")
    }
}

Write-Step "done"
