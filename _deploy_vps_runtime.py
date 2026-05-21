import paramiko, sys, os

host = "31.129.97.211"
user = "root"
password = "WCw8eJo&TIxu"
remote_base = "/var/www/adebechigef"
skip_migration = len(sys.argv) > 1 and sys.argv[1] == "--skip-migration"

files = [
    ("laravel_backend_vps/app/Domain/Chat/ChatRepository.php", f"{remote_base}/app/Domain/Chat/ChatRepository.php"),
    ("laravel_backend_vps/app/Http/Controllers/ChatController.php", f"{remote_base}/app/Http/Controllers/ChatController.php"),
    ("laravel_backend_vps/routes/api.php", f"{remote_base}/routes/api.php"),
]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=15)
sftp = client.open_sftp()

for local, remote in files:
    print(f"Uploading {local} ...")
    try:
        sftp.stat(remote + ".bak")
        sftp.remove(remote + ".bak")
    except:
        pass
    try:
        sftp.rename(remote, remote + ".bak")
    except:
        pass
    sftp.put(local, remote)
    print(f"  {local} -> {remote}")

sftp.close()

if not skip_migration:
    stdin, stdout, stderr = client.exec_command(f"cd {remote_base} && php artisan migrate --force 2>&1")
    print("Migration:", stdout.read().decode().strip())
    err = stderr.read().decode().strip()
    if err:
        print("Migration stderr:", err)

stdin2, stdout2, stderr2 = client.exec_command(f"cd {remote_base} && php artisan cache:clear 2>&1")
print("Cache clear:", stdout2.read().decode().strip())

client.close()
print("Deploy done.")
