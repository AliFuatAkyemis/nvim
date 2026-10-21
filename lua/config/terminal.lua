-- Alt split'te tek terminal. <C-j> acar/kapatir; kapaninca odak metne doner.
local M = {}

-- "Neovim'i baslattigim dizin" semantigi: :cd sonrasi degismez.
local startup_cwd = vim.fn.getcwd()
local term_buf = nil
local text_win = nil
local last_text_win = nil
local layout_guard_until = 0

local function now_ms()
  return (vim.uv or vim.loop).now()
end

-- Terminal acma/kapama sirasinda layout manager'in Neo-tree/opencode
-- genisliklerini yeniden uygulamasini engelle.
local function guard_layout()
  layout_guard_until = now_ms() + 300
end

function M.layout_busy()
  return now_ms() < layout_guard_until
end

local function is_text_win(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  local ft = vim.bo[buf].filetype
  return ft ~= "neo-tree" and ft ~= "opencode" and ft ~= "opencode_output" and ft ~= "opencode_footer" and ft ~= "lazy"
end

if is_text_win(vim.api.nvim_get_current_win()) then
  last_text_win = vim.api.nvim_get_current_win()
end

vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("TerminalTextFocus", { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if is_text_win(win) then
      last_text_win = win
    end
  end,
})

-- Once odaktaki metin penceresi, sonra ayni sekmedeki son metin penceresi,
-- en son ilk metin penceresi. Hicbiri yoksa nil (cagiran mevcut pencereye duser).
local function find_text_win()
  local current = vim.api.nvim_get_current_win()
  if is_text_win(current) then
    return current
  end

  local tab = vim.api.nvim_get_current_tabpage()
  if is_text_win(last_text_win) and vim.api.nvim_win_get_tabpage(last_text_win) == tab then
    return last_text_win
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_text_win(win) then
      return win
    end
  end
  return nil
end

local function find_term_win()
  if not (term_buf and vim.api.nvim_buf_is_valid(term_buf)) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == term_buf then
      return win
    end
  end
  return nil
end

local function open_split_with(buf)
  local target = find_text_win() or vim.api.nvim_get_current_win()
  text_win = target
  if target ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_set_current_win(target)
  end

  vim.cmd("belowright split")
  local term_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(term_win, buf)
  pcall(vim.api.nvim_win_set_height, term_win, 12)
  return term_win
end

local function start_terminal()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  local term_win = open_split_with(buf)

  local ok, err = pcall(vim.fn.termopen, vim.o.shell, {
    cwd = startup_cwd,
    on_exit = function()
      vim.schedule(function()
        if term_buf ~= buf then
          return
        end
        term_buf = nil
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end)
    end,
  })

  if not ok then
    pcall(vim.api.nvim_win_close, term_win, true)
    vim.notify("Terminal baslatilamadi: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  term_buf = buf
  vim.cmd("startinsert")
end

local function close_terminal(term_win)
  local current = vim.api.nvim_get_current_win()
  -- Odak baska bir metin penceresindeyse orada kal; yan panel gibi metin
  -- olmayan bir penceredeyse metin penceresine don.
  local target = current ~= term_win and is_text_win(current) and current or text_win
  pcall(vim.api.nvim_win_close, term_win, false)
  if target and vim.api.nvim_win_is_valid(target) and target ~= term_win then
    vim.api.nvim_set_current_win(target)
  end
end

function M.toggle()
  guard_layout()
  local term_win = find_term_win()
  if term_win then
    close_terminal(term_win)
    return
  end

  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    open_split_with(term_buf)
    vim.cmd("startinsert")
    return
  end

  start_terminal()
end

return M
