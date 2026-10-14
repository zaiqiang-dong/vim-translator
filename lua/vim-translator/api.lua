-- vim-translator: 请求组装、异步调用、响应解析
local config = require("vim-translator.config")

local M = {}

local WORD_PROMPT = [[你是一个中英双语词典引擎。只输出 JSON，不要 markdown 代码块。
用户输入英文单词时输出：
{"word":"原文","phonetic":"美式音标","defs":[{"pos":"词性","trans":"中文释义"}],"examples":[{"en":"英文例句","zh":"例句中文"}]}
用户输入中文词时：defs 的 trans 给出对应英文释义，phonetic 给拼音。]]

local SENTENCE_PROMPT = [[你是一个专业中英互译引擎。自动检测用户文本的语言：中文则译成英文，英文则译成中文。
只输出 JSON，不要 markdown 代码块：
{"source":"原文","source_lang":"zh或en","translation":"译文"}
要求：忠实原文、语句通顺、保留换行与段落结构、不加解释。]]

local job = nil -- 当前 in-flight 请求（单飞控制）
local seq = 0

---去掉模型偶尔输出的 markdown 代码块包裹
local function strip_code_fence(s)
  s = s:gsub("^%s*```[%w%-]*\n?", ""):gsub("```%s*$", "")
  return s
end

---构造请求体表
local function build_payload(text, is_word, with_json_mode)
  local system = is_word and WORD_PROMPT or SENTENCE_PROMPT
  local body = {
    model = config.opts.llm.model,
    temperature = config.opts.llm.temperature,
    messages = {
      { role = "system", content = system },
      { role = "user", content = text },
    },
  }
  if with_json_mode then
    body.response_format = { type = "json_object" }
  end
  for k, v in pairs(config.opts.llm.extra_body or {}) do
    body[k] = v
  end
  return body
end

---构造 curl 命令（请求体经临时文件传入，规避转义/注入）
local function build_cmd(tmpfile)
  local llm = config.opts.llm
  local url = llm.base_url:gsub("/+$", "") .. "/v1/chat/completions"
  local cmd = {
    "curl",
    "-sS",
    "--max-time",
    tostring(llm.timeout),
  }
  if llm.proxy ~= "" then
    table.insert(cmd, "-x")
    table.insert(cmd, llm.proxy)
  end
  vim.list_extend(cmd, {
    "-X",
    "POST",
    url,
    "-H",
    "Authorization: Bearer " .. config.api_key(),
    "-H",
    "Content-Type: application/json",
    "-d",
    "@" .. tmpfile,
  })
  return cmd
end

---解析响应 → 结果表（成功）或 nil, err（失败）
---@param stdout string curl 原始输出
---@param code integer curl exit code
---@return table|nil result {kind="word"|"sentence", data=...}
---@return string|nil err
local function parse_response(stdout, code)
  if code ~= 0 then
    if code == 124 or code == 28 then
      return nil, ("请求超时（curl exit %d）"):format(code)
    end
    return nil, ("curl 失败（exit %d）：%s"):format(code, stdout:sub(1, 200))
  end
  local ok, resp = pcall(vim.json.decode, stdout)
  if not ok or type(resp) ~= "table" then
    return nil, "响应不是合法 JSON：" .. stdout:sub(1, 200)
  end
  if resp.error then
    local msg = resp.error.message or vim.inspect(resp.error)
    return nil, "API 错误：" .. msg
  end
  local choice = resp.choices and resp.choices[1]
  local content = choice and choice.message and choice.message.content
  if not content or content == "" then
    return nil, "API 返回了空的 choices/message.content"
  end
  local ok2, data = pcall(vim.json.decode, strip_code_fence(content))
  if not ok2 or type(data) ~= "table" then
    -- 纯文本回退：整体作为 sentence.translation 展示
    return { kind = "plain", data = { translation = strip_code_fence(content) } }, nil
  end
  if data.translation or data.source then
    return { kind = "sentence", data = data }, nil
  end
  if data.word or data.defs then
    return { kind = "word", data = data }, nil
  end
  return { kind = "plain", data = { translation = strip_code_fence(content) } }, nil
end

---对外入口：翻译 text。自动判定单词/句子模式。
---@param text string 待翻译文本
---@param on_done function|nil 回调 on_done(result|nil, err|nil)；nil 时用 vim.notify
function M.translate(text, on_done)
  on_done = on_done or function(_, err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end

  local is_word = require("vim-translator.text").is_word(text)

  -- 单飞：取消旧请求
  if job then
    pcall(function()
      job:kill()
    end)
    job = nil
  end

  local use_json_mode = true
  seq = seq + 1
  local tmpfile = ("/tmp/vim_translator_%d_%d.json"):format(vim.fn.getpid(), seq)

  local function write_body(path, with_json_mode)
    local fh = io.open(path, "w")
    if not fh then
      return false
    end
    fh:write(vim.json.encode(build_payload(text, is_word, with_json_mode)))
    fh:close()
    return true
  end

  local function done(result, err)
    job = nil
    on_done(result, err)
  end

  if not write_body(tmpfile, use_json_mode) then
    on_done(nil, "无法写临时文件 " .. tmpfile)
    return
  end

  job = vim.system(build_cmd(tmpfile), { text = true }, function(obj)
    os.remove(tmpfile)
    vim.schedule(function()
      local result, err = parse_response(obj.stdout or "", obj.code)
      if err and use_json_mode and obj.code == 0 and result == nil then
        -- 服务可能不支持 response_format：去参重试一次（只重试一层）
        use_json_mode = false
        if write_body(tmpfile, false) then
          job = vim.system(build_cmd(tmpfile), { text = true }, function(obj2)
            os.remove(tmpfile)
            vim.schedule(function()
              local r2, e2 = parse_response(obj2.stdout or "", obj2.code)
              done(r2, e2)
            end)
          end)
          return
        end
      end
      done(result, err)
    end)
  end)
end

return M
