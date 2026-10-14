# vim-translator 开发文档

一个基于大模型（LLM）的**中英文互译** Neovim 插件，**Lua 实现**，支持单词和句子翻译、
语言自动检测（中→英 / 英→中）、字段级高亮配色、lazy.nvim 懒加载。
仅支持中英两种语言，不引入其他语言。

- 仓库：`/home/zaiqdong/work/vim-translator`
- 目标环境：Neovim ≥ 0.9（本机 0.13-dev）
- 文档版本：v0.3（2026-10-14，需求更新：仅中英互译，方向固定自动检测，去掉手动指定）

---

## 1. 项目目标

在 Neovim 内通过调用大模型 API 完成中英互译（**仅中英两种语言**）：

1. **单词翻译**：按键翻译光标下单词，返回释义、音标、词性、例句等词典信息。
2. **句子翻译**：可视模式选中句子，按键翻译整句。
3. **方向自动检测**：文本含中文 → 译成英文；否则 → 译成中文。固定规则，无配置项、无手动指定。
4. **按键可配置**：所有触发键可自定义，也可禁用默认键位。
5. **字段颜色可配置**：译文标题、音标、词性、释义、例句等字段分别配色。
6. **lazy.nvim 懒加载**：`lazy = true` + `cmd`/`keys` 触发，首按才加载。
7. **大模型参数可配置**：base_url、api_key、model、temperature、超时、代理等。
8. **异步无卡顿**：请求异步执行，翻译期间不阻塞编辑。

## 2. 总体架构

```
用户按键（<leader>w / <leader>s ...）
        │
        ▼
 取文本：光标单词（<cword>） / 可视选区（visual selection）
        │
        ▼
 判断翻译方向：文本含中文 → zh→en，否则 → en→zh（固定规则，无配置）
        │
        ▼
 组装 OpenAI 兼容 chat/completions 请求
 （system prompt 按单词/句子两种模板）
        │
        ▼
 curl 异步请求（vim.system 或 jobstart + curl）
        │
        ▼
 回调解析 JSON → 按 JSON 结构化字段渲染浮窗（逐字段高亮）
```

核心原则：

- **纯 Lua 模块**，不依赖 Python/Node；外部只依赖 `curl`。
- **OpenAI 兼容协议**：只实现 `/v1/chat/completions`，兼容 OpenAI / DeepSeek /
  通义 / 智谱 / 本地 vLLM/Ollama 等，用户只需提供 `base_url` + `api_key` + `model`。
- **结构化输出**：要求大模型返回 JSON（`response_format: json_object`，
  不支持的服务自动回退为纯文本），这是"字段分别配色"的基础。
- **模块分层**：config / text（取词取选区）/ api（请求解析）/ ui（浮窗渲染高亮）解耦。

## 3. 目录结构

```
vim-translator/
├── README.md                    # 用户文档（安装、配置、用法）
├── doc/
│   ├── DEVELOPMENT.md           # 本文档
│   └── vim-translator.txt      # Vim help 格式文档（:help vim-translator）
├── lua/
│   ├── vim-translator/
│   │   ├── init.lua             # setup() 入口、默认配置合并、命令注册
│   │   ├── config.lua           # 默认配置、配置校验
│   │   ├── text.lua             # 取光标单词 / 取可视选区 / 方向判定
│   │   ├── api.lua              # 请求组装、curl 异步调用、JSON 解析、错误处理
│   │   ├── ui.lua               # 浮窗创建、结构化字段渲染、高亮
│   │   └── highlights.lua       # 高亮组定义 + 从用户配色生成 :highlight
│   └── telescope/               # （后续扩展）telescope 翻译历史
├── plugin/
│   └── translator.lua           # 仅 2 行：创建 :Translate 命令（延迟加载钩子）
├── after/plugin/
│   └── translator.lua           # lazy 场景下 setup 自动调用点
└── tests/
    ├── spec/                    # plenary.nvim 测试（方向判定、解析、渲染行构造）
    └── run_headless.sh          # headless 冒烟测试
```

模块命名：`require("vim-translator")` 为主入口。

## 4. 安装与懒加载

### 4.1 lazy.nvim（推荐）

```lua
{
  "zaiqdong/vim-translator",
  lazy = true,
  cmd = { "Translate" },
  keys = {
    { "<leader>w", desc = "翻译光标单词" },
    { "<leader>s", mode = "v", desc = "翻译选中句子" },
  },
  opts = {},  -- 同第 5 节 setup 配置
}
```

- `lazy = true` + `cmd`/`keys`：插件本体在首次执行 `:Translate` 或按键时才加载。
- `keys` 中的键在加载前由 lazy 的 placeholder 映射接管，加载后由插件重建真实映射。
- 兼容 Packer：`keys` + `commands` 字段同理。

### 4.2 手动（非 lazy）

```lua
-- init.lua
require("vim-translator").setup({ ... })
```

### 4.3 懒加载实现要点（插件侧）

- `plugin/translator.lua` 里只做一件事：定义 `:Translate` 用户命令
  （`vim.api.nvim_create_user_command(..., function() require("vim-translator") ... end)`），
  命令回调里才 `require` 主模块 —— 保证即使用户没配 lazy，插件启动开销也接近零。
- 默认键位在 `setup()` 里创建（`vim.keymap.set`），`setup` 由 lazy 的 `opts`
  机制在加载时调用。

## 5. 配置项（用户侧 setup）

```lua
require("vim-translator").setup({
  -- 大模型服务（OpenAI 兼容，均必填或经环境变量提供）
  llm = {
    base_url = "https://api.example.com/v1",  -- 注意含 /v1
    api_key  = "sk-xxxx",                      -- 或环境变量 VIM_TRANSLATOR_API_KEY
    model    = "deepseek-chat",
    temperature = 0.1,
    timeout    = 30,          -- 秒
    proxy      = "",          -- 可选 http(s):// 代理
    extra_body = {},          -- 透传给 API 的额外字段（如 top_p、自定义参数）
  },

  -- 语言方向：仅中英互译，自动检测，无配置项
  -- 检测规则：文本含 CJK 字符（[\u4e00-\u9fff] 等）→ zh→en；否则 → en→zh

  -- 默认键位（设为 false 禁用该键；设 no_default_maps=true 全禁用）
  no_default_maps = false,
  keys = {
    word    = "<leader>w",             -- n 模式：光标单词
    line    = "<leader>l",             -- n 模式：当前行
    sentence = "<leader>s",            -- v 模式：选中句子
    replace = "<leader>r",             -- v 模式：翻译并替换选中文本
    close   = "<leader>q",             -- n 模式：关闭翻译浮窗
  },

  -- 浮窗外观
  ui = "float",                         -- float | preview
  window = {
    max_width  = 60,
    max_height = 20,
    border  = "rounded",
    opacity = 0.95,                     -- winblend
  },

  -- 字段颜色（值为 highlight 属性表，见第 8 节）
  highlights = {
    title     = { fg = "#61afef", bold = true },   -- 标题行 "◆ hello / 你好"
    phonetic  = { fg = "#98c379" },                -- 音标 /həˈloʊ/
    pos       = { fg = "#e5c07b" },                -- 词性 n./v./adj.
    trans     = { fg = "#abb2bf" },                -- 释义正文
    example   = { fg = "#7f848e", italic = true }, -- 例句原文
    example_trans = { fg = "#56b6c2" },            -- 例句译文
    error     = { fg = "#e06c75", bold = true },   -- 错误信息
    loading   = { fg = "#c678dd", italic = true }, -- "翻译中..."
  },
})
```

校验（`config.lua`）：`base_url`/`model` 未配置时首次调用给出明确报错；
`api_key` 取值优先级 `llm.api_key` > `$VIM_TRANSLATOR_API_KEY`。

## 6. 命令与键位

| 命令 | 模式/范围 | 默认键 | 行为 |
|---|---|---|---|
| `:Translate` | normal | `<leader>w` | 翻译光标所在单词（词典式结果） |
| `:Translate` | visual | `<leader>s` | 翻译选中的句子/段落 |
| `:TranslateLine` | normal | `<leader>l` | 翻译当前行 |
| `:TranslateReplace` | visual | `<leader>r` | 翻译并**替换**选中文本（可 `u` 撤销） |
| `:TranslateClose` | normal | `<leader>q` | 关闭浮窗 |

语言方向**始终自动检测**，不提供手动指定参数：文本含 CJK 字符 → 译成英文；
否则 → 译成中文。仅支持中英互译，不引入其他语言。

浮窗内键位：`q` / `<Esc>` 关闭（`buf`-local 映射，不影响全局）。

## 7. 大模型请求设计（api.lua）

### 7.1 请求体

```json
POST {base_url}/chat/completions
Authorization: Bearer {api_key}
Content-Type: application/json

{
  "model": "...",
  "temperature": 0.1,
  "response_format": { "type": "json_object" },
  "messages": [
    { "role": "system", "content": "<见 7.2>" },
    { "role": "user", "content": "<待翻译文本，原样保留换行>" }
  ]
}
```

`response_format: json_object` 让模型稳定输出 JSON；若服务返回 4xx 表明不支持该参数，
自动去掉此字段重试一次（回退为纯文本，浮窗整体用 `trans` 高亮显示）。

### 7.2 System Prompt

**单词模式**（判定：文本无空格、单行、长度 ≤ 40）：

```
你是一个中英双语词典引擎。只输出 JSON，不要 markdown 代码块。
用户输入英文单词时输出：
{"word":"原文","phonetic":"美式音标","defs":[{"pos":"词性","trans":"中文释义"}],
 "examples":[{"en":"英文例句","zh":"例句中文"}]}
用户输入中文词时：defs 的 trans 给出对应英文释义，phonetic 给拼音。
```

**句子模式**：

```
你是一个专业中英互译引擎。自动检测用户文本的语言：
中文则译成英文，英文则译成中文。
只输出 JSON，不要 markdown 代码块：
{"source":"原文","source_lang":"zh或en","translation":"译文"}
要求：忠实原文、语句通顺、保留换行与段落结构、不加解释。
```

### 7.3 异步执行

优先 `vim.system(cmd, { timeout = ..., text = false }, callback)`（Neovim ≥ 0.10，
本机 0.13-dev 满足），内部即 libuv 进程，无需手写 jobstart；超时由 vim.system
直接支持。curl 命令：

```sh
curl -sS --max-time {timeout} [-x {proxy}] \
  -X POST "{base_url}/chat/completions" \
  -H "Authorization: Bearer {api_key}" \
  -H "Content-Type: application/json" \
  -d @/tmp/vim_translator_{pid}_{seq}.json
```

请求体写临时文件经 `-d @file` 传入，规避 shell 转义/注入（文本可能含引号、反引号、`$`）。用后即删。

**并发控制**：同一时间只保留一个请求，新请求先取消旧请求（`vim.system` 返回的
`:kill()`），避免浮窗内容错乱。

### 7.4 响应解析与错误处理

```lua
local resp = vim.json.decode(raw)
local content = resp.choices[1].message.content
local data = vim.json.decode(strip_code_fence(content))
```

| 场景 | 行为 |
|---|---|
| 未配置 base_url/api_key/model | 报错并明确指出缺哪项 |
| `curl` 不存在 | setup 时 `vim.fn.executable("curl")` 检查 |
| 超时 / exit ≠ 0 | 浮窗显示错误 + exit code |
| API 返回 error | 解析 `error.message` 展示 |
| JSON 解析失败 | 显示前 200 字符原始输出帮助排查 |
| 不支持 response_format | 自动去参重试一次 |
| 空选区 / 光标在空白处 | `vim.notify` 提示后静默返回 |

## 8. 结果展示与字段高亮（ui.lua + highlights.lua）

### 8.1 浮窗

- scratch buffer（`buftype=nofile`，`filetype=translator`），`nvim_open_win`
  光标右上角，自动防溢出（超出右缘左移，高度取 min(行数, max_height)）。
- 请求发出即显示 `⏳ 翻译中...`（`loading` 高亮），回调后整体替换内容。

### 8.2 结构化渲染（单词模式示意）

```
◆ hello                                    ← title   (bold, 蓝)
  /həˈloʊ/                                 ← phonetic(绿)
  n. 你好；打招呼                           ← pos(黄) + trans(灰)
  int. 喂；你好
  · "Hello, how are you?"                  ← example (斜体, 灰)
    你好，你好吗？                          ← example_trans(青)
```

渲染流程：解析出的 JSON → 生成带**行内元数据**的行列表
`{ { text = "n. ", hl = "pos" }, { text = "你好；打招呼", hl = "trans" } }` →
逐行 `nvim_buf_set_lines` + `nvim_buf_add_extmark`（`hl_group`）上色。

### 8.3 高亮组管理（highlights.lua）

- 每个字段一个命名高亮组：`VTTitle` / `VTPhonetic` / `VTPos` / `VTTrans` /
  `VTExample` / `VTExampleTrans` / `VTError` / `VTLoading`。
- `setup()` 时根据 `highlights` 配置逐个 `vim.api.nvim_set_hl(0, "VTxxx", spec)`；
  用户传空表 `{}` 表示"跟随主题默认"（fallback 链：`VTTrans` → `Normal`，
  `VTTitle` → `Title` 等常见组）。
- 用户可随时 `:hi VTPhonetic guifg=red` 直接覆盖（配置只是初始值，不覆盖用户手动 `:hi`）。

## 9. 测试计划

1. **单元**（plenary.nvim，`tests/spec/`）：
   - `text.lua`：方向判定（纯英文/纯中文/中英混合）、选区提取（多行、含 CRLF）。
   - `api.lua`：mock curl 输出的 JSON 解析（含 ```` ```json ```` 包裹、错误体）。
   - `ui.lua`：渲染行构造（单词/句子两种 payload → 期望的行+高亮元数据表）。
2. **冒烟**（headless，`tests/run_headless.sh`）：
   ```sh
   nvim --headless -u NORC \
     -c 'set rtp+=.' \
     -c 'lua require("vim-translator").setup({llm={base_url=...,api_key=...,model=...}})' \
     -c 'normal ihello' \
     -c 'Translate' \
     -c 'sleep 5' -c 'qa!'
   ```
   断言浮窗 buffer 含 "你好"（单词 hello 的释义）。
3. **手工用例**：英文单词、英文长句、中文长句、混合文本选区、Replace+撤销、
   各字段配色修改后重新打开浮窗。

## 10. 里程碑

| 阶段 | 内容 | 产出 |
|---|---|---|
| M1 | Lua 骨架 + setup/config + 同步请求打通（`vim.notify` 输出译文） | `init/config/api.lua` |
| M2 | 异步 + 浮窗 + 结构化渲染 + 字段高亮 | `ui/highlights.lua`，单词/选区可用 |
| M3 | Replace 模式、行翻译、方向自动判断、错误分支 | 全命令可用 |
| M4 | lazy 支持、help 文档、README、测试 | 可发布 v0.1.0 |

## 11. 后续扩展（不在 v1 范围）

- 流式输出（SSE，逐 token 更新浮窗）
- 翻译历史（`:TranslateHistory` + telescope 扩展）
- 项目术语表 / few-shot 注入（保持代码、变量名不译）
- 多语言（日/韩）——当前明确不做，仅中英互译
