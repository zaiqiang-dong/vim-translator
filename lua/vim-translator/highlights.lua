-- vim-translator: 高亮组定义
-- 每字段一个命名组 VTxxx；setup 时按用户配置 :highlight，不覆盖用户手动 :hi
local config = require("vim-translator.config")

local M = {}

-- 字段 → 高亮组名（VT = vim-translator）
M.groups = {
  title = "VTTitle",
  phonetic = "VTPhonetic",
  pos = "VTPos",
  trans = "VTTrans",
  example = "VTExample",
  example_trans = "VTExampleTrans",
  error = "VTError",
  loading = "VTLoading",
}

-- 用户没配某字段颜色时，link 到主题常见组
local fallback_link = {
  title = "Title",
  phonetic = "String",
  pos = "Statement",
  trans = "Normal",
  example = "Comment",
  example_trans = "Special",
  error = "ErrorMsg",
  loading = "Comment",
}

function M.setup()
  local user = config.opts.highlights or {}
  for field, group in pairs(M.groups) do
    local spec = user[field]
    if type(spec) == "table" and next(spec) ~= nil then
      vim.api.nvim_set_hl(0, group, spec)
    else
      vim.api.nvim_set_hl(0, group, { link = fallback_link[field] or "Normal", default = true })
    end
  end
end

return M
