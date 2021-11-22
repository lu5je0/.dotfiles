function string.startswith(self, str)
  return string.sub(self, 1 , string.len(str)) == str
end
