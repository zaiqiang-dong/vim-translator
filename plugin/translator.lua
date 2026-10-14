-- vim-translator: 仅定义命令壳，回调里才 require 主模块（零启动开销 / lazy 友好）
-- 单一命令 :Translate：
--   visual 模式下 → 翻译选中文本
--   normal 模式下 → 翻译光标单词
-- 浮窗打开后按任意键自动关闭，无需专用关闭命令
local function lazy(kind)
  return function()
    require("vim-translator").dispatch(kind)
  end
end

vim.api.nvim_create_user_command("Translate", lazy("translate"), { desc = "翻译光标单词/选中文本" })
