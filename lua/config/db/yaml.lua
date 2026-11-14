-- Minimal YAML okuyucu (yalnızca anahtar: değer ve iç içe bloklar).
-- Liste desteği yok; `- ` ile başlayan satırlar atlanır.

local M = {}

---@param value string
---@return string
local function clean(value)
  value = value:gsub("%s+#.*$", "")
  value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
  return vim.trim(value)
end

---@param text string
---@return table
function M.parse(text)
  local result = {}

  ---@type { indent: integer, key: string, node: table }[]
  local stack = {}
  local current = result

  for line in (text or ""):gmatch("[^\r\n]*") do
    local indent, key, value = line:match("^(%s*)([%w_.%-]+)%s*:%s*(.-)%s*$")
    if key then
      indent = #indent
      while #stack > 0 and stack[#stack].indent >= indent do
        current = table.remove(stack).parent
      end

      value = clean(value)
      if value == "" then
        local child = {}
        current[key] = child
        stack[#stack + 1] = { indent = indent, key = key, parent = current }
        current = child
      else
        current[key] = value
      end
    end
  end

  return result
end

---@param path string
---@return table|nil
function M.read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return M.parse(text)
end

return M
