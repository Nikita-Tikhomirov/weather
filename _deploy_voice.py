import sys, subprocess
try: import paramiko
except: subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"]); import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect("31.129.97.211", username="root", password="WCw8eJo&TIxu", timeout=10)

cmds = [
    # Fix 1: allow voice type
    """sed -i "s/'image_group'\\]/'image_group', 'voice'\\]/" /var/www/adebechigef/app/Domain/Chat/ChatRepository.php""",
    # Fix 2: voice notification
    """sed -i "/if (\\$type === 'image') {/,/}/{s/return 'Отправлено изображение';/return 'Отправлено изображение';\\n        }\\n        if (\\$type === 'voice') {\\n            return '🎤 Голосовое сообщение';/}" /var/www/adebechigef/app/Http/Controllers/ChatController.php""",
]

for c in cmds:
    stdin, stdout, stderr = client.exec_command(c)
    print("CMD:", c[:60])
    print("OUT:", stdout.read().decode())
    print("ERR:", stderr.read().decode())

# Verify
stdin, stdout, stderr = client.exec_command("grep -n voice /var/www/adebechigef/app/Domain/Chat/ChatRepository.php")
print("VERIFY ChatRepository:", stdout.read().decode())
stdin, stdout, stderr = client.exec_command("grep -n voice /var/www/adebechigef/app/Http/Controllers/ChatController.php")
print("VERIFY ChatController:", stdout.read().decode())

client.close()
print("DONE")
