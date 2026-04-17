$ErrorActionPreference = "Stop"

Set-Location "C:\Users\user\Desktop\weather"

# Stage all local changes.
git add -A

# Exit quickly when there is nothing staged.
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    exit 0
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$message = "chore(auto): sync $timestamp"

git commit -m $message
git push origin master
