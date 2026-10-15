-- vim-translator: ACP (Agent Client Protocol) 后端
-- vim-translator 作为 ACP client，通过 JSON-RPC（换行分隔）调用任意 ACP agent
-- （traecli / claude / gemini / opencode 等）完成翻译。
-- 两种接入方式（acp.mode）：
--   "connect"：连接已在后台运行的 ACP 服务（TCP 或 unix socket），纯 client
--   "spawn"  ：由插件自动拉起 agent 子进程（stdio），进程常驻复用会话
local config = require("vim-translator.config")
local uv = vim.uv or vim.loop

local M = {}

local proc = nil -- spawn 模式: vim.system 句柄
local sock = nil -- connect 模式: libuv tcp/pipe 句柄
local next_id = 1
local session_id = nil
local pending = {} -- 请求 id -> { cb = fn, timer = uv timer }
local waiters = {} -- 等待 agent 就绪的调用
local state = "idle" -- idle | starting | ready | dead(主动关闭)
local out_buf = "" -- 接收行缓冲
local stderr_buf = ""
local update_text = {} -- 当前 prompt 经 session/update 流式推送的文本块

---当前传输层是否可用
local function transport_ok()
  return (proc ~= nil) or (sock ~= nil)
end

---向 agent 写一条 JSON-RPC 请求
---@return integer|nil id
local function send(method, params, on_result)
  if not transport_ok() then
    if on_result then
      on_result(nil, "ACP 服务未连接")
    end
    return nil
  end
  local id = next_id
  next_id = next_id + 1
  if on_result then
    pending[id] = { cb = on_result }
  end
  local ok, encoded = pcall(vim.json.encode, { jsonrpc = "2.0", id = id, method = method, params = params })
  if not ok then
    pending[id] = nil
    if on_result then
      on_result(nil, "ACP 请求编码失败")
    end
    return nil
  end
  if proc then
    proc:write(encoded .. "\n")
  elseif sock then
    sock:write(encoded .. "\n")
  end
  return id
end

local function fail_pending(err)
  local olds = pending
  pending = {}
  for _, entry in pairs(olds) do
    if entry.timer then
      entry.timer:stop()
      entry.timer:close()
    end
    entry.cb(nil, err)
  end
end

local function flush_waiters(err)
  local ws = waiters
  waiters = {}
  for _, cb in ipairs(ws) do
    cb(err)
  end
end

---agent 异常死亡 / 连接断开 / 握手失败：清理状态并通知所有等待方
local function die(err)
  local p = proc
  local s = sock
  proc = nil
  sock = nil
  session_id = nil
  state = "idle"
  if p then
    pcall(function()
      p:kill()
    end)
  end
  if s then
    pcall(function()
      s:close()
    end)
  end
  flush_waiters(err)
  fail_pending(err)
end

---处理 agent stdout 的一行 JSON-RPC 消息
local function handle_line(line)
  local ok, msg = pcall(vim.json.decode, line)
  if not ok or type(msg) ~= "table" then
    return
  end
  -- 流式通知：session/update 的 agent_message_chunk 逐块累积
  -- （traecli 等把全部文本经 update 推送，prompt 响应的 content 为空）
  -- 注意：字段在 params.update 下（非顶层），content 可为单对象或数组
  if msg.method == "session/update" and type(msg.params) == "table" then
    local p = msg.params
    local u = p.update or p -- 兼容两种放置方式
    if p.sessionId == session_id and u.sessionUpdate == "agent_message_chunk" then
      local contents = {}
      if type(u.content) == "table" and u.content.type ~= nil then
        contents = { u.content }
      elseif type(u.content) == "table" then
        contents = u.content
      end
      for _, c in ipairs(contents) do
        if type(c) == "table" and c.type == "text" and c.text then
          table.insert(update_text, c.text)
        end
      end
    end
    return
  end
  if msg.id ~= nil and pending[msg.id] then
    local entry = pending[msg.id]
    pending[msg.id] = nil
    if entry.timer then
      entry.timer:stop()
      entry.timer:close()
    end
    vim.schedule(function()
      if msg.error then
        entry.cb(nil, ("ACP 错误(%s)：%s"):format(msg.error.code or "?", msg.error.message or "?"))
      else
        entry.cb(msg.result, nil)
      end
    end)
  end
  -- session/update 等通知：忽略（浮窗已有 loading 提示）
end

---接收流式回调：按行切分（ACP 为换行分隔的 JSON-RPC）
local function on_data(_, data)
  if not data then
    return
  end
  out_buf = out_buf .. data
  while true do
    local nl = out_buf:find("\n", 1, true)
    if not nl then
      break
    end
    local line = out_buf:sub(1, nl - 1)
    out_buf = out_buf:sub(nl + 1)
    if line:match("%S") then
      handle_line(line)
    end
  end
end

---握手：initialize + session/new（connect/spawn 共用）
local function handshake(on_die)
  send("initialize", {
    protocolVersion = 1,
    clientCapabilities = {},
    clientInfo = { name = "vim-translator", version = "0.1.0" },
  }, function(result, err)
    if err or type(result) ~= "table" then
      return on_die("ACP initialize 失败：" .. tostring(err))
    end
    send("session/new", {
      cwd = vim.fn.getcwd(),
      mcpServers = vim.empty_dict(),
    }, function(result2, err2)
      if err2 or type(result2) ~= "table" or not result2.sessionId then
        return on_die("ACP session/new 失败：" .. tostring(err2))
      end
      session_id = result2.sessionId
      state = "ready"
      flush_waiters(nil)
    end)
  end)
end

---spawn 模式：拉起 agent 子进程（stdio）
local function start_spawn()
  local acp = config.opts.acp
  if acp.command == "" or not vim.fn.executable(acp.command) then
    return flush_waiters("vim-translator: acp.command 不可执行: " .. acp.command)
  end
  local cmd = { acp.command }
  vim.list_extend(cmd, acp.args or {})
  proc = vim.system(cmd, {
    text = true,
    stdin = true, -- 保持 stdin 打开，后续持续写请求
    env = vim.tbl_extend("force", vim.fn.environ(), acp.env or {}),
    stdout = on_data,
    stderr = function(_, data)
      if data then
        stderr_buf = stderr_buf .. data
      end
    end,
  }, function(obj)
    vim.schedule(function()
      local err_tail = stderr_buf
      stderr_buf = ""
      if state ~= "dead" then
        die(("ACP agent 退出（exit %d）：%s"):format(obj.code, err_tail:sub(1, 200)))
      else
        state = "idle"
        proc = nil
        session_id = nil
      end
    end)
  end)
  handshake(function(err)
    die(err)
  end)
end

---connect 模式：连接后台 ACP 服务（TCP 或 unix socket），插件纯 client
local function start_connect()
  local acp = config.opts.acp
  local is_unix = acp.socket ~= nil and acp.socket ~= ""
  if not is_unix and not acp.port then
    return flush_waiters("vim-translator: connect 模式需配置 acp.port（TCP）或 acp.socket（unix）")
  end

  -- libuv 回调运行在 fast 上下文，API 调用需经 schedule
  local on_connect = vim.schedule_wrap(function(err)
    if err then
      return die(("ACP 连接失败: %s（服务是否已启动？）"):format(tostring(err)))
    end
    sock:read_start(vim.schedule_wrap(function(rerr, data)
      if rerr then
        return die("ACP 读错误: " .. tostring(rerr))
      end
      if data == nil then
        -- 服务端关闭连接
        return die("ACP 服务关闭了连接（服务是否退出？）")
      end
      on_data(nil, data)
    end))
    handshake(function(err2)
      die(err2)
    end)
  end)

  if is_unix then
    sock = uv.new_pipe()
    sock:connect(acp.socket, on_connect)
  else
    sock = uv.new_tcp()
    sock:connect(acp.host or "127.0.0.1", acp.port, on_connect)
  end
end

---启动（按 mode 分发）并完成握手
local function start()
  if config.opts.acp.mode == "connect" then
    return start_connect()
  end
  return start_spawn()
end

---确保 agent 已就绪（幂等；并发调用会排队）
local function ensure_ready(on_ready)
  if state == "ready" then
    return on_ready(nil)
  end
  table.insert(waiters, on_ready)
  if state == "starting" then
    return
  end
  state = "starting"
  start()
end

---翻译入口：prompt_text 为完整指令 + 原文（api.lua 组装）
---@param prompt_text string
---@param on_done function(result|nil, err|nil)
function M.translate(prompt_text, on_done)
  ensure_ready(function(err)
    if err then
      return on_done(nil, err)
    end
    -- 单飞：取消在途的 session/prompt
    if M.prompt_in_flight and pending[M.prompt_in_flight] then
      send("session/cancel", {
        sessionId = session_id,
        promptId = M.prompt_in_flight,
      })
    end

    local acp = config.opts.acp
    update_text = {} -- 新 prompt，重置流式累积
    local id = send("session/prompt", {
      sessionId = session_id,
      prompt = { { type = "text", text = prompt_text } },
    }, function(result, err)
      M.prompt_in_flight = nil
      if err then
        return on_done(nil, err)
      end
      -- 优先取 prompt 响应里的 text 内容块
      local parts = {}
      local content_blocks = result and result.content or {}
      if type(content_blocks) == "table" and content_blocks.type == nil then
        for _, block in ipairs(content_blocks) do
          if block.type == "text" and block.text and block.text ~= "" then
            table.insert(parts, block.text)
          end
        end
      elseif type(content_blocks) == "table" and content_blocks.type == "text" then
        table.insert(parts, content_blocks.text or "")
      end
      local content = table.concat(parts, "\n")
      if content == "" then
        -- 兼容只经 session/update 流式推送的 agent（如 traecli）
        content = table.concat(update_text, "")
      end
      if content == "" then
        local dbg = stderr_buf ~= "" and ("（stderr 尾部: " .. stderr_buf:sub(-200) .. "）") or ""
        return on_done(nil, "ACP agent 返回了空内容" .. dbg)
      end
      on_done(require("vim-translator.api").parse_content(content))
    end)
    if not id then
      return
    end
    M.prompt_in_flight = id

    -- 超时保护
    local timer = vim.loop.new_timer()
    pending[id].timer = timer
    timer:start(acp.timeout * 1000, 0, vim.schedule_wrap(function()
      if pending[id] then
        local entry = pending[id]
        pending[id] = nil
        M.prompt_in_flight = nil
        if entry.timer then
          entry.timer:close()
        end
        on_done(nil, ("ACP 翻译超时（%ds）"):format(acp.timeout))
      end
    end))
  end)
end

M.prompt_in_flight = nil

---退出前断开连接/关闭 agent（VimLeavePre 调用）
function M.shutdown()
  local p = proc
  local s = sock
  state = "dead"
  proc = nil
  sock = nil
  session_id = nil
  if p then
    pcall(function()
      p:kill()
    end)
  end
  if s then
    pcall(function()
      s:close()
    end)
  end
end

return M
