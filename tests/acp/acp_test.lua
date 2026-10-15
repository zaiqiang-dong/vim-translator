-- vim-translator ACP 后端 headless 测试（配合 tests/acp/mock_agent.py）
-- 流程：单词翻译 → 会话复用 → 句子翻译，dump 浮窗内容
local dump = function(tag)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "translator" then
      local ls = vim.api.nvim_buf_get_lines(b, 0, -1, false)
      print(tag .. ": " .. table.concat(ls, " | "))
      return
    end
  end
  print(tag .. ": NO FLOAT")
end

vim.cmd("normal ihello world")
vim.cmd("normal 0")
vim.cmd("Translate")

vim.defer_fn(function()
  dump("ACP_WORD")
  -- 可视选区整行 → 句子路径（会话复用第二次请求）
  vim.cmd("vmap <buffer> <leader>t <cmd>Translate<cr>")
  vim.cmd("call feedkeys('ggVG\\\\t', 'xt')")
  vim.defer_fn(function()
    dump("ACP_SENT")
    vim.cmd("qa!")
  end, 3000)
end, 3000)
