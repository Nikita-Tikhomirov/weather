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

function Invoke-FlutterCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $Flutter)) {
        throw "Flutter launcher not found: $Flutter. Set FLUTTER_BIN to a valid flutter.bat path."
    }

    & $Flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed with exit code ${LASTEXITCODE}: $Flutter $($Arguments -join ' ')"
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
        $output = & $Flutter "test" $Path "--concurrency=1" 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if ($exitCode -eq 0) {
            return
        }
        $combinedOutput = $output -join "`n"
        $isInfrastructureFailure =
            $combinedOutput -match "Connection closed before test suite loaded" -or
            $combinedOutput -match "0xc0000005" -or
            $exitCode -eq -1073741819
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
