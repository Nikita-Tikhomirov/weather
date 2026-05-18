import subprocess
import sys

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

path = "/var/www/adebechigef/app/Domain/Profiles/PhoneProfileRepository.php"

# Fix: replace throw with auto-rebind comment
cmd = f"sed -i \"s/throw.*already linked.*;/\\/\\/ Auto-rebind/\" {path} && echo FIXED && grep -n 'Auto-rebind\|already linked' {path}"
stdin, stdout, stderr = client.exec_command(cmd)
print("OUT:", stdout.read().decode())
print("ERR:", stderr.read().decode())

client.close()
