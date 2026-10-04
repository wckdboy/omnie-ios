"""Scripted OpenAI-compatible model for exercising Hermes end to end."""
import json, time, uuid
from aiohttp import web

def last_user(msgs):
    for m in reversed(msgs):
        if m.get("role") == "user":
            c = m.get("content")
            if isinstance(c, list):
                return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
            return c or ""
    return ""

def plan(body):
    msgs = body.get("messages", [])
    if msgs and msgs[-1].get("role") == "tool":
        out = str(msgs[-1].get("content", ""))[:120].replace("\n", " ")
        return {"text": f"Tool finished. Result: {out}"}
    text = last_user(msgs).lower()
    if "danger" in text:
        return {"tool": ("terminal", {"command": "rm -rf /tmp/omnie-approval-probe"})}
    if "ask" in text:
        return {"tool": ("clarify", {"questions": [{"question": "Which color?", "choices": ["red", "blue"]}]})}
    if "tool" in text:
        return {"tool": ("terminal", {"command": "echo hello-from-tool"})}
    if "slow" in text:
        return {"text": "Slow reply " + "word " * 40, "delay": 0.15}
    return {"text": "Hello from the fake model. You said: " + text[:80], "reasoning": "Thinking about the reply."}

def chunk(cid, delta, finish=None, usage=None):
    d = {"id": cid, "object": "chat.completion.chunk", "created": int(time.time()), "model": "fake-1",
         "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
    if usage: d["usage"] = usage
    return ("data: " + json.dumps(d) + "\n\n").encode()

async def completions(request):
    body = await request.json()
    p = plan(body)
    cid = "chatcmpl-" + uuid.uuid4().hex[:8]
    usage = {"prompt_tokens": 12, "completion_tokens": 7, "total_tokens": 19}
    if not body.get("stream"):
        msg = {"role": "assistant", "content": p.get("text")}
        if "tool" in p:
            name, args = p["tool"]
            msg = {"role": "assistant", "content": None, "tool_calls": [{"id": "call_" + uuid.uuid4().hex[:6], "type": "function",
                   "function": {"name": name, "arguments": json.dumps(args)}}]}
        return web.json_response({"id": cid, "object": "chat.completion", "created": int(time.time()), "model": "fake-1",
                                  "choices": [{"index": 0, "message": msg, "finish_reason": "tool_calls" if "tool" in p else "stop"}], "usage": usage})
    resp = web.StreamResponse(headers={"Content-Type": "text/event-stream"})
    await resp.prepare(request)
    await resp.write(chunk(cid, {"role": "assistant"}))
    if "tool" in p:
        name, args = p["tool"]
        await resp.write(chunk(cid, {"tool_calls": [{"index": 0, "id": "call_" + uuid.uuid4().hex[:6], "type": "function",
                                                       "function": {"name": name, "arguments": json.dumps(args)}}]}))
        await resp.write(chunk(cid, {}, "tool_calls", usage))
    else:
        if p.get("reasoning"):
            await resp.write(chunk(cid, {"reasoning_content": p["reasoning"]}))
        import asyncio
        for word in p["text"].split(" "):
            await resp.write(chunk(cid, {"content": word + " "}))
            if p.get("delay"): await asyncio.sleep(p["delay"])
        await resp.write(chunk(cid, {}, "stop", usage))
    await resp.write(b"data: [DONE]\n\n")
    return resp

async def models(request):
    return web.json_response({"object": "list", "data": [{"id": "fake-1", "object": "model", "owned_by": "test"}]})

app = web.Application()
app.router.add_post("/v1/chat/completions", completions)
app.router.add_get("/v1/models", models)
web.run_app(app, host="127.0.0.1", port=18080, print=None)
