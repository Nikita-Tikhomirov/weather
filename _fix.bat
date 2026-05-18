@echo off
C:\Windows\System32\OpenSSH\ssh.exe -o StrictHostKeyChecking=no root@31.129.97.211 "sed -i 's/throw.*already linked.*;/\/\/ Auto-rebind/' /var/www/laravel_backend_vps/app/Domain/Profiles/PhoneProfileRepository.php && echo FIXED"
