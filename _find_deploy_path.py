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

# Find where laravel is deployed
stdin, stdout, stderr = client.exec_command("find / -name 'FcmPushGateway.php' -type f 2>/dev/null")
result = stdout.read().decode().strip()
print("Found at:", result)

client.close()
