with open(r'C:\Users\user\Desktop\weather\mobile_app\lib\features\home\home_page.dart', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if '_pickAndSetGroupAvatar' in line or 'chatUploadMedia' in line or 'setGroupAvatar' in line:
        start = max(0, i-2)
        end = min(len(lines), i+12)
        for j in range(start, end):
            print(f"{j+1}:{lines[j]}", end='')
        print("---")
