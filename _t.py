import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('31.129.97.211', 22, username='root', password='WCw8eJo&TIxu', timeout=30, look_for_keys=False, allow_agent=False)

# Check tunnel log for recent bridge activity
s, o, e = c.exec_command('tail -30 /var/log/tunnel_server.log')
print("=== Tunnel log (last 30) ===")
print(o.read().decode())

# Check if bridges are registered
s, o, e = c.exec_command('grep "Bridge registered" /var/log/tunnel_server.log | tail -5')
print("=== Last 5 bridge registrations ===")
print(o.read().decode())

c.close()
