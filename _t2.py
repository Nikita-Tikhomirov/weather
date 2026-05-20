import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('31.129.97.211', 22, username='root', password='WCw8eJo&TIxu', timeout=30, look_for_keys=False, allow_agent=False)

# Check all recent bridge activity
s, o, e = c.exec_command('grep -E "cifra|Bridge registered|Bridge unregistered|Mobile waiting|Launcher: project" /var/log/tunnel_server.log | tail -30')
print("=== cifra + bridge activity ===")
print(o.read().decode())

# Check current connections
s, o, e = c.exec_command('ss -tn | grep 9877')
print("=== Current connections ===")
print(o.read().decode())

c.close()
