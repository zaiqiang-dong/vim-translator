#!/usr/bin/env python3
"""vim-translator 测试用 mock ACP agent。

按 ACP 协议（换行分隔的 JSON-RPC 2.0 over stdio）响应：
- initialize -> agentCapabilities
- session/new -> sessionId
- session/prompt -> 按原文形状返回单词/句子 JSON（与插件 prompt 约定一致）
  文本经 session/update 流式推送（模拟 traecli 行为：prompt 响应 content 为空）

用法：python3 tests/acp/mock_agent.py   （stdio，spawn 模式测试）
"""
import json
import sys


def has_cjk(s):
    return any("\u4e00" <= c <= "\u9fff" for c in s)


def translate(payload):
    # 与 vim-translator 的 prompt 约定：'待翻译文本：' 之后为原文
    text = payload.split("待翻译文本：", 1)[1].strip() if "待翻译文本：" in payload else payload
    if " " in text or "\n" in text or len(text) > 40:
        return {
            "source": text,
            "source_lang": "zh" if has_cjk(text) else "en",
            "translation": "[mock] " + text.upper(),
        }
    return {
        "word": text,
        "phonetic": "/mɒk/",
        "defs": [{"pos": "n.", "trans": "[mock] " + text + " 的释义"}],
        "examples": [{"en": "mock example of " + text, "zh": text + " 的模拟例句"}],
    }


def handle_message(line):
    """处理一行 JSON-RPC 请求，返回要写回的响应行列表（可为空）"""
    msg = json.loads(line)
    method = msg.get("method")
    mid = msg.get("id")
    out = []

    def emit(obj):
        out.append(json.dumps(obj, ensure_ascii=False))

    if method == "initialize":
        emit({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": 1, "agentCapabilities": {}, "authMethods": []}})
    elif method == "session/new":
        emit({"jsonrpc": "2.0", "id": mid, "result": {"sessionId": "mock-session"}})
    elif method == "session/prompt":
        blocks = msg.get("params", {}).get("prompt", [])
        full = "\n".join(b.get("text", "") for b in blocks)
        text = json.dumps(translate(full), ensure_ascii=False)
        sid = msg.get("params", {}).get("sessionId", "mock-session")
        # 模拟流式 agent（如 traecli）：update 嵌套在 params.update 下，分块推送
        for i in range(0, len(text), 20):
            emit({"jsonrpc": "2.0", "method": "session/update", "params": {
                "sessionId": sid,
                "updateId": "u1",
                "update": {
                    "sessionUpdate": "agent_message_chunk",
                    "content": {"type": "text", "text": text[i:i + 20]},
                },
            }})
        emit({"jsonrpc": "2.0", "id": mid, "result": {"stopReason": "end_turn", "content": []}})
    elif mid is not None:
        emit({"jsonrpc": "2.0", "id": mid, "result": {}})
    return out


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        for resp in handle_message(line):
            print(resp, flush=True)


if __name__ == "__main__":
    main()
