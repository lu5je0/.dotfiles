local M = {}

local REMEMBER_LAST_SEARCH_PICKER_TYPES = { "grep" }

M.get_last_search_keyword = function(key)
  if M.last_search then
    return M.last_search[key]
  end
  return nil
end

local function get_picker_type()
  local p = (Snacks.picker.get() or {})[1]
  local picker_type = p and p.opts.source
  local res = picker_type or M.last_picker_type
  M.last_picker_type = picker_type
  if vim.tbl_contains(REMEMBER_LAST_SEARCH_PICKER_TYPES, res) then
    return res
  end
  return nil
end

local function remember_last_search()
  local group = vim.api.nvim_create_augroup('snacks-custom', { clear = true })

  M.snacks_last_search = ''
  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      if M.disable_keep_last_search then
        return
      end

      if vim.o.buftype == 'prompt' and vim.bo.filetype == 'snacks_picker_input' then
        if not M.last_search then
          M.last_search = {}
        end
        local picker_type = get_picker_type()
        if picker_type then
          M.last_search[picker_type] = string.sub(vim.api.nvim_get_current_line(), 0, -1)
        end
      end
    end
  })

  local wrap_mapping = function(mode, lhs, mapping_opts)
    local close_mapping_callback = require('lu5je0.core.keys').get_rhs_callback(mode, lhs, {
      buffer = 0
    })
    if close_mapping_callback then
      vim.keymap.set({ 's', 'v' }, lhs, function()
        if vim.api.nvim_get_mode().mode ~= 'n' then
          require('lu5je0.core.keys').feedkey("<esc>", 'n')
        end
        close_mapping_callback()
      end, mapping_opts)
    end
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'snacks_picker_input' },
    callback = function()
      local opts = { noremap = true, silent = true, buffer = true, desc = 'snacks-custom', nowait = true }

      vim.defer_fn(function()
        wrap_mapping('i', '<Esc>', opts)
        wrap_mapping('i', '<C-P>', opts)
        wrap_mapping('i', '<C-D>', opts)
        wrap_mapping('i', '<C-Q>', opts)
        wrap_mapping('i', '<Up>', opts)
        wrap_mapping('i', '<Down>', opts)
        vim.keymap.set({ 's' }, "<bs>", function()
          require('lu5je0.core.keys').feedkey('<bs>i', 'n')
        end)
      end, 0)

      vim.defer_fn(function()
        local last_search = M.get_last_search_keyword(get_picker_type())
        if last_search and last_search ~= "" then
          vim.api.nvim_feedkeys(last_search, '', false)
          require('lu5je0.core.keys').feedkey('<c-c>0v$h<c-g><c-r>_', 'n')
        end
      end, 0)
    end
  })
end

-- WSL+WezTerm: force remote data transfer mode and fix terminal pixel size.
-- WezTerm on Windows cannot read Linux paths (snacks uses t=f by default),
-- and WSL pty ioctl often returns xpixel/ypixel=0, causing broken image scaling.
local function patch_snacks_wsl_wezterm_image()
  if vim.fn.has('wsl') ~= 1 or vim.env.TERM_PROGRAM ~= 'WezTerm' then
    return
  end

  vim.env.SNACKS_WEZTERM = vim.env.SNACKS_WEZTERM or 'true'
  vim.env.SNACKS_SSH = vim.env.SNACKS_SSH or 'true'

  local function wezterm_exe()
    local exe = vim.fn.exepath('wezterm.exe')
    if exe ~= '' then
      return exe
    end
    if vim.env.WIN_HOME then
      local shim = vim.env.WIN_HOME .. '/scoop/shims/wezterm.exe'
      if vim.fn.executable(shim) == 1 then
        return shim
      end
    end
  end

  local wezterm_pane_size_cache = nil

  local function wezterm_pane_size(columns, rows)
    if wezterm_pane_size_cache
        and wezterm_pane_size_cache.request_columns == columns
        and wezterm_pane_size_cache.request_rows == rows then
      return wezterm_pane_size_cache
    end

    local exe = wezterm_exe()
    if not exe then
      return
    end

    local ok, result = pcall(function()
      if vim.system then
        return vim.system({ exe, 'cli', 'list', '--format', 'json' }, { text = true }):wait(1000)
      end
      local stdout = vim.fn.system({ exe, 'cli', 'list', '--format', 'json' })
      return { code = vim.v.shell_error, stdout = stdout }
    end)
    if not ok or result.code ~= 0 then
      return
    end

    local decoded_ok, panes = pcall(vim.json.decode, result.stdout)
    if not decoded_ok or type(panes) ~= 'table' then
      return
    end

    local best = nil
    local best_score = -1
    for _, pane in ipairs(panes) do
      local size = type(pane) == 'table' and pane.size or nil
      local pixel_width = size and tonumber(size.pixel_width)
      local pixel_height = size and tonumber(size.pixel_height)
      local pane_columns = size and tonumber(size.cols)
      local pane_rows = size and tonumber(size.rows)
      if pixel_width and pixel_height and pane_columns and pane_rows
          and pixel_width > 0 and pixel_height > 0 and pane_columns > 0 and pane_rows > 0 then
        local score = 0
        if pane_columns == columns then
          score = score + 2
        end
        if pane_rows == rows then
          score = score + 2
        end
        if pane.is_active then
          score = score + 1
        end
        if score > best_score then
          best = {
            request_columns = columns,
            request_rows = rows,
            columns = pane_columns,
            rows = pane_rows,
            width = pixel_width,
            height = pixel_height,
          }
          best_score = score
        end
      end
    end

    wezterm_pane_size_cache = best
    return best
  end

  return function()
    local terminal = require('snacks.image.terminal')
    if terminal._lu5je0_wsl_wezterm_size_patch then
      return
    end
    terminal._lu5je0_wsl_wezterm_size_patch = true

    local orig_size = terminal.size
    terminal.size = function()
      local ret = vim.deepcopy(orig_size())
      if ret.cell_width > 0 and ret.cell_height > 0 and ret.width > 0 and ret.height > 0 then
        return ret
      end

      ret.columns = ret.columns > 0 and ret.columns or vim.o.columns
      ret.rows = ret.rows > 0 and ret.rows or vim.o.lines
      local pane_size = wezterm_pane_size(ret.columns, ret.rows)
      if pane_size then
        ret.columns = pane_size.columns
        ret.rows = pane_size.rows
        ret.width = pane_size.width
        ret.height = pane_size.height
        ret.cell_width = pane_size.width / pane_size.columns
        ret.cell_height = pane_size.height / pane_size.rows
        ret.scale = math.max(1, ret.cell_width / 8)
        return ret
      end

      local pixel_width = tonumber(vim.env.SNACKS_WEZTERM_PIXEL_WIDTH)
      local pixel_height = tonumber(vim.env.SNACKS_WEZTERM_PIXEL_HEIGHT)
      if pixel_width and pixel_height and pixel_width > 0 and pixel_height > 0 then
        ret.width = pixel_width
        ret.height = pixel_height
        ret.cell_width = pixel_width / ret.columns
        ret.cell_height = pixel_height / ret.rows
        ret.scale = math.max(1, ret.cell_width / 8)
        return ret
      end

      ret.cell_width = tonumber(vim.env.SNACKS_WEZTERM_CELL_WIDTH) or 9
      ret.cell_height = tonumber(vim.env.SNACKS_WEZTERM_CELL_HEIGHT) or 15
      ret.width = ret.columns * ret.cell_width
      ret.height = ret.rows * ret.cell_height
      ret.scale = math.max(1, ret.cell_width / 8)
      return ret
    end
  end
end

-- WezTerm: invalidate snacks image convert cache when source file is newer.
-- snacks caches identify results by file path sha256 but never checks mtime,
-- so replacing a file (e.g. /tmp/iocr/source.png) causes stale dimensions.
local function patch_snacks_image_convert_cache()
  if vim.env.TERM_PROGRAM ~= 'WezTerm' then
    return
  end

  local convert_mod = require('snacks.image.convert')
  if convert_mod._lu5je0_cache_patch then
    return
  end
  convert_mod._lu5je0_cache_patch = true

  local orig_convert = convert_mod.convert
  convert_mod.convert = function(opts)
    local instance = orig_convert(opts)
    if instance and instance.steps and instance.src then
      local uv = vim.uv or vim.loop
      local src_stat = uv.fs_stat(instance.src)
      if src_stat then
        for _, step in ipairs(instance.steps) do
          if step.done and step.file then
            local cache_stat = uv.fs_stat(step.file)
            if cache_stat and src_stat.mtime.sec > cache_stat.mtime.sec then
              os.remove(step.file)
              step.done = false
            end
          end
        end
      end
    end
    return instance
  end
end

M.setup = function()
  local post_setup_wsl_wezterm = patch_snacks_wsl_wezterm_image()

  require('snacks').setup({
    image = {
      -- your image configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    },
    -- indent = {
    --   indent = {
    --     char = "▏"
    --   },
    --   scope = {
    --     char = "▏"
    --   },
    --   animate = {
    --
    --   },
    --   filter = function(buf)
    --     return vim.g.snacks_indent ~= false and vim.b[buf].snacks_indent ~= false and vim.bo[buf].buftype == "" and require('lu5je0.ext.big-file').is_big_file(buf) and vim.bo[buf].filetype == 'markdown'
    --   end
    -- },
    picker = {
      layout = {
        cycle = true,
        --- Use the default layout or vertical if the window is too narrow
        preset = function()
          return vim.o.columns >= 100 and "default" or "vertical"
        end,
      },
      win = {
        -- input window
        input = {
          keys = {
            ["<c-n>"] = { "history_forward", mode = { "i", "n" } },
            ["<c-p>"] = { "history_back", mode = { "i", "n" } },
            ["<esc>"] = { "close", mode = { "n", "i" } },
            ["<c-c>"] = { "close", mode = { "n" } },
          }
        }
      }
    }
  })
  if post_setup_wsl_wezterm then post_setup_wsl_wezterm() end
  patch_snacks_image_convert_cache()

  -- local wrapper_fn_for_visual = function(fun)
  --   return function()
  --     local search = require('lu5je0.core.visual').get_visual_selection_as_string()
  --     fun()
  --     vim.schedule(function()
  --       require('lu5je0.core.keys').feedkey(search)
  --     end)
  --   end
  -- end
  -- vim.keymap.set('n', '<leader>ps', function() Snacks.profiler.toggle() end)
  -- vim.keymap.set('n', '<leader>ff', function() Snacks.picker.pick("files", {}) end)
  -- vim.keymap.set('n', '<leader>fj', function() Snacks.picker.pick("files", { dirs = { '~/junk-file/' } }) end)
  -- vim.keymap.set('n', '<leader>fm', function() Snacks.picker.pick("recent", {}) end)
  -- vim.keymap.set('n', '<leader>fh', function() Snacks.picker.pick("help", {}) end)
  -- vim.cmd('map <leader>fn :set filetype=')
  -- -- vim.keymap.set('n', '<leader>ft', function() Snacks.picker.pick("filetype", {}) end)
  -- vim.keymap.set('n', '<leader>fr', function() Snacks.picker.pick("grep", {}) end)
  -- -- 默认是smart-case
  -- vim.keymap.set('x', '<leader>fr', wrapper_fn_for_visual(function() Snacks.picker.pick("grep", {}) end))
  -- vim.keymap.set('n', '<leader>fR', function() Snacks.picker.pick("git_grep", {}) end)
  vim.keymap.set('n', '<leader>fg', function() Snacks.picker.pick("git_status", {}) end)
  vim.keymap.set('n', '<leader>fG', function() Snacks.picker.pick("git_diff", {}) end)
  -- vim.keymap.set('n', '<leader>fl', function() Snacks.picker.pick("git_log", {}) end)
  vim.keymap.set('n', '<leader>fp',
    function()
      Snacks.picker.pick("projects",
        {
          confirm = function(picker, item)
            vim.cmd('cd ' .. item.file)
            picker:close()
          end
        })
    end)
  vim.keymap.set('n', '<leader>f\"', function() Snacks.picker.pick("registers", {}) end)

  remember_last_search()
end

return M
