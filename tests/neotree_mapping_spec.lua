-- tests/neotree_mapping_spec.lua
-- Neo-tree <leader>j expand/collapse mapping'i.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/neotree_mapping_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")

local failures, total = 0, 0
local function check(cond, label)
  total = total + 1
  if cond then
    io.write("ok   - " .. label .. "\n")
  else
    failures = failures + 1
    io.write("FAIL - " .. label .. "\n")
  end
end

local spec = dofile(root .. "/lua/plugins/neotree.lua")
local neotree = spec[1]

check(neotree[1] == "nvim-neo-tree/neo-tree.nvim", "neo-tree plugin spec'i bulundu")
check(neotree.opts.filesystem.window.mappings["<leader>j"] == "toggle_node", "neo-tree <leader>j toggle_node")
check(neotree.opts.filesystem.window.mappings["<C-j>"] == nil, "neo-tree <C-j> terminal icin bos")

io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
