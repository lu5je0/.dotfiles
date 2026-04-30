local M = {
  log_width = 15,
  win_height = 0.5,
  win_height_expanded = 0.9,

  git_status = {},
  project_log = {
    max_commits = 1000,
  },
  line_log = {},
}

function M.get(scope, key)
  local sub = M[scope]
  if sub and sub[key] ~= nil then
    return sub[key]
  end
  return M[key]
end

return M
