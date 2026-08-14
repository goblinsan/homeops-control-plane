import json
import os
import re
import sys
import urllib.request

BASE = sys.argv[1].rstrip("/")
CONTRACT = sys.argv[2]

SYSTEM = " ".join([
    "You are the lead engineer implementing one scoped task in an existing repository.",
    "Respond with full-file rewrite blocks using ```file path=<relative-path> fences.",
    "Never output unified diffs, git diff headers, or @@ hunks.",
    "Include the complete contents of each changed file.",
    "Only touch files needed for the task. Never edit lockfiles, .env files, or CI credentials.",
])


def remove_target_section(description):
    lines, kept, in_target = description.split("\n"), [], False
    for line in lines:
        heading = line.strip().upper()
        if heading == "TARGET":
            in_target = True
            continue
        if in_target and heading in ("CONTEXT", "CHANGE", "ACCEPTANCE"):
            in_target = False
        if not in_target:
            kept.append(line)
    return "\n".join(kept).strip()


INVENTORY = open(sys.argv[3]).read().strip()
text = open(CONTRACT).read()
prompt = remove_target_section(text)

payload = {
    "model": "Qwen3.6-14B-A3B-FableVibes-Q6_K.gguf",
    "messages": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": f"Repository files:\n{INVENTORY}\n\n{prompt}"},
    ],
    "max_tokens": 6000,
    "frequency_penalty": 0.5,
}

req = urllib.request.Request(
    f"{BASE}/v1/chat/completions",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(req, timeout=600) as r:
    body = json.loads(r.read())

out = body["choices"][0]["message"]["content"]
open(os.environ.get("PROBE_OUT", "/tmp/probe-out.md"), "w").write(out)

paths = re.findall(r"^`{3,}(?:file|rewrite)\s+path=(\S+)", out, re.M)
print("file blocks emitted:", paths or "(none)")
print("output chars:", len(out))
print("usage:", body.get("usage"))
