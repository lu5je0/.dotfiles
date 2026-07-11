-- Pure-Lua native Wayland clipboard for Neovim.
-- Speaks the Wayland wire protocol + zwlr_data_control_unstable_v1 directly over
-- the Wayland unix socket. Uses LuaJIT FFI only for libc syscalls that vim.uv
-- cannot express (socket/connect + SCM_RIGHTS fd passing via sendmsg/recvmsg);
-- the event loop is driven by vim.uv on Neovim's main loop. No external process
-- (wl-copy/wl-paste) and no compiled .so.
--
-- NOTE: struct msghdr/cmsghdr layout below is the Linux 64-bit ABI (x86_64/arm64).

local M = {}

local ffi = require('ffi')
local bit = require('bit')
local band, bor, bnot, lshift, rshift = bit.band, bit.bor, bit.bnot, bit.lshift, bit.rshift
local byte, char, rep, sub = string.byte, string.char, string.rep, string.sub

ffi.cdef([[
typedef long ssize_t;
typedef unsigned long __sz;

int socket(int domain, int type, int protocol);
int connect(int fd, const void *addr, unsigned int len);
int close(int fd);
int pipe(int fds[2]);
ssize_t write(int fd, const void *buf, __sz n);

struct sockaddr_un { unsigned short sun_family; char sun_path[108]; };

struct iovec { void *iov_base; __sz iov_len; };
struct msghdr {
  void *msg_name; unsigned int msg_namelen;
  struct iovec *msg_iov; __sz msg_iovlen;
  void *msg_control; __sz msg_controllen;
  int msg_flags;
};
struct cmsghdr { __sz cmsg_len; int cmsg_level; int cmsg_type; };

ssize_t sendmsg(int fd, const struct msghdr *msg, int flags);
ssize_t recvmsg(int fd, struct msghdr *msg, int flags);
]])

local C = ffi.C
local AF_UNIX, SOCK_STREAM = 1, 1
local SOL_SOCKET, SCM_RIGHTS = 1, 1
local MSG_DONTWAIT = 0x40
-- x86_64/arm64: sizeof(struct cmsghdr)=16, CMSG_ALIGN(16)=16, CMSG_LEN(4)=20
local CMSG_HDR = 16
local CMSG_LEN_1 = 20
local CMSG_SPACE_1 = 24

-- ── little-endian packing (Wayland uses host byte order; LE on x86_64/arm64) ──
local function p32(v)
  return char(band(v, 0xff), band(rshift(v, 8), 0xff), band(rshift(v, 16), 0xff), band(rshift(v, 24), 0xff))
end
local function u32(s, o)
  return byte(s, o) + byte(s, o + 1) * 256 + byte(s, o + 2) * 65536 + byte(s, o + 3) * 16777216
end
local function pad(n) return (4 - n % 4) % 4 end

-- string argument: uint32 length (incl NUL) + bytes + NUL + pad-to-4
local function wstr(s)
  local raw = s .. '\0'
  return p32(#raw) .. raw .. rep('\0', pad(#raw))
end
-- read a string arg from body at 1-based cursor c; returns text, next_cursor
local function rstr(b, c)
  local len = u32(b, c)
  local text = sub(b, c + 4, c + 4 + len - 2) -- drop trailing NUL
  return text, c + 4 + len + pad(len)
end

-- ── protocol constants ──
local WL_DISPLAY = 1
local MIMES = { 'text/plain;charset=utf-8', 'text/plain', 'UTF8_STRING', 'STRING', 'TEXT' }
local PREF = { 'text/plain;charset=utf-8', 'UTF8_STRING', 'text/plain', 'STRING', 'TEXT' }

-- ── state ──
local sockfd
local ready = false
local next_id = 2
local objects = {}   -- [id] = interface_name
local globals = {}   -- [interface] = { name=, version= }
local sync_done = {}
local offers = {}    -- [offer_id] = { mimes = { [mime]=true } }
local sources = {}   -- [source_id] = { text=, regtype= }
local owned = {}     -- ['clipboard'|'primary'] = { src=, text=, regtype= }
local fd_queue = {}
local inbuf = ''
local poll_handle

local registry_id, seat_id, manager_id, device_id
local current_offer, current_primary
local have_primary = false

local function alloc()
  local id = next_id
  next_id = next_id + 1
  return id
end

-- ── raw socket I/O (FFI) ──
local function sock_write(bytes)
  local n = #bytes
  local buf = ffi.new('char[?]', n)
  ffi.copy(buf, bytes, n)
  local off = 0
  while off < n do
    local w = tonumber(C.write(sockfd, buf + off, n - off))
    if w <= 0 then break end
    off = off + w
  end
end

-- send a request without fds
local function req(obj, opcode, body)
  local size = 8 + #body
  sock_write(p32(obj) .. p32(bor(lshift(size, 16), opcode)) .. body)
end

-- send a request carrying exactly one fd via SCM_RIGHTS
local function req_fd(obj, opcode, body, fd)
  local msgbytes = p32(obj) .. p32(bor(lshift(8 + #body, 16), opcode)) .. body
  local dbuf = ffi.new('char[?]', #msgbytes)
  ffi.copy(dbuf, msgbytes, #msgbytes)

  local iov = ffi.new('struct iovec[1]')
  iov[0].iov_base = dbuf
  iov[0].iov_len = #msgbytes

  local ctrl = ffi.new('char[?]', CMSG_SPACE_1)
  local cmsg = ffi.cast('struct cmsghdr*', ctrl)
  cmsg.cmsg_len = CMSG_LEN_1
  cmsg.cmsg_level = SOL_SOCKET
  cmsg.cmsg_type = SCM_RIGHTS
  ffi.cast('int*', ctrl + CMSG_HDR)[0] = fd

  local mh = ffi.new('struct msghdr')
  mh.msg_iov = iov
  mh.msg_iovlen = 1
  mh.msg_control = ctrl
  mh.msg_controllen = CMSG_LEN_1
  C.sendmsg(sockfd, mh, 0)
end

-- ── requests ──
local function bind(interface, version)
  local g = globals[interface]
  if not g then return nil end
  local id = alloc()
  objects[id] = interface
  local v = math.min(g.version, version)
  req(registry_id, 0, p32(g.name) .. wstr(interface) .. p32(v) .. p32(id))
  return id, v
end

local function roundtrip()
  local cb = alloc()
  objects[cb] = 'wl_callback'
  sync_done[cb] = false
  req(WL_DISPLAY, 0, p32(cb)) -- wl_display.sync
  vim.wait(2000, function() return sync_done[cb] end, 2)
  objects[cb] = nil
  sync_done[cb] = nil
end

-- ── inbound handling ──
local function on_source_send(src, body)
  local fd = table.remove(fd_queue, 1)
  if not fd then return end
  local entry = sources[src]
  local text = entry and entry.text or ''
  local n = #text
  if n > 0 then
    local buf = ffi.new('char[?]', n)
    ffi.copy(buf, text, n)
    local off = 0
    while off < n do
      local w = tonumber(C.write(fd, buf + off, n - off))
      if w <= 0 then break end
      off = off + w
    end
  end
  C.close(fd)
end

local function on_source_cancelled(src)
  req(src, 1, '') -- destroy
  objects[src] = nil
  sources[src] = nil
  if owned.clipboard and owned.clipboard.src == src then owned.clipboard = nil end
  if owned.primary and owned.primary.src == src then owned.primary = nil end
end

local function destroy_offer(id)
  if id and objects[id] == 'zwlr_data_control_offer_v1' then
    req(id, 1, '') -- destroy
    objects[id] = nil
    offers[id] = nil
  end
end

local function handle(obj, opcode, body)
  if obj == WL_DISPLAY then
    if opcode == 1 then
      objects[u32(body, 1)] = nil -- delete_id
    end
    return
  end

  local iface = objects[obj]
  if iface == 'wl_registry' then
    if opcode == 0 then
      local name = u32(body, 1)
      local ifs, c = rstr(body, 5)
      globals[ifs] = { name = name, version = u32(body, c) }
    end
  elseif iface == 'wl_callback' then
    if opcode == 0 then sync_done[obj] = true end
  elseif iface == 'zwlr_data_control_device_v1' then
    if opcode == 0 then -- data_offer(new_id)
      local id = u32(body, 1)
      offers[id] = { mimes = {} }
      objects[id] = 'zwlr_data_control_offer_v1'
    elseif opcode == 1 then -- selection(offer)
      local id = u32(body, 1)
      local prev = current_offer
      current_offer = (id ~= 0) and id or nil
      if prev and prev ~= current_offer then destroy_offer(prev) end
    elseif opcode == 3 then -- primary_selection(offer)
      local id = u32(body, 1)
      local prev = current_primary
      current_primary = (id ~= 0) and id or nil
      if prev and prev ~= current_primary then destroy_offer(prev) end
    end
  elseif iface == 'zwlr_data_control_offer_v1' then
    if opcode == 0 then -- offer(mime)
      local mime = rstr(body, 1)
      if offers[obj] then offers[obj].mimes[mime] = true end
    end
  elseif iface == 'zwlr_data_control_source_v1' then
    if opcode == 0 then
      on_source_send(obj, body)
    elseif opcode == 1 then
      on_source_cancelled(obj)
    end
  end
end

local function parse_messages()
  while #inbuf >= 8 do
    local obj = u32(inbuf, 1)
    local word2 = u32(inbuf, 5)
    local size = rshift(word2, 16)
    local opcode = band(word2, 0xffff)
    if size < 8 or #inbuf < size then break end
    handle(obj, opcode, sub(inbuf, 9, size))
    inbuf = sub(inbuf, size + 1)
  end
end

-- ── recvmsg draining (captures data bytes + SCM_RIGHTS fds) ──
local RECV_N = 65536
local recv_data = ffi.new('char[?]', RECV_N)
local recv_ctrl = ffi.new('char[?]', 256)
local recv_iov = ffi.new('struct iovec[1]')
local recv_mh = ffi.new('struct msghdr')

local function drain()
  while true do
    recv_iov[0].iov_base = recv_data
    recv_iov[0].iov_len = RECV_N
    recv_mh.msg_name = nil
    recv_mh.msg_namelen = 0
    recv_mh.msg_iov = recv_iov
    recv_mh.msg_iovlen = 1
    recv_mh.msg_control = recv_ctrl
    recv_mh.msg_controllen = 256
    recv_mh.msg_flags = 0

    local n = tonumber(C.recvmsg(sockfd, recv_mh, MSG_DONTWAIT))
    if n <= 0 then break end

    local clen = tonumber(recv_mh.msg_controllen)
    local off = 0
    while off + CMSG_HDR <= clen do
      local cmsg = ffi.cast('struct cmsghdr*', recv_ctrl + off)
      local cl = tonumber(cmsg.cmsg_len)
      if cl < CMSG_HDR then break end
      if cmsg.cmsg_level == SOL_SOCKET and cmsg.cmsg_type == SCM_RIGHTS then
        local fdcount = math.floor((cl - CMSG_HDR) / 4)
        local fdp = ffi.cast('int*', recv_ctrl + off + CMSG_HDR)
        for i = 0, fdcount - 1 do
          fd_queue[#fd_queue + 1] = fdp[i]
        end
      end
      off = off + band(cl + 7, bnot(7))
    end

    inbuf = inbuf .. ffi.string(recv_data, n)
    parse_messages()
  end
end

-- ── connection ──
local function socket_path()
  local wd = os.getenv('WAYLAND_DISPLAY') or 'wayland-0'
  if wd:sub(1, 1) == '/' then return wd end
  local runtime = os.getenv('XDG_RUNTIME_DIR')
  if not runtime or runtime == '' then error('XDG_RUNTIME_DIR unset') end
  return runtime .. '/' .. wd
end

local function connect()
  local path = socket_path()
  if #path >= 108 then error('wayland socket path too long') end
  sockfd = C.socket(AF_UNIX, SOCK_STREAM, 0)
  if sockfd < 0 then error('socket() failed') end

  local addr = ffi.new('struct sockaddr_un')
  addr.sun_family = AF_UNIX
  ffi.copy(addr.sun_path, path)
  if C.connect(sockfd, ffi.cast('void*', addr), ffi.sizeof('struct sockaddr_un')) ~= 0 then
    C.close(sockfd)
    error('connect() failed: ' .. path)
  end

  registry_id = alloc()
  objects[registry_id] = 'wl_registry'
  req(WL_DISPLAY, 1, p32(registry_id)) -- wl_display.get_registry

  poll_handle = vim.uv.new_poll(sockfd)
  poll_handle:start('r', function(err)
    if err then return end
    drain()
  end)
end

local function ensure()
  if ready then return end
  connect()
  roundtrip() -- collect globals

  if not globals['zwlr_data_control_manager_v1'] then
    error('compositor lacks zwlr_data_control_manager_v1')
  end
  seat_id = bind('wl_seat', 1)
  local mv
  manager_id, mv = bind('zwlr_data_control_manager_v1', 2)
  have_primary = (mv or 1) >= 2
  if not (seat_id and manager_id) then error('bind failed') end
  roundtrip()

  device_id = alloc()
  objects[device_id] = 'zwlr_data_control_device_v1'
  req(manager_id, 1, p32(device_id) .. p32(seat_id)) -- get_data_device
  roundtrip() -- receive initial data_offer/selection

  ready = true
end

-- ── public API ──
local function set(is_primary, lines, regtype)
  ensure()
  local text = table.concat(lines, '\n')
  local key = is_primary and 'primary' or 'clipboard'

  local src = alloc()
  objects[src] = 'zwlr_data_control_source_v1'
  sources[src] = { text = text, regtype = regtype or '' }
  req(manager_id, 0, p32(src)) -- create_data_source
  for _, m in ipairs(MIMES) do
    req(src, 0, wstr(m)) -- source.offer
  end
  if is_primary and have_primary then
    req(device_id, 2, p32(src)) -- set_primary_selection
  else
    req(device_id, 0, p32(src)) -- set_selection
  end
  owned[key] = { src = src, text = text, regtype = regtype or '' }
  roundtrip()
end

local function pick_mime(id)
  local o = offers[id]
  if not o then return nil end
  for _, m in ipairs(PREF) do
    if o.mimes[m] then return m end
  end
  for m in pairs(o.mimes) do return m end
  return nil
end

local function receive(offer_id, mime)
  local fds = ffi.new('int[2]')
  if C.pipe(fds) ~= 0 then return '' end
  local rfd, wfd = fds[0], fds[1]

  req_fd(offer_id, 0, wstr(mime), wfd) -- offer.receive(mime, fd)
  C.close(wfd)

  local chunks, done = {}, false
  local rp = vim.uv.new_pipe(false)
  rp:open(rfd)
  rp:read_start(function(err, data)
    if err or data == nil then
      done = true
      rp:read_stop()
      if not rp:is_closing() then rp:close() end
      return
    end
    chunks[#chunks + 1] = data
  end)
  vim.wait(2000, function() return done end, 2)
  if not done then
    pcall(function()
      rp:read_stop()
      if not rp:is_closing() then rp:close() end
    end)
  end
  return table.concat(chunks)
end

local function read(is_primary)
  ensure()
  roundtrip()
  local key = is_primary and 'primary' or 'clipboard'
  local own = owned[key]
  if own and own.src and sources[own.src] then
    return { vim.split(own.text, '\n'), own.regtype }
  end

  local cur = is_primary and current_primary or current_offer
  if not cur then return { { '' }, '' } end
  local mime = pick_mime(cur)
  if not mime then return { { '' }, '' } end
  return { vim.split(receive(cur, mime), '\n'), '' }
end

function M.setup()
  ensure()

  vim.o.clipboard = 'unnamedplus'
  vim.g.clipboard = {
    name = 'nvim-wayland',
    copy = {
      ['+'] = function(lines, regtype) set(false, lines, regtype) end,
      ['*'] = function(lines, regtype) set(true, lines, regtype) end,
    },
    paste = {
      ['+'] = function() return read(false) end,
      ['*'] = function() return read(true) end,
    },
  }
end

return M
