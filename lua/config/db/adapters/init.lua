-- Adaptör kaydı: sabit sıra, hata izolasyonu.

local M = {}

M.order = { "env", "dotenv", "spring", "rails", "prisma", "django", "compose" }

---@param root string
---@return table|nil
function M.run(root)
  for _, name in ipairs(M.order) do
    local ok, adapter = pcall(require, "config.db.adapters." .. name)
    if ok and type(adapter.detect) == "function" then
      local called, result = pcall(adapter.detect, root)
      if called and result then
        return result
      end
    end
  end
  return nil
end

return M
