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

# Find the file
cmds = [
    "find / -name 'PhoneProfileRepository.php' -type f 2>/dev/null | head -5",
    "ls /var/www/ 2>/dev/null",
    "ls /home/ 2>/dev/null",
]
for c in cmds:
    stdin, stdout, stderr = client.exec_command(c)
    print("CMD:", c)
    print(stdout.read().decode())
    print("---")

client.close()
