-- Prompt input alanlari (Telescope) icin readline-benzeri duzenleme tuslari.
-- Telescope insert modda <C-u>/<C-w> gibi tuslari preview scroll'a bagladigi
-- icin yerlesik insert davranisi kayboluyor; burada dogrudan buffer uzerinde
-- geri veriyoruz (insert modda feedkeys'e guvenmeden, deterministik).

local M = {}

--- Aktif prompt buffer'i, penceresi, satiri ve imlec konumunu dondurur.
--- @return integer, integer, integer, integer, string
local function prompt()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  return buf, win, row, col, line
end

--- Satiri ve imleci gunceller; imleci satir sonuna gore kirpar.
local function apply(buf, win, row, col, line)
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { line })
  local maxcol = #line
  if col > maxcol then
    col = maxcol
  end
  if col < 0 then
    col = 0
  end
  vim.api.nvim_win_set_cursor(win, { row, col })
end

--- Imlecin solundaki her seyi siler (readline <C-u>).
function M.delete_to_start()
  local buf, win, row, col, line = prompt()
  apply(buf, win, row, 0, line:sub(col + 1))
end

--- Imlecin solundaki bosluk + kelimeyi siler (readline <C-w>).
function M.delete_word()
  local buf, win, row, col, line = prompt()
  local keep = line:sub(1, col)
  keep = keep:gsub("%s+$", "")
  keep = keep:gsub("%S+$", "")
  keep = keep:gsub("%s+$", "")
  local newcol = #keep
  apply(buf, win, row, newcol, keep .. line:sub(col + 1))
end

--- Imlecten satir sonuna kadar siler (readline <C-k>).
function M.delete_to_end()
  local buf, win, row, col, line = prompt()
  apply(buf, win, row, col, line:sub(1, col))
end

--- Imleci satir sonuna goturur (readline <C-e>).
function M.move_end()
  local buf, win, row, _, line = prompt()
  apply(buf, win, row, #line, line)
end

--- Imleci bir karakter sola goturur (readline <C-b>).
function M.move_left()
  local buf, win, row, col, line = prompt()
  apply(buf, win, row, col - 1, line)
end

--- Imleci bir karakter saga goturur (readline <C-f>).
function M.move_right()
  local buf, win, row, col, line = prompt()
  apply(buf, win, row, col + 1, line)
end

--- Imlecin sagindaki karakteri siler (readline <C-d>).
function M.delete_forward()
  local buf, win, row, col, line = prompt()
  if col >= #line then
    return
  end
  apply(buf, win, row, col, line:sub(1, col) .. line:sub(col + 2))
end

--- Telescope insert modu mapping tablosu.
--- @return table<string, fun(bufnr: integer)>
function M.mappings()
  return {
    -- Ilk basista kapat (varsayilan: insert'ten cikar, ikinci basista kapatir).
    ["<Esc>"] = function(bufnr)
      require("telescope.actions").close(bufnr)
    end,
    ["<C-u>"] = M.delete_to_start,
    ["<C-w>"] = M.delete_word,
    ["<C-k>"] = M.delete_to_end,
    ["<C-e>"] = M.move_end,
    ["<C-b>"] = M.move_left,
    ["<C-f>"] = M.move_right,
    ["<C-d>"] = M.delete_forward,
  }
end

return M
