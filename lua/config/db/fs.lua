-- Kök dizinle sınırlı dosya okuma. Symlink/`..` ile kök dışına çıkan
-- yollar reddedilir.

local M = {}

---@param path string
---@param root string
---@return string|nil
function M.read(path, root)
  if type(path) ~= "string" or type(root) ~= "string" then
    return nil
  end

  local real_root = vim.uv.fs_realpath(vim.fs.normalize(root))
  local real_path = vim.uv.fs_realpath(vim.fs.normalize(path))
  if not real_root or not real_path then
    return nil
  end
  if not vim.startswith(real_path, real_root .. "/") and real_path ~= real_root then
    return nil
  end

  local file = io.open(real_path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

return M
