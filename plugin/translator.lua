-- vim-translator: 仅定义命令壳，回调里才 require 主模块（零启动开销 / lazy 友好）
local function lazy(kind)
  return function()
    require("vim-translator").dispatch(kind)
  end
end

vim.api.nvim_create_user_command("Translate", function()
  lazy("word")()
end, { desc = "翻译光标单词" })

vim.api.nvim_create_user_command("TranslateLine", function()
  lazy("line")()
end, { desc = "翻译当前行" })

vim.api.nvim_create_user_command("TranslateVisual", function()
  lazy("sentence")()
end, { range = true, desc = "翻译选中句子" })

vim.api.nvim_create_user_command("TranslateReplace", function()
  lazy("replace")()
end, { range = true, desc = "翻译并替换选中文本" })

vim.api.nvim_create_user_command("TranslateClose", function()
  lazy("close")()
end, { desc = "关闭翻译浮窗" })
