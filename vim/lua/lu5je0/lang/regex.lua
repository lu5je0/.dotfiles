local M = {}

--- Convert a Perl-style regex pattern to Vim very-magic regex.
--- Handles lazy quantifiers: *? +? ??
--- Prepends \v\c for very-magic case-insensitive mode.
--- Returns a compiled vim.regex object, or nil if the pattern is invalid/empty.
function M.compile(pattern)
  if not pattern or pattern == '' then
    return nil
  end
  local pat = pattern:gsub('%*%?', '{-}'):gsub('%+%?', '{-1,}'):gsub('%?%?', '{-0,1}')
  local ok, r = pcall(vim.regex, '\\v\\c' .. pat)
  if ok then
    return r
  end
  return nil
end

return M
