-- vim-translator: setup 入口、命令、键位
local config = require("vim-translator.config")
local highlights = require("vim-translator.highlights")
local text = require("vim-translator.text")
local api = require("vim-translator.api")
local ui = require("vim-translator.ui")
local M = {}

local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

---核心：翻译 text 并浮窗展示；range 记录原文范围供按 i 替换
local function show(text_to_translate, range)
  local err = config.validate()
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  ui.show_loading(text_to_translate)
  api.translate(text_to_translate, function(result, e)
    if e then
      ui.show_error(e)
    else
      ui.show_result(result, range)
    end
  end)
end

---单一入口：有选区翻译选区，否则翻译光标单词
---visual 模式下调用（选区有效）；normal 模式下调用（光标单词）
function M.dispatch(kind)
  if kind == "close" then
    ui.close()
    return
  end

  local target
  local range = nil -- {sl,sc,el,ec,linewise} 原文范围，按 i 替换用
  if vim.fn.mode():find("^[vV\22]") then
    -- visual 模式：记录选区范围与文本后退出 visual
    local sl, sc, el, ec = text.visual_range()
    range = { sl = sl, sc = sc, el = el, ec = ec, linewise = vim.fn.mode() == "V" }
    target = text.visual_selection()
    vim.api.nvim_feedkeys(esc, "n", false)
  else
    target = text.cursor_word()
    if target then
      -- 光标单词的字节范围
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2] + 1
      local s = line:sub(1, col):match("()%f[%w_][%w_]*$")
      local e = line:sub(col):match("^[%w_]*%f[%w_]()")
      if s and e then
        range = { sl = vim.fn.line("."), sc = s, el = vim.fn.line("."), ec = s + e - 2, linewise = false }
      end
    end
  end

  if target then
    show(target, range)
  end
end

function M.setup(opts)
  config.setup(opts)
  highlights.setup()
  -- 不内置任何键位：用户通过 :Translate 命令或自行 vim.keymap.set 调用
end

-- 未经 setup 直接经 :Translate 命令进入时，应用默认配置
if not config.opts then
  M.setup({})
end

return M
