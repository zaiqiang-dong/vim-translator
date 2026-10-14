-- vim-translator: 默认配置与配置校验
local M = {}

M.defaults = {
  -- 大模型服务（OpenAI 兼容），必填；api_key 也可经环境变量 VIM_TRANSLATOR_API_KEY
  llm = {
    base_url = "https://autoai.seewayai.com",
    api_key = "",
    model = "glm-5.3",
    temperature = 0.1,
    timeout = 60, -- 秒
    proxy = "",
    extra_body = {}, -- 透传给 API 的额外字段
  },
  -- 语言方向固定自动检测（含中文→译英，否则→译中），无配置项

  no_default_maps = false,
  keys = {
    word = "<leader>w", -- n 模式：光标单词
    line = "<leader>l", -- n 模式：当前行
    sentence = "<leader>s", -- v 模式：选中句子
    replace = "<leader>r", -- v 模式：翻译并替换选中文本
    close = "<leader>q", -- n 模式：关闭浮窗
  },

  window = {
    max_width = 60,
    max_height = 20,
    border = "rounded",
    opacity = 0.95, -- winblend
  },

  -- 字段颜色：nil/{} 表示跟随主题默认；此处默认值见 highlights.lua 的 fallback 链
  highlights = {
    title = { fg = "#61afef", bold = true },
    phonetic = { fg = "#98c379" },
    pos = { fg = "#e5c07b" },
    trans = { fg = "#abb2bf" },
    example = { fg = "#7f848e", italic = true },
    example_trans = { fg = "#56b6c2" },
    error = { fg = "#e06c75", bold = true },
    loading = { fg = "#c678dd", italic = true },
  },
}

M.opts = nil

---合并用户配置（浅层逐节合并）
function M.setup(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend("keep", opts, M.defaults)
  M.opts = merged
  return merged
end

---读取 api_key：配置优先，其次环境变量
function M.api_key()
  local key = M.opts and M.opts.llm.api_key or ""
  if key == "" then
    key = vim.env.VIM_TRANSLATOR_API_KEY or ""
  end
  return key
end

---首次调用时校验，返回错误字符串或 nil
function M.validate()
  if not vim.fn.executable("curl") then
    return "vim-translator: 需要 curl（未找到可执行文件）"
  end
  local llm = M.opts.llm
  if not llm.base_url or llm.base_url == "" then
    return "vim-translator: 未配置 llm.base_url"
  end
  if M.api_key() == "" then
    return "vim-translator: 未配置 llm.api_key（或环境变量 VIM_TRANSLATOR_API_KEY）"
  end
  if not llm.model or llm.model == "" then
    return "vim-translator: 未配置 llm.model"
  end
  return nil
end

return M
