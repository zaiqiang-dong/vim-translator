#!/usr/bin/env bash
# vim-translator headless 冒烟测试
# 用法: VIM_TRANSLATOR_API_KEY=sk-xxx tests/run_headless.sh
set -uo pipefail
cd "$(dirname "$0")/.."

BASE_URL="${VIM_TRANSLATOR_BASE_URL:-https://autoai.seewayai.com}"
MODEL="${VIM_TRANSLATOR_MODEL:-glm-5.3}"

NVIM=(nvim --headless -u NORC -n -i NONE
  -c 'set rtp+=.'
  -c 'runtime plugin/translator.lua'
  -c "lua require('vim-translator').setup({ llm = { base_url = '${BASE_URL}', model = '${MODEL}' } })")

# 用例 1：normal 模式 :Translate → 光标单词
out=$("${NVIM[@]}" \
  -c 'normal ihello world' \
  -c 'normal $' \
  -c 'Translate' \
  -c 'sleep 25' \
  -c 'lua local ui = require("vim-translator.ui"); print("WORD_TEST ui_open=" .. tostring(ui.is_open()))' \
  -c 'qa!' 2>&1 || true)
echo "case1 (word): $out"

# 用例 2：visual 模式 :Translate → 选中文本（模拟用户 n/v 各映射一个键）
out=$("${NVIM[@]}" \
  -c 'normal ithis is a translation plugin test' \
  -c 'nmap <buffer> <leader>t <cmd>Translate<cr>' \
  -c 'vmap <buffer> <leader>t <cmd>Translate<cr>' \
  -c 'call feedkeys("ggVG\\t", "xt")' \
  -c 'sleep 25' \
  -c 'lua local ui = require("vim-translator.ui"); print("SENT_TEST ui_open=" .. tostring(ui.is_open()))' \
  -c 'qa!' 2>&1 || true)
echo "case2 (sentence): $out"

# 用例 3：单元测试
out=$("${NVIM[@]}" \
  -c "lua dofile('tests/spec/unit_test.lua')" \
  -c 'qa!' 2>&1 || true)
echo "case3 (unit): $out"

# 用例 4：ACP 后端 spawn 模式（mock agent）：单词 + 句子 + 会话复用
out=$(nvim --headless -u NORC -n -i NONE \
  -c 'set rtp+=.' \
  -c 'runtime plugin/translator.lua' \
  -c "lua require('vim-translator').setup({ provider = 'acp', acp = { mode = 'spawn', command = 'python3', args = { 'tests/acp/mock_agent.py' }, timeout = 10 } })" \
  -c 'lua dofile("tests/acp/acp_test.lua")' \
  -c 'sleep 8' \
  -c 'qa!' 2>&1 || true)
echo "case4 (acp): $out"

# 用例 5：ACP 后端 connect 模式（mock agent 起本地 TCP 服务）
python3 tests/acp/mock_agent_serve.py 8378 &
BRIDGE_PID=$!
sleep 1
out=$(nvim --headless -u NORC -n -i NONE \
  -c 'set rtp+=.' \
  -c 'runtime plugin/translator.lua' \
  -c "lua require('vim-translator').setup({ provider = 'acp', acp = { mode = 'connect', host = '127.0.0.1', port = 8378, timeout = 10 } })" \
  -c 'lua dofile("tests/acp/acp_test.lua")' \
  -c 'sleep 8' \
  -c 'qa!' 2>&1 || true)
kill $BRIDGE_PID 2>/dev/null
echo "case5 (acp-connect): $out"
