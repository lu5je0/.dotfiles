local M = {}

function M.is_blank(s)
  return s == nil or s:match("%S") == nil
end

function M.trim(s)
  return s:match "^%s*(.*)":match "(.-)%s*$"
end

--@brief 切割字符串，并用“...”替换尾部
--@param filename:要切割的字符串
--@return max_len，字符串上限,中文字为2的倍数
--@param en_max_len：显示英文字个数，中文字为2的倍数,可为空
--@note         函数实现：截取字符串一部分，剩余用“...”替换
function M.get_short_filename(filename, max_len, en_max_len)
  local sStr = filename
  local tCode = {}
  local tName = {}
  local nLenInByte = #sStr
  local nWidth = 0
  if en_max_len == nil then
    en_max_len = max_len - 3
  end
  for i = 1, nLenInByte do
    local curByte = string.byte(sStr, i)
    local byteCount = 0;
    if curByte > 0 and curByte <= 127 then
      byteCount = 1
    elseif curByte >= 192 and curByte < 223 then
      byteCount = 2
    elseif curByte >= 224 and curByte < 239 then
      byteCount = 3
    elseif curByte >= 240 and curByte <= 247 then
      byteCount = 4
    end
    local char = nil
    if byteCount > 0 then
      char = string.sub(sStr, i, i + byteCount - 1)
      i = i + byteCount - 1
    end
    if byteCount == 1 then
      nWidth = nWidth + 1
      table.insert(tName, char)
      table.insert(tCode, 1)
    elseif byteCount > 1 then
      nWidth = nWidth + 2
      table.insert(tName, char)
      table.insert(tCode, 2)
    end
  end

  if nWidth > max_len then
    local _sN = ""
    local _len = 0
    for i = 1, #tName do
      _sN = _sN .. tName[i]
      _len = _len + tCode[i]
      if _len >= en_max_len then
        break
      end
    end
    filename = _sN .. "…"
  end
  return filename
end

return M
