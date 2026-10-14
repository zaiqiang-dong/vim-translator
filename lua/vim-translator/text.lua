-- vim-translator: 文本获取与语言方向判定
local M = {}

---文本是否含 CJK 字符（中日韩统一表意文字 + 扩展A + 兼容表意）
---@param text string
---@return boolean
function M.has_cjk(text)
  return text:find("[\u{4e00}-\u{9fff}\u{3400}-\u{4dbf}\u{f900}-\u{faff}]") ~= nil
end

---自动检测方向：含中文 → 译英（"en"），否则 → 译中（"zh"）
---@param text string
---@return "zh"|"en" target_lang 目标语言
function M.detect_target(text)
  if M.has_cjk(text) then
    return "en"
  end
  return "zh"
end

---光标所在单词（<cword>，keyword 字符集）；空白处返回 nil
---@return string|nil
function M.cursor_word()
  local word = vim.fn.expand("<cword>")
  if word == "" then
    return nil
  end
  return word
end

---当前可视选择的模式：'v' | 'V' | '\22'（块选）；仅在 visual 模式下调用
local function visual_kind()
  return vim.fn.mode()
end

---可视选区的行列范围（sl,sc,el,ec），规范化为 start ≤ end；仅在 visual 模式下调用
---visual 模式下 '< 尚未更新，用 v 标记（选区起点）与 . （光标）
---注意：光标列指向多字节字符的首字节，字符级包含选择应推进 ec 到该字符末字节
---@return integer,integer,integer,integer
function M.visual_range()
  local kind = visual_kind()
  local s = vim.fn.getpos("v")
  local e = vim.fn.getpos(".")
  local sl, sc, el, ec = s[2], s[3], e[2], e[3]
  if sl > el or (sl == el and sc > ec) then
    sl, sc, el, ec = el, ec, sl, sc
  end
  if kind ~= "V" then
    -- 字符级选择：光标列是 1 基字节位，且指向多字节字符首字节；
    -- 选择包含整个字符，ec 推进到该字符末字节（charidx/byteidx 均为 0 基字节偏移）
    local lastline = vim.api.nvim_buf_get_lines(0, el - 1, el, false)[1] or ""
    local ci = vim.fn.charidx(lastline, ec - 1)
    if ci >= 0 then
      local nextb = vim.fn.byteidx(lastline, ci + 1)
      ec = nextb > 0 and nextb or #lastline
    end
  end
  return sl, sc, el, ec
end

---可视模式选中文本（保留换行）；仅在 visual 模式下调用
---@return string|nil
function M.visual_selection()
  local sl, sc, el, ec = M.visual_range()
  local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
  if #lines == 0 then
    return nil
  end
  if visual_kind() ~= "V" then
    lines[#lines] = lines[#lines]:sub(1, ec)
    lines[1] = lines[1]:sub(sc)
  end
  local text = table.concat(lines, "\n")
  if text:match("^%s*$") then
    return nil
  end
  return text
end

---判定单词模式：无空格、单行、长度 ≤ 40 且含字母或中文
---@param text string
---@return boolean
function M.is_word(text)
  if text:find("[\n\r]") or text:find("%s") then
    return false
  end
  if #text > 40 then
    return false
  end
  return text:find("%a") ~= nil or M.has_cjk(text)
end

return M
