"""Print a readable trace of an agent run: python3 -I agents/show_log.py agents/logs/<id>.jsonl"""
import json, sys

for line in open(sys.argv[1]):
    e = json.loads(line)
    t = e.get("type")
    if t == "tool_execution_start" and not e.get("parentToolCallId"):
        print("TOOL", e["toolName"], json.dumps(e["args"])[:400])
    elif t == "tool_execution_start":
        print("  call", e["toolName"], json.dumps(e["args"])[:160])
    elif t == "tool_execution_end" and not e.get("parentToolCallId"):
        text = "".join(c.get("text", "") for c in e["result"]["content"] if c.get("type") == "text")
        print("  ->", "ERROR" if e["isError"] else "ok", text[:500].replace("\n", " "))
    elif t == "message_end" and e["message"]["role"] == "assistant":
        for c in e["message"]["content"]:
            if c.get("type") == "text" and c["text"].strip():
                print("ASSISTANT:", c["text"][:3000])
        if e["message"].get("errorMessage"):
            print("  error:", e["message"]["errorMessage"][:300])
    elif t == "extension_error":
        print("EXTENSION ERROR", e)
