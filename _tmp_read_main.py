import sys
with open('mobile_app/lib/main.dart', encoding='utf-8') as f:
    lines = f.readlines()

start = int(sys.argv[1]) - 1 if len(sys.argv) > 1 else 2429
end = int(sys.argv[2]) if len(sys.argv) > 2 else start + 200

for i, line in enumerate(lines[start:end], start=start+1):
    print(f'{i}: {line}', end='')
