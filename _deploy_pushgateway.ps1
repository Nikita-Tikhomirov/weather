$passwd = "WCw8eJo&TIxu"
$source = "laravel_backend_vps/app/Services/Push/FcmPushGateway.php"
$target = "/var/www/laravel_backend_vps/app/Services/Push/FcmPushGateway.php"

Write-Host "Uploading $source to VPS..."

# Use scp with password via sshpass or plink
$env:PLINK_PROTOCOL = "ssh"
echo y | plink -pw $passwd root@31.129.97.211 "exit"
if ($LASTEXITCODE -ne 0) {
    Write-Host "SSH connection test failed"
    exit 1
}

# Upload via scp
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL $source root@31.129.97.211:$target
if ($LASTEXITCODE -ne 0) {
    Write-Host "SCP upload failed"
    exit 1
}

Write-Host "Upload OK. Verifying..."
echo y | plink -pw $passwd root@31.129.97.211 "md5sum $target"
Write-Host "Done."
