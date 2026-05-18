import sys, subprocess
try: import paramiko
except: subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"]); import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect("31.129.97.211", username="root", password="WCw8eJo&TIxu", timeout=10)

# Fix 1: add 'voice' to message types
cmd1 = """php -r "
\\$file = '/var/www/adebechigef/app/Domain/Chat/ChatRepository.php';
\\$content = file_get_contents(\\$file);
\\$content = str_replace(
    \\\"['text', 'sticker', 'image', 'image_group']\\\",
    \\\"['text', 'sticker', 'image', 'image_group', 'voice']\\\",
    \\$content
);
file_put_contents(\\$file, \\$content);
echo 'OK1';
"
"""
stdin, stdout, stderr = client.exec_command(cmd1)
print("FIX1:", stdout.read().decode(), stderr.read().decode())

# Fix 2: add voice notification body
cmd2 = """php -r "
\\$file = '/var/www/adebechigef/app/Http/Controllers/ChatController.php';
\\$content = file_get_contents(\\$file);
\\$insert = \\\"        }\\\\n        if (\\\\\\$type === 'voice') {\\\\n            return '🎤 Голосовое сообщение';\\\";
\\$content = str_replace(
    \\\"return 'Отправлено изображение';\\\",
    \\\"return 'Отправлено изображение';\\\" . \\$insert,
    \\$content
);
file_put_contents(\\$file, \\$content);
echo 'OK2';
"
"""
stdin, stdout, stderr = client.exec_command(cmd2)
print("FIX2:", stdout.read().decode(), stderr.read().decode())

# Verify
stdin, stdout, stderr = client.exec_command("grep -n 'voice' /var/www/adebechigef/app/Domain/Chat/ChatRepository.php")
print("VERIFY1:", stdout.read().decode())

stdin, stdout, stderr = client.exec_command("grep -n 'voice' /var/www/adebechigef/app/Http/Controllers/ChatController.php")
print("VERIFY2:", stdout.read().decode())

client.close()
print("DONE")
