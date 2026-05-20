from commands import match_command, available_phrases
cmd = match_command("зоны")
print("MATCH:", cmd)
print("PHRASES:", [p for p in available_phrases() if "зон" in p])
