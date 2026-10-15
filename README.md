# vim-translator

基于大模型（OpenAI 兼容 API）的 **中英文互译** Neovim 插件（纯 Lua）。

- 仅中英互译，自动检测方向：文本含中文 → 译成英文；否则 → 译成中文
- **两种翻译后端**：直连 OpenAI 兼容 API，或通过 **ACP agent**（claude / gemini / codex / opencode 等任一 ACP 兼容智能体）翻译
- **单一键位**：没选中就翻译光标单词（词典式：音标、词性、释义、例句）；选中了就翻译选中的句子/段落
- 浮窗展示，各字段（音标/词性/释义/例句）分别配色，按任意键自动关闭；按 `i` 用译文替换原文
- 异步请求（`vim.system`），不阻塞编辑
- 支持 lazy.nvim 懒加载

## 依赖

- Neovim ≥ 0.10（`vim.system`）
- `curl`

## 安装

### lazy.nvim（推荐）

```lua
{
  "zaiqdong/vim-translator",
  lazy = true,
  cmd = { "Translate" },
  keys = {
    { "<leader>t", "<cmd>Translate<cr>", mode = { "n", "v" }, desc = "翻译单词/选中文本" },
  },
  opts = {
    llm = {
      base_url = "https://autoai.seewayai.com",
      model = "glm-5.3",
    },
  },
}
```

`api_key` 建议放环境变量（`~/.zshrc` / `~/.bashrc`）：

```sh
export VIM_TRANSLATOR_API_KEY="sk-xxxx"
```

也可以直接写在 `opts.llm.api_key` 里。

### 手动安装

```lua
-- init.lua
require("vim-translator").setup({
  llm = {
    base_url = "https://autoai.seewayai.com",
    api_key = "sk-xxxx", -- 或用环境变量 VIM_TRANSLATOR_API_KEY
    model = "glm-5.3",
  },
})
```

任意 OpenAI 兼容服务（DeepSeek、通义、本地 vLLM/Ollama 等）均可：改 `base_url`
（**不含** `/v1` 后缀，插件自动拼接 `/v1/chat/completions`）与 `model` 即可。

## 用法

插件**不内置任何键位**，通过 `:Translate` 命令触发；键位由你自行映射。

`Translate` 的行为随调用时的模式自动切换：

| 调用时模式 | 行为 |
|---|---|
| normal（未选中） | 翻译光标所在单词（词典式结果） |
| visual（有选区） | 翻译选中的句子/段落 |

推荐映射（同一个键，n/v 两种模式各一份，放在 lazy spec 的 `keys` 里）：

```lua
vim.keymap.set("n", "<leader>t", "<cmd>Translate<cr>", { desc = "翻译光标单词" })
vim.keymap.set("v", "<leader>t", "<cmd>Translate<cr>", { desc = "翻译选中句子" })
```

浮窗打开后的按键行为：

- **任意键**：关闭浮窗
- **`i`**：用译文**替换原文**（单词翻译替换光标单词；选区翻译替换选中部分；均可 `u` 撤销），替换后光标停在译文末尾并进入插入模式

单词翻译效果（浮窗）：

```
◆ hello  /həˈloʊ/
  int. 你好；（用于打招呼）喂
  n. 问候，招呼
  · "Hello, how are you today?"
    你好，你今天怎么样？
```

## 配置

全部默认值（省略的项保持默认）。两个翻译后端二选一：`provider = "llm"`（默认，
直连 OpenAI 兼容 API）或 `provider = "acp"`（通过 ACP agent 翻译）：

```lua
require("vim-translator").setup({
  provider = "llm",           -- "llm" | "acp"

  -- 后端一：OpenAI 兼容 API（默认）
  llm = {
    base_url = "https://autoai.seewayai.com",
    api_key = "",              -- 空则读环境变量 VIM_TRANSLATOR_API_KEY
    model = "glm-5.3",
    temperature = 0.1,
    timeout = 60,              -- 秒
    proxy = "",                -- 可选 http(s):// 代理
    extra_body = {},           -- 透传给 API 的额外 JSON 字段
  },

  -- 后端二：ACP agent（provider = "acp" 时启用），两种接入方式
  acp = {
    mode = "spawn",            -- "spawn"（默认）：插件直接拉起 agent 子进程
                               -- "connect"：连接后台 ACP 服务（TCP/socket），插件纯 client
    -- spawn 模式：agent 命令（默认 traecli，可换 claude/opencode 等）
    command = "traecli",
    args = { "acp", "serve" },
    env = {},                  -- 额外环境变量

    -- connect 模式（TCP 或 unix socket 二选一）
    host = "127.0.0.1",
    port = 8377,
    socket = "",               -- 非空则优先用 unix socket

    timeout = 120,             -- 秒
  },

  window = {
    max_width = 60,
    max_height = 20,
    border = "rounded",
    opacity = 0.95,            -- 1.0 完全不透明
  },

  -- 字段颜色：高亮属性表；nil/{} 跟随主题
  highlights = {
    title         = { fg = "#61afef", bold = true },   -- 标题
    phonetic      = { fg = "#98c379" },                -- 音标
    pos           = { fg = "#e5c07b" },                -- 词性
    trans         = { fg = "#abb2bf" },                -- 释义/译文
    example       = { fg = "#7f848e", italic = true }, -- 例句原文
    example_trans = { fg = "#56b6c2" },                -- 例句译文
    error         = { fg = "#e06c75", bold = true },   -- 错误
    loading       = { fg = "#c678dd", italic = true }, -- 加载中
  },
})
```

配置只是初始值，运行时可随时用 `:hi VTPhonetic guifg=red` 临时覆盖。
高亮组：`VTTitle` `VTPhonetic` `VTPos` `VTTrans` `VTExample` `VTExampleTrans`
`VTError` `VTLoading`。

### ACP 后端示例

**spawn 模式（默认，推荐，零操作）**：插件在首次翻译时直接拉起
`traecli acp serve` 子进程并保持常驻（会话复用），退出 nvim 时自动收掉进程。
不需要手动启动任何服务：

```lua
require("vim-translator").setup({
  provider = "acp",
  acp = { mode = "spawn", command = "traecli", args = { "acp", "serve" } },
})
-- 或其他 agent：
-- acp = { mode = "spawn", command = "claude", args = { "--experimental-acp" } }
-- acp = { mode = "spawn", command = "opencode", args = { "acp" } }
```

注意：ACP 协议基于 stdio（stdin/stdout 管道），**在终端里手动跑
`traecli acp serve` 是连不上的**——它只和持有它管道的进程通信，不监听任何端口。
所以"手动启动服务 + 插件连接"必须有一个 stdio→socket 的桥接（见 connect 模式）；
不想桥接就用 spawn 模式，插件自己持有管道。

**connect 模式**（插件纯 client，服务独立于 nvim 常驻）：需要把 stdio 的 agent
暴露成 TCP，可用仓库自带的 `scripts/acp_bridge.py`（或 socat）：

```sh
python3 /path/to/vim-translator/scripts/acp_bridge.py 8377 -- traecli acp serve &
```

```lua
require("vim-translator").setup({
  provider = "acp",
  acp = { mode = "connect", host = "127.0.0.1", port = 8377 },
})
```

首次翻译时连接并完成 `initialize` + `session/new` 握手，之后所有翻译复用该连接
（`session/prompt`）；连接断开自动报错，下次翻译自动重连。

两种模式 agent 均需已自行登录/配置好模型。

## 测试

```sh
VIM_TRANSLATOR_API_KEY=sk-xxx tests/run_headless.sh
```

headless 冒烟（单词/选区浮窗）+ 单元测试（方向检测、单词判定）+ ACP 后端
spawn/connect 两种模式（`tests/acp/mock_agent*.py` 模拟 agent，无需真实服务）。

## 开发文档

见 [doc/DEVELOPMENT.md](doc/DEVELOPMENT.md)。
