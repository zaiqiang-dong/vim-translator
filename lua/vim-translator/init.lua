-- vim-translator: setup 入口、命令、键位
local config = require("vim-translator.config")
local highlights = require("vim-translator.highlights")
local text = require("vim-translator.text")
local api = require("vim-translator.api")
local ui = require("vim-translator.ui")
local M = {}

local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

---核心：翻译 text 并浮窗展示
local function show(text_to_translate)
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
      ui.show_result(result)
    end
  end)
end

---按行列范围替换选区为译文（可 u 撤销）
---@param linewise boolean 行模式（V 选择）时整行替换
local function replace_range(sl, sc, el, ec, selected, linewise)
  local err = config.validate()
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  api.translate(selected, function(result, e)
    if e then
      vim.notify(e, vim.log.levels.ERROR)
      return
    end
    local translation = ui.result_text(result)
    if not translation or translation == "" then
      vim.notify("vim-translator: 未获得译文", vim.log.levels.WARN)
      return
    end
    local new_lines
    if linewise then
      new_lines = vim.split(translation, "\n", { plain = true })
    else
      local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
      local head = lines[1]:sub(1, sc - 1)
      local tail = lines[#lines]:sub(ec + 1)
      new_lines = vim.split(head .. translation .. tail, "\n", { plain = true })
    end
    vim.api.nvim_buf_set_lines(0, sl - 1, el, false, new_lines)
  end)
end

---命令/键位分发
function M.dispatch(kind)
  if kind == "word" then
    local word = text.cursor_word()
    if word then
      show(word)
    end
  elseif kind == "line" then
    local line = text.current_line()
    if line then
      show(line)
    end
  elseif kind == "sentence" then
    -- visual 模式下调用：先取选区，再退出 visual
    local selected = text.visual_selection()
    vim.api.nvim_feedkeys(esc, "n", false)
    if selected then
      show(selected)
    end
  elseif kind == "replace" then
    local selected = text.visual_selection()
    if not selected then
      vim.notify("vim-translator: 选区为空", vim.log.levels.WARN)
      return
    end
    -- 记录选区行列与模式后退出 visual，避免替换时 marks 已变
    local linewise = vim.fn.mode() == "V"
    local sl, sc, el, ec = text.visual_range()
    vim.api.nvim_feedkeys(esc, "n", false)
    replace_range(sl, sc, el, ec, selected, linewise)
  elseif kind == "close" then
    ui.close()
  end
end

function M.setup(opts)
  config.setup(opts)
  highlights.setup()
  local keys = config.opts.keys
  if not config.opts.no_default_maps then
    local maps = {
      { keys.word, "n", "word", "翻译光标单词" },
      { keys.line, "n", "line", "翻译当前行" },
      { keys.sentence, "v", "sentence", "翻译选中句子" },
      { keys.replace, "v", "replace", "翻译并替换选中文本" },
      { keys.close, "n", "close", "关闭翻译浮窗" },
    }
    for _, m in ipairs(maps) do
      local lhs, mode, kind, desc = m[1], m[2], m[3], m[4]
      if lhs and lhs ~= false and lhs ~= "" then
        vim.keymap.set(mode, lhs, function()
          M.dispatch(kind)
        end, { desc = desc, silent = true })
      end
    end
  end
end

-- 未经 setup 直接经 :Translate 命令进入时，应用默认配置
if not config.opts then
  M.setup({})
end

return M
