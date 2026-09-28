import re, subprocess, sys
for it in range(30):
    out = subprocess.run(["sh", "tools/check.sh"], capture_output=True, text=True).stdout
    hits = re.findall(r'Cannot infer the type of "(\w+)".*?\n\s+at: GDScript::reload \(res://([^:]+):(\d+)\)', out)
    if not hits:
        print(out); break
    for var, path, line in set(hits):
        lines = open(path).read().split("\n")
        i = int(line) - 1
        lines[i] = lines[i].replace("var %s :=" % var, "var %s =" % var, 1)
        open(path, "w").write("\n".join(lines))
        print("fixed", path, line, var)
