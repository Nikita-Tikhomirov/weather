import subprocess
subprocess.run(['schtasks', '/run', '/tn', 'ShutdownTask'])
