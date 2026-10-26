import sys
import pexpect


def run(command, args):
    child = pexpect.spawn(command, args, encoding="utf-8", timeout=30)
    shown = ""
    try:
        while True:
            i = child.expect([r"Authenticating as: (\S+)", r"[Pp]assword[^:]*:", pexpect.EOF])
            if i == 0:
                shown = child.match.group(1)
            elif i == 1:
                child.sendline("pw")
            else:
                break
    finally:
        child.close()
    return child.exitstatus, shown, child.before


what = sys.argv[1]
if what == "su":
    status, _, out = run("su", [sys.argv[2], "-c", "id -un"])
else:
    status, shown, out = run("pkexec", ["id", "-un"])
    print("authenticating-as:", shown)
print("status:", status)
print("output:", out.strip().splitlines()[-1:] if out else "")
