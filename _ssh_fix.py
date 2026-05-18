import subprocess
import sys

# First check if paramiko is installed
try:
    import paramiko
    print("paramiko available")
except ImportError:
    print("paramiko not installed")
    # Try pip install
    subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"])
    import paramiko
    print("paramiko installed")

# Connect and fix
host = "31.129.97.211"
user = "root"
password = "WCw8eJo&TIxu"

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=10)

cmd = """sed -i "s/throw.*already linked.*;/\\/\\/ Auto-rebind/" /var/www/laravel_backend_vps/app/Domain/Profiles/PhoneProfileRepository.php && echo FIXED && grep -n 'Auto-rebind' /var/www/laravel_backend_vps/app/Domain/Profiles/PhoneProfileRepository.php"""
stdin, stdout, stderr = client.exec_command(cmd)
out = stdout.read().decode()
err = stderr.read().decode()
print("OUT:", out)
print("ERR:", err)
client.close()
