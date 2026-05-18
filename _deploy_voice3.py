import sys, subprocess
try: import paramiko
except: subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"]); import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect("31.129.97.211", username="root", password="WCw8eJo&TIxu", timeout=10)

# Fix 1: add voice to message types
# The line is: return in_array($type, ['text', 'sticker', 'image', 'image_group'], true) ? $type : 'text';
sftp = client.open_sftp()
with sftp.open('/var/www/adebechigef/app/Domain/Chat/ChatRepository.php', 'r') as f:
    c1 = f.read().decode()
c1 = c1.replace(
    "['text', 'sticker', 'image', 'image_group']",
    "['text', 'sticker', 'image', 'image_group', 'voice']"
)
with sftp.open('/var/www/adebechigef/app/Domain/Chat/ChatRepository.php', 'w') as f:
    f.write(c1)

# Fix 2: add voice notification
with sftp.open('/var/www/adebechigef/app/Http/Controllers/ChatController.php', 'r') as f:
    c2 = f.read().decode()
old = "        if ($type === 'image') {\n            return 'Отправлено изображение';\n        }"
new = "        if ($type === 'image') {\n            return 'Отправлено изображение';\n        }\n        if ($type === 'voice') {\n            return '🎤 Голосовое сообщение';\n        }"
c2 = c2.replace(old, new)
with sftp.open('/var/www/adebechigef/app/Http/Controllers/ChatController.php', 'w') as f:
    f.write(c2)

sftp.close()

# Verify
stdin, stdout, stderr = client.exec_command("grep -n voice /var/www/adebechigef/app/Domain/Chat/ChatRepository.php")
print("OK1:", stdout.read().decode())
stdin, stdout, stderr = client.exec_command("grep -n voice /var/www/adebechigef/app/Http/Controllers/ChatController.php")
print("OK2:", stdout.read().decode())

client.close()
print("DONE")
