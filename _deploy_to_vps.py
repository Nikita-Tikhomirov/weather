import subprocess, sys
try:
    import paramiko
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"])
    import paramiko

host = "31.129.97.211"
user = "root"
password = "WCw8eJo&TIxu"

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=10)

sftp = client.open_sftp()
local_path = r"laravel_backend_vps\app\Services\Push\FcmPushGateway.php"
remote_path = "/var/www/adebechigef/app/Services/Push/FcmPushGateway.php"

# backup
try:
    sftp.stat(remote_path + ".bak")
    sftp.remove(remote_path + ".bak")
except:
    pass
sftp.rename(remote_path, remote_path + ".bak")

sftp.put(local_path, remote_path)
print(f"Uploaded {local_path} -> {remote_path}")

stdin, stdout, stderr = client.exec_command(f"md5sum {remote_path}")
print("Remote:", stdout.read().decode().strip())
stdin2, stdout2, stderr2 = client.exec_command(f"md5sum {remote_path}.bak")
print("Backup:", stdout2.read().decode().strip())

sftp.close()
client.close()
print("Done.")
