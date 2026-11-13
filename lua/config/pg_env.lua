-- PostgreSQL baglanti bilgisini ortamdan bulur.
-- Sirasiyla: DATABASE_URL / PG* ortam degiskenleri, proje kokundeki
-- .env.local / .env icindeki DATABASE_URL.

local M = {}

---@param path string
---@return string|nil
local function read_database_url(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local value
  for line in file:lines() do
    local match = line:match("^%s*DATABASE_URL%s*=%s*(.-)%s*$")
    if match and match ~= "" then
      value = match:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      break
    end
  end
  file:close()
  return value
end

---@param root string|nil
---@return string|nil
function M.database_url(root)
  if vim.env.DATABASE_URL and vim.env.DATABASE_URL ~= "" then
    return vim.env.DATABASE_URL
  end
  if not root then
    return nil
  end

  for _, name in ipairs({ ".env.local", ".env" }) do
    local value = read_database_url(vim.fs.joinpath(root, name))
    if value then
      return value
    end
  end
  return nil
end

---LSP alt sureci icin ortam: mevcut ortam + bulunan DATABASE_URL.
---@param root string|nil
---@return table
function M.environ(root)
  local env = vim.fn.environ()
  local url = M.database_url(root)
  if url then
    env.DATABASE_URL = url
  end
  return env
end

return M
