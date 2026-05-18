$password = 'WCw8eJo&TIxu'
$command = 'sed -i "s/throw.*already linked.*;/\/\/ Auto-rebind/" /var/www/laravel_backend_vps/app/Domain/Profiles/PhoneProfileRepository.php && echo FIXED && grep -n Auto-rebind /var/www/laravel_backend_vps/app/Domain/Profiles/PhoneProfileRepository.php'

# Use plink-style approach: create temp ssh key
$keyFile = "$env:TEMP\_tmp_vps_key"
ssh-keygen -t rsa -f $keyFile -N '""' -q 2>$null
ssh-copy-id -i "$keyFile.pub" -o StrictHostKeyChecking=no root@31.129.97.211 2>$null
ssh -i $keyFile -o StrictHostKeyChecking=no root@31.129.97.211 $command
Remove-Item $keyFile, "$keyFile.pub" -Force -ErrorAction SilentlyContinue
