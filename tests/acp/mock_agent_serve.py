#!/usr/bin/env python3
"""mock ACP agent 的 TCP 版：作为独立服务在指定端口监听（connect 模式测试用）。

每个 TCP 连接跑一个完整的 mock agent 会话（复用 mock_agent.py 的逻辑）。
用法：python3 tests/acp/mock_agent_serve.py [port]
"""
import asyncio
import json
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mock_agent import handle_message  # noqa: E402

DEFAULT_PORT = 8378


async def handle_conn(reader, writer):
    buf = b""
    try:
        while True:
            data = await reader.read(4096)
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if line.strip():
                    for resp in handle_message(line.decode("utf-8")):
                        writer.write((resp + "\n").encode("utf-8"))
                        await writer.drain()
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        writer.close()


async def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    server = await asyncio.start_server(handle_conn, "127.0.0.1", port)
    print(f"mock ACP serving on 127.0.0.1:{port}", file=sys.stderr)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
