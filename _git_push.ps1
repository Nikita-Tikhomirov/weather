# Git silent push — no prompts, no credential manager
$ErrorActionPreference = 'Stop'

# Kill ALL credential helpers
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_ASKPASS = 'echo'
$env:GIT_SSH_COMMAND = 'ssh -o BatchMode=yes'

$repo = 'C:\Users\user\Desktop\weather'
Set-Location $repo

# Push with every credential helper forcibly disabled
git -c credential.helper= `
    -c credential.helper= `
    -c credential.useHttpPath=false `
    push 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Push failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Write-Output "Push OK"
