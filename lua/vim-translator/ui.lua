-- vim-translator: 浮窗与结果渲染（结构化字段 + extmark 高亮）
local config = require("vim-translator.config")
local hl = require("vim-translator.highlights")

local M = {}

local win = nil
local buf = nil
local ns = vim.api.nvim_create_namespace("vim-translator")
local close_ns = vim.api.nvim_create_namespace("vim-translator-close")

-- 最近一次翻译的纯译文（按 i 插入用）与其原文范围（按 i 替换用）
local last_result = nil
local last_range = nil -- {sl,sc,el,ec,linewise}

---渲染行模型：{ { text = "n. ", hl = "VTPos" }, ... } 的一行
---先构造模型再统一写 buffer，便于测试

---单词模式 → 渲染行模型
local function render_word(data)
  local lines = {}
  local function add(parts)
    table.insert(lines, parts)
  end

  local title = data.word or ""
  if data.phonetic and data.phonetic ~= "" then
    title = title .. "  " .. data.phonetic
  end
  add({
    { text = "◆ " .. title, hl = hl.groups.title },
  })

  for _, def in ipairs(data.defs or {}) do
    local parts = {}
    if def.pos and def.pos ~= "" then
      table.insert(parts, { text = "  " .. def.pos .. " ", hl = hl.groups.pos })
    else
      table.insert(parts, { text = "  ", hl = hl.groups.trans })
    end
    table.insert(parts, { text = def.trans or "", hl = hl.groups.trans })
    add(parts)
  end

  for _, ex in ipairs(data.examples or {}) do
    add({ { text = "", hl = hl.groups.example } })
    if ex.en and ex.en ~= "" then
      add({ { text = '  · "' .. ex.en .. '"', hl = hl.groups.example } })
    end
    if ex.zh and ex.zh ~= "" then
      add({ { text = "    " .. ex.zh, hl = hl.groups.example_trans } })
    end
  end

  return lines
end

---句子/纯文本模式 → 渲染行模型
local function render_sentence(data)
  local lines = {}
  local tag
  if data.source_lang == "zh" then
    tag = "中 → 英"
  elseif data.source_lang == "en" then
    tag = "英 → 中"
  end
  if tag then
    table.insert(lines, { { text = "◆ " .. tag, hl = hl.groups.title } })
  end
  for _, l in ipairs(vim.split(data.translation or "", "\n", { plain = true })) do
    table.insert(lines, { { text = l, hl = hl.groups.trans } })
  end
  return lines
end

---错误 → 渲染行模型
local function render_error(err)
  return { { { text = "✗ " .. err, hl = hl.groups.error } } }
end

---加载中 → 渲染行模型
local function render_loading(text)
  local preview = text:gsub("\n", " ")
  if #preview > 30 then
    preview = preview:sub(1, 30) .. "…"
  end
  return { { { text = "⏳ 翻译中: " .. preview, hl = hl.groups.loading } } }
end

---把渲染行模型写进浮窗 buffer（nvim_buf_set_lines + extmark 上色）
local function apply_model(lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local texts = {}
  for _, parts in ipairs(lines) do
    local t = ""
    for _, p in ipairs(parts) do
      t = t .. p.text
    end
    table.insert(texts, t)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, parts in ipairs(lines) do
    local col = 0
    for _, p in ipairs(parts) do
      local len = vim.fn.strdisplaywidth(p.text)
      if len > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, {
          end_col = col + #p.text,
          hl_group = p.hl,
        })
      end
      col = col + #p.text
    end
  end
end

---从结果表提取纯译文文本
---@param result table
---@return string|nil
local function result_text(result)
  if not result then
    return nil
  end
  if result.kind == "word" then
    -- 单词：拼接各词性释义（如 "你好；（用于打招呼）喂; 问候，招呼"）
    local parts = {}
    for _, def in ipairs(result.data.defs or {}) do
      table.insert(parts, def.trans or "")
    end
    return table.concat(parts, "; ")
  end
  return result.data.translation
end

---按 i：关闭浮窗，用译文替换原文范围（可 u 撤销），并进入插入模式
local function insert_result()
  local text = result_text(last_result)
  M.close()
  if not text or text == "" then
    return
  end
  local new_lines = vim.split(text, "\n", { plain = true })
  local r = last_range

  if not r then
    -- 无原文范围（异常情况）：退回光标处插入
    local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_text(0, lnum - 1, col, lnum - 1, col, new_lines)
    vim.api.nvim_win_set_cursor(0, { lnum, col + #(new_lines[1] or "") })
    vim.cmd("startinsert")
    return
  end

  if r.linewise then
    -- 行模式：整行替换
    vim.api.nvim_buf_set_lines(0, r.sl - 1, r.el, false, new_lines)
    vim.api.nvim_win_set_cursor(0, { r.sl + #new_lines - 1, #(new_lines[#new_lines]) })
  else
    -- 字符模式：head + 译文 + tail
    local lines = vim.api.nvim_buf_get_lines(0, r.sl - 1, r.el, false)
    if #lines >= 1 and r.sc <= #lines[1] and r.ec <= #lines[#lines] then
      local head = lines[1]:sub(1, r.sc - 1)
      local tail = lines[#lines]:sub(r.ec + 1)
      local all = {}
      for i, l in ipairs(new_lines) do
        table.insert(all, (i == 1 and head or "") .. l .. (i == #new_lines and tail or ""))
      end
      vim.api.nvim_buf_set_lines(0, r.sl - 1, r.el, false, all)
      vim.api.nvim_win_set_cursor(0, { r.sl + #all - 1, #(all[#all]) })
    else
      -- 原文行已被改动（范围越界）：退回光标处插入
      local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
      vim.api.nvim_buf_set_text(0, lnum - 1, col, lnum - 1, col, new_lines)
      vim.api.nvim_win_set_cursor(0, { lnum, col + #(new_lines[1] or "") })
    end
  end
  vim.cmd("startinsert")
end
local function resize()
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local wcfg = config.opts.window
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local height = math.min(#lines, wcfg.max_height)
  width = math.min(width + 2, wcfg.max_width)
  vim.api.nvim_win_set_config(win, { width = width, height = math.max(height, 1) })
end

---确保浮窗存在（复用同一 buf/win），光标右上角，自动防溢出
function M.open()
  if win and vim.api.nvim_win_is_valid(win) then
    return
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = "translator"
  end
  local wcfg = config.opts.window
  win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = 40,
    height = 1,
    border = wcfg.border,
    style = "minimal",
  })
  vim.wo[win].winblend = math.floor((1 - wcfg.opacity) * 100)
  -- 任意键按下即关闭；按 i 则先把译文插入光标处再关闭
  local close_aug = vim.api.nvim_create_augroup("vim-translator-close", { clear = true })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = close_aug,
    buffer = 0,
    callback = M.close,
  })
  vim.on_key(function(_, typed)
    if typed ~= "" and M.is_open() then
      if typed == "i" and last_result then
        insert_result() -- 内部会 close
        return
      end
      M.close()
    end
  end, close_ns)
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  vim.on_key(nil, close_ns)
  vim.api.nvim_clear_autocmds({ group = "vim-translator-close" })
end

function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---显示"翻译中"
function M.show_loading(text)
  M.open()
  apply_model(render_loading(text))
  resize()
end

---显示翻译结果（api.lua 的 result 表）；range 为原文范围，按 i 时替换用
function M.show_result(result, range)
  local lines
  if result.kind == "word" then
    lines = render_word(result.data)
  else
    lines = render_sentence(result.data)
  end
  last_result = result
  last_range = range
  apply_model(lines)
  resize()
end

---显示错误
function M.show_error(err)
  M.open()
  apply_model(render_error(err))
  resize()
end

return M
