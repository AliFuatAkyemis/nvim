-- Tek kisayol: gc
-- Normal: mevcut satiri // ile toggle eder.
-- Visual line: tek satir //; cok satir /* ... */ (formatter'in yildiz stili).
-- Visual block: her satirda sadece secili parcayi /* ... */ icine alir.
-- Formatter'dan gecmis bloklar ( * onekleri, degisken bosluk/tab) de geri alinir.

local M = {}

local function indent_of(line)
  return line:match("^%s*") or ""
end

local function line_markers()
  local prefix = (vim.bo.commentstring or "// %s"):match("^(.-)%%s") or "// "
  return prefix, prefix:gsub("%s+$", "")
end

local function is_line_commented(line, bare)
  return line:match("^%s*" .. vim.pesc(bare)) ~= nil
end

local function toggle_line_text(line)
  local indent, rest = line:match("^(%s*)(.*)$")
  local prefix, bare = line_markers()
  if rest:match("^" .. vim.pesc(bare)) then
    rest = rest:gsub("^" .. vim.pesc(bare) .. "%s?", "", 1)
    return indent .. rest
  end
  return indent .. prefix .. rest
end

local function block_markers()
  local cs = vim.bo.commentstring or ""
  if cs:find("/*", 1, true) and cs:find("*/", 1, true) then
    return true
  end
  -- Java'nin commentstring'i sadece //; blok stili ayrica desteklenir.
  return vim.bo.filetype == "java"
end

local function is_block(lines)
  return #lines >= 2 and vim.trim(lines[1]) == "/*" and vim.trim(lines[#lines]) == "*/"
end

local function add_block(lines)
  local base = indent_of(lines[1])
  local out = { base .. "/*" }
  for _, line in ipairs(lines) do
    local content = line
    if base ~= "" then
      if content:sub(1, #base) == base then
        content = content:sub(#base + 1)
      else
        content = content:gsub("^%s+", "")
      end
    end
    if content == "" then
      out[#out + 1] = base .. " *"
    else
      out[#out + 1] = base .. " * " .. content
    end
  end
  out[#out + 1] = base .. " */"
  return out
end

local function remove_block(lines)
  local base = indent_of(lines[1])
  local out = {}
  for i = 2, #lines - 1 do
    local content = lines[i]:gsub("^%s*%*%s?", "")
    if content == "" then
      out[#out + 1] = ""
    else
      out[#out + 1] = base .. content
    end
  end
  return out
end

local function all_line_commented(lines, bare)
  local found = false
  for _, line in ipairs(lines) do
    if line:match("%S") then
      found = true
      if not is_line_commented(line, bare) then
        return false
      end
    end
  end
  return found
end

local function toggle_lines(lines)
  if #lines == 1 then
    return { toggle_line_text(lines[1]) }
  end
  if is_block(lines) then
    return remove_block(lines)
  end

  local _, bare = line_markers()
  if all_line_commented(lines, bare) then
    local out = {}
    for i, line in ipairs(lines) do
      out[i] = toggle_line_text(line)
    end
    return out
  end

  if block_markers() then
    return add_block(lines)
  end

  local out = {}
  for i, line in ipairs(lines) do
    out[i] = toggle_line_text(line)
  end
  return out
end

M.toggle_line = function()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { toggle_line_text(line) })
end

local function comment_span(line)
  local start_col = line:find("/*", 1, true)
  if not start_col then
    return nil
  end
  local end_col = line:find("*/", start_col + 2, true)
  if not end_col then
    return nil
  end
  return start_col, end_col + 1
end

local function unwrap_inline(line, sel_start, sel_end)
  local start_col, end_col = comment_span(line)
  if not start_col or sel_end < start_col or sel_start > end_col then
    return nil
  end
  local inner = line:sub(start_col + 2, end_col - 2):gsub("^%s?", ""):gsub("%s?$", "")
  return line:sub(1, start_col - 1) .. inner .. line:sub(end_col + 1), start_col, start_col + #inner - 1
end

local function wrap_inline(line, sel_start, sel_end)
  local wrapped = line:sub(1, sel_start - 1)
    .. "/* "
    .. line:sub(sel_start, sel_end)
    .. " */"
    .. line:sub(sel_end + 1)
  return wrapped, sel_start, sel_end + 6
end

local function toggle_blockwise(lines, start_col, end_col)
  local results = {}
  local all_commented = true
  local any = false

  for i, line in ipairs(lines) do
    local sel_start = math.min(start_col, #line + 1)
    local sel_end = math.min(end_col, #line)
    if sel_end >= sel_start then
      any = true
      local text, from, to = unwrap_inline(line, sel_start, sel_end)
      if text then
        results[i] = { text = text, from = from, to = to }
      else
        all_commented = false
      end
    end
  end

  if not any then
    return lines
  end

  local out = {}
  local mark_from, mark_to
  for i, line in ipairs(lines) do
    if results[i] then
      out[i] = results[i].text
      mark_from = math.min(mark_from or results[i].from, results[i].from)
      mark_to = math.max(mark_to or results[i].to, results[i].to)
    elseif all_commented then
      out[i] = line
    else
      local sel_start = math.min(start_col, #line + 1)
      local sel_end = math.min(end_col, #line)
      if sel_end >= sel_start then
        local text, from, to = wrap_inline(line, sel_start, sel_end)
        out[i] = text
        mark_from = math.min(mark_from or from, from)
        mark_to = math.max(mark_to or to, to)
      else
        out[i] = line
      end
    end
  end

  return out, mark_from, mark_to
end

local function set_visual_marks(srow, erow, scol, ecol)
  vim.fn.setpos("'<", { 0, srow, scol or 1, 0 })
  vim.fn.setpos("'>", { 0, erow, ecol or 1, 0 })
end

M.toggle_visual = function(mode_)
  mode_ = mode_ or vim.fn.visualmode()
  local srow = math.min(vim.fn.line("'<"), vim.fn.line("'>"))
  local erow = math.max(vim.fn.line("'<"), vim.fn.line("'>"))
  local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)

  local out, mark_from, mark_to
  if mode_ == "\22" then
    local col1 = vim.fn.getpos("'<")[3]
    local col2 = vim.fn.getpos("'>")[3]
    out, mark_from, mark_to = toggle_blockwise(lines, math.min(col1, col2), math.max(col1, col2))
  else
    -- charwise secim de satir bazli davranir
    out = toggle_lines(lines)
  end

  vim.api.nvim_buf_set_lines(0, srow - 1, erow, false, out)
  set_visual_marks(srow, srow + #out - 1, mark_from, mark_to)
end

function M.setup()
  -- Neovim'in yerlesik gcc/gbc/gc operatoru ve eski Comment.nvim
  -- kalintilari kalmasin: tek yorum tusu gc.
  for _, lhs in ipairs({ "gc", "gcc", "gb", "gbc", "gco", "gcO", "gcA" }) do
    for _, mode_ in ipairs({ "n", "x", "o" }) do
      pcall(vim.keymap.del, mode_, lhs)
    end
  end

  vim.keymap.set("n", "gc", M.toggle_line, { desc = "Toggle line comment" })
  vim.keymap.set(
    "x",
    "gc",
    ":<C-u>lua require('config.comments').toggle_visual()<CR>",
    { silent = true, desc = "Toggle comment" }
  )
end

return M
