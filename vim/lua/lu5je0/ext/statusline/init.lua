local M = {}

local config = require('lu5je0.ext.statusline.config')

local highlight_cache = {}

function M.get_highlight(color)
  if type(color) == "string" then
    return string.format("%%#%s#", color)
  elseif type(color) == "table" then
    local fg = color.fg or "NONE"
    local bg = color.bg or config.colors.bg
    local hl_group = string.format("StatusLineCustom_%s_%s_%s", fg:sub(2), bg:sub(2), color.bold and "bold" or "NONE")

    if not highlight_cache[hl_group] then
      vim.api.nvim_set_hl(0, hl_group, { fg = fg, bg = bg, bold = color.bold })
      highlight_cache[hl_group] = true
    end

    return string.format("%%#%s#", hl_group)
  end
  return "%#StatusLine#"
end

local function create_cached_component(component)
  local cached = setmetatable({}, {
    __index = function(self, buf_id)
      self[buf_id] = {
        last_update = 0,
        value = nil
      }
      return self[buf_id]
    end
  })

  local ttl = component.cache_ttl or 1000
  local func = component[1]

  return setmetatable({}, {
    __call = function(_, args)
      local buf_id = args.buf_id
      local cache = cached[buf_id]
      local current_time = vim.loop.now()
      if current_time - cache.last_update > ttl then
        cache.value = func(args)
        cache.last_update = current_time
      end
      return cache.value
    end,
    __index = {
      cache_evict_autocmd = function(_, buf_id)
        if cached[buf_id] then
          cached[buf_id] = nil
        end
      end
    }
  })
end

local function prepare_component(component)
  if component.cache or component.cache_ttl then
    component[1] = create_cached_component(component)
    component.cache_evict_autocmd = component.cache_evict_autocmd or {}
    table.insert(component.cache_evict_autocmd, "BufWinLeave")
    vim.api.nvim_create_autocmd(component.cache_evict_autocmd, {
      callback = function()
        local buf_id = vim.api.nvim_get_current_buf()
        component[1]:cache_evict_autocmd(buf_id)
      end
    })
  end
end

local function match_rule(rule, filetype, buftype)
  local match = rule.match
  if match.filetype and match.filetype ~= filetype then
    return false
  end
  if match.buftype and match.buftype ~= buftype then
    return false
  end
  return true
end

local function process_components(components, args, focus_win_id, focus_win_is_floating, side)
  local default_padding_left = side == 'left' and 1 or 0
  local default_padding_right = side == 'right' and 1 or 0
  local parts = {}
  for _, component in ipairs(components) do
    if component.cond and not component.cond(args) then
      goto continue
    end
    if not focus_win_is_floating and component.inactive == false and args.win_id ~= focus_win_id then
      goto continue
    end

    local text
    if type(component[1]) == 'string' then
      text = component[1]
    else
      text = component[1](args)
    end
    if text and text ~= "" then
      local highlight = M.get_highlight(component.color)
      local padding_left = component.padding and component.padding.left or default_padding_left
      local padding_right = component.padding and component.padding.right or default_padding_right
      table.insert(parts,
        string.format("%s%s%s%s", highlight, string.rep(" ", padding_left), text, string.rep(" ", padding_right)))
    end
    ::continue::
  end
  return parts
end

local function resolve_components(component_refs)
  local result = {}
  for _, ref in ipairs(component_refs) do
    if type(ref) == 'string' then
      ref = { name = ref }
    end
    local component = config.components[ref.name]
    if component then
      local resolved = component
      for k, v in pairs(ref) do
        if k ~= 'name' then
          resolved = vim.tbl_extend('force', component, ref)
          resolved.name = nil
          break
        end
      end
      table.insert(result, resolved)
    end
  end
  return result
end

local function create_statusline_timer(mills)
  local timer = vim.loop.new_timer()
  timer:start(0, mills, vim.schedule_wrap(function()
    vim.cmd.redrawstatus()
  end))
  return timer
end

function M.register_component(name, component)
  config.components[name] = component
  prepare_component(component)
end

function M.append_config(rule)
  local pos = #config.statusline_config
  table.insert(config.statusline_config, pos, rule)
end

M.setup = function()
  vim.api.nvim_set_hl(0, 'StatusLineGrey', { fg = '#cccccc', bg = '#212328', bold = false })
  vim.api.nvim_set_hl(0, 'StatusLineViolet', { fg = config.colors.violet, bg = '#212328', bold = false })

  for _, component in pairs(config.components) do
    prepare_component(component)
  end

  M.statusline = function()
    local win_id = vim.g.statusline_winid
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local focus_win_id = vim.api.nvim_get_current_win()
    local focus_win_is_floating = vim.api.nvim_win_get_config(focus_win_id).relative ~= ''
    local filename = vim.fs.basename(vim.api.nvim_buf_get_name(buf_id))
    local filetype = vim.bo[buf_id].filetype
    local buftype = vim.bo[buf_id].buftype

    local args = { win_id = win_id, buf_id = buf_id, filename = filename, filetype = filetype }

    for _, rule in ipairs(config.statusline_config) do
      if match_rule(rule, filetype, buftype) then
        local left_components = resolve_components(rule.left or {})
        local right_components = resolve_components(rule.right or {})

        local left_parts = process_components(left_components, args, focus_win_id, focus_win_is_floating, 'left')
        local right_parts = process_components(right_components, args, focus_win_id, focus_win_is_floating, 'right')

        return table.concat({ table.concat(left_parts, ''), "%=", table.concat(right_parts, '') })
      end
    end

    return ''
  end

  _G.__my_status_line = function()
    return M.statusline()
  end

  vim.o.statusline = '%!v:lua._G.__my_status_line()'

  _G.__tabpage_click = function(tabnr, _clicks, button, _mods)
    if button == 'l' then
      vim.cmd('tabnext ' .. tabnr)
    end
  end

  create_statusline_timer(300)

  vim.api.nvim_create_user_command("StatusLineBenchmark", function()
    vim.g.statusline_winid = vim.api.nvim_get_current_win()
    local timer = require('lu5je0.lang.timer')
    timer.measure_fn(M.statusline, 80000)
  end, {})
end

return M
