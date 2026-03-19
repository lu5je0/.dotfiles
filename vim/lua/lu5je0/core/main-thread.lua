-- main.nvim_get_mode total=0.335ms avg=0.335us last_mode=n
-- main-thread.nvim_get_mode total=37.508ms avg=37.508us last_mode=n

-- local mt = require('lu5je0.core.main-thread')
-- mt.new_thread(function()
--   local mt = require('lu5je0.core.main-thread')
--   local vim = mt.vim
-- end)

local M = {}

local uv = vim.uv
local unpack = table.unpack or unpack

local thread_server_address

local function close_handle(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function normalize_lua_chunk(expr)
  if expr:match("^%s*return[%s;%(]") then
    return expr
  end

  return "return " .. expr
end

local function make_callable_expr(path)
  return ("%s(...)"):format(path)
end

local function ensure_server_address()
  if vim.is_thread() then
    if not thread_server_address or thread_server_address == "" then
      error("main-thread is not attached to a main-thread RPC address")
    end

    return thread_server_address
  end

  if vim.v.servername ~= "" then
    return vim.v.servername
  end

  local ok, address = pcall(vim.fn.serverstart)
  if ok and address and address ~= "" then
    return address
  end

  local fallback = ("%s/nvim-main-thread-%d.sock"):format(uv.os_tmpdir(), vim.fn.getpid())
  ok, address = pcall(vim.fn.serverstart, fallback)
  if not ok or not address or address == "" then
    error("failed to create Neovim RPC server")
  end

  return address
end

local function is_tcp_address(address)
  if address:match("^\\\\%.\\pipe\\") then
    return false
  end

  if address:find("/") then
    return false
  end

  return address:match("^.+:%d+$") ~= nil
end

local function connect(address, callback)
  if is_tcp_address(address) then
    local host, port = address:match("^(.-):(%d+)$")
    local client = uv.new_tcp()
    client:connect(host, tonumber(port), function(err)
      callback(err, client)
    end)
    return client
  end

  local client = uv.new_pipe(false)
  client:connect(address, function(err)
    callback(err, client)
  end)
  return client
end

local function rpc_request(address, method, params)
  local response
  local response_error
  local done = false
  local read_buffer = ""
  local unpacker = vim.mpack.Unpacker()
  local msgid = 1

  local client

  local function finish(result, err)
    if done then
      return
    end

    done = true
    response = result
    response_error = err

    if client and client.read_stop then
      pcall(client.read_stop, client)
    end
    close_handle(client)
  end

  client = connect(address, function(err, connected_client)
    if err then
      finish(nil, err)
      return
    end

    connected_client:read_start(function(read_err, chunk)
      if read_err then
        finish(nil, read_err)
        return
      end

      if not chunk then
        finish(nil, "connection closed before RPC response")
        return
      end

      read_buffer = read_buffer .. chunk

      local offset = 1
      while offset <= #read_buffer do
        local message, next_offset = unpacker(read_buffer, offset)
        if message == nil then
          break
        end

        offset = next_offset

        if message[1] == 1 and message[2] == msgid then
          if message[3] ~= nil and message[3] ~= vim.NIL then
            finish(nil, message[3])
          else
            finish(message[4], nil)
          end
          return
        end
      end

      if offset > 1 then
        read_buffer = read_buffer:sub(offset)
      end
    end)

    connected_client:write(vim.mpack.encode({ 0, msgid, method, params }), function(write_err)
      if write_err then
        finish(nil, write_err)
      end
    end)
  end)

  while not done do
    uv.run("once")
  end

  if response_error ~= nil then
    error(("main-thread RPC request failed: %s"):format(vim.inspect(response_error)))
  end

  return response
end

function M.attach(address)
  thread_server_address = address
end

function M.get_server_address()
  return ensure_server_address()
end

local function normalize_call_args(...)
  local argc = select("#", ...)
  if argc == 0 then
    return {}
  end

  local first = select(1, ...)
  if argc == 1 and type(first) == "table" then
    return first
  end

  return { ... }
end

function M.call(expr, ...)
  local args = normalize_call_args(...)

  local chunk = normalize_lua_chunk(expr)
  if not vim.is_thread() then
    local fn, err = load(chunk, "=(main-thread)", "t", _G)
    if not fn then
      error(err)
    end

    return fn(unpack(args))
  end

  return rpc_request(ensure_server_address(), "nvim_exec_lua", { chunk, args })
end

function M.call_path(path, ...)
  return M.call(make_callable_expr(path), ...)
end

local function make_proxy(path)
  return setmetatable({}, {
    __index = function(_, key)
      return make_proxy(("%s.%s"):format(path, key))
    end,
    __call = function(_, ...)
      return M.call_path(path, ...)
    end,
  })
end

M.api = make_proxy("vim.api")
M.fn = make_proxy("vim.fn")
M.treesitter = make_proxy("vim.treesitter")
M.vim = make_proxy("vim")

function M.new_thread(entry, ...)
  local address = ensure_server_address()
  local dumped_entry
  local package_path = package.path
  local package_cpath = package.cpath

  if type(entry) == "function" then
    dumped_entry = string.dump(entry, true)
  elseif type(entry) == "string" then
    dumped_entry = entry
  else
    error("main-thread.new_thread() expects a function or dumped Lua chunk string")
  end

  return uv.new_thread(function(server_address, entry_chunk, inherited_package_path, inherited_package_cpath, ...)
    if inherited_package_path and inherited_package_path ~= "" then
      package.path = inherited_package_path
    end
    if inherited_package_cpath and inherited_package_cpath ~= "" then
      package.cpath = inherited_package_cpath
    end

    local main_thread = require("lu5je0.core.main-thread")
    main_thread.attach(server_address)

    local loader = loadstring or load
    local loaded_entry, err = loader(entry_chunk)
    if not loaded_entry then
      error(err)
    end

    return loaded_entry(...)
  end, address, dumped_entry, package_path, package_cpath, ...)
end

return M
