local function toggle_profile()
  local prof = require('profile')
  if prof.is_recording() then
    prof.stop()
    vim.ui.input({ prompt = 'Save profile to:', completion = 'file', default = vim.fs.normalize('~/profile.json') },
      function(filename)
        if filename then
          prof.export(filename)
          vim.notify(string.format('Wrote %s', filename))
        end
      end)
  else
    print('profile is starting now')
    prof.start('*')
  end
end

vim.keymap.set('n', '<S-F1>', toggle_profile)
