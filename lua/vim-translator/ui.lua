-- vim-translator: 浮窗与结果渲染（结构化字段 + extmark 高亮）
local config = require("vim-translator.config")
local hl = require("vim-translator.highlights")

local M = {}

local win = nil
local buf = nil
local ns = vim.api.nvim_create_namespace("vim-translator")

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

---按内容行数/宽度调整浮窗大小
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
  -- 关闭键（buf-local）
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = 0,
    once = true,
    callback = function()
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_config(win, { relative = "cursor", row = 1, col = 0 })
      end
    end,
  })
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
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

---显示翻译结果（api.lua 的 result 表）
function M.show_result(result)
  local lines
  if result.kind == "word" then
    lines = render_word(result.data)
  else
    lines = render_sentence(result.data)
  end
  apply_model(lines)
  resize()
end

---显示错误
function M.show_error(err)
  M.open()
  apply_model(render_error(err))
  resize()
end

---取纯译文文本（TranslateReplace 用）
---@param result table
---@return string|nil
function M.result_text(result)
  if not result then
    return nil
  end
  if result.kind == "word" then
    local parts = {}
    for _, def in ipairs(result.data.defs or {}) do
      table.insert(parts, def.trans or "")
    end
    return table.concat(parts, "; ")
  end
  return result.data.translation
end

return M
