-- Alt split'te tek terminal. <C-j> acar/odaklar/kapatir; kapaninca gelinen
-- pencereye (neo-tree, opencode veya metin) doner.
local M = {}

-- "Neovim'i baslattigim dizin" semantigi: :cd sonrasi degismez.
local startup_cwd = vim.fn.getcwd()
local term_buf = nil
local text_win = nil
local last_text_win = nil
local layout_guard_until = 0
-- <C-j> ile terminale girilen pencere ve terminal disinda son odaklanan pencere.
-- Kapatinca terminale nereden gelindiyse oraya donulur.
local return_win = nil
local last_focus_win = nil
local focusing_terminal = false

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

-- Terminal yüksekliği pencere yüksekliğine oranlanır: tam ekranda ekranın
-- ~%28'i, pencere küçüldükçe doğrusal olarak %50'ye çıkar. Sabit satır sayısı
-- yerine oran kullanmak, tam ekrana geçişte terminalin ekranı kaplamasını
-- engeller (Neovim büyüyen satırları alt pencerede toplar).
local TERM_RATIO_LARGE = 0.28 -- TERM_LINES_LARGE ve üstünde
local TERM_RATIO_SMALL = 0.50 -- TERM_LINES_SMALL ve altında
local TERM_LINES_LARGE = 50
local TERM_LINES_SMALL = 24

local function term_height_ratio(lines)
  if lines <= TERM_LINES_SMALL then
    return TERM_RATIO_SMALL
  end
  if lines >= TERM_LINES_LARGE then
    return TERM_RATIO_LARGE
  end
  local t = (lines - TERM_LINES_SMALL) / (TERM_LINES_LARGE - TERM_LINES_SMALL)
  return TERM_RATIO_SMALL + (TERM_RATIO_LARGE - TERM_RATIO_SMALL) * t
end

-- Güncel pencere yüksekliğine göre terminal split'inin hedef yüksekliği.
-- Üstteki metin penceresine en az 1 satır, statusline'a 1 satır bırakılır.
function M.target_height()
  local max_height = math.max(1, vim.o.lines - vim.o.cmdheight - 2)
  return math.max(1, math.min(max_height, math.floor(vim.o.lines * term_height_ratio(vim.o.lines))))
end

local function apply_term_height(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  pcall(vim.api.nvim_win_set_height, win, M.target_height())
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

-- Terminale donus hedefi olabilecek pencereler: gecerli, yüzen olmayan ve
-- terminal buffer'ini gostermeyen pencereler.
local function is_returnable_win(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  if term_buf and vim.api.nvim_win_get_buf(win) == term_buf then
    return false
  end
  return true
end

if is_text_win(vim.api.nvim_get_current_win()) then
  last_text_win = vim.api.nvim_get_current_win()
end
if is_returnable_win(vim.api.nvim_get_current_win()) then
  last_focus_win = vim.api.nvim_get_current_win()
end

vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "TabEnter" }, {
  group = vim.api.nvim_create_augroup("TerminalReturnFocus", { clear = true }),
  callback = function()
    if focusing_terminal then
      return
    end
    local win = vim.api.nvim_get_current_win()
    if term_buf and vim.api.nvim_win_get_buf(win) == term_buf then
      -- Terminale baska bir yolla (fare, :wincmd) gelindiyse son odagi hatirla.
      if is_returnable_win(last_focus_win) and last_focus_win ~= win then
        return_win = last_focus_win
      end
    elseif is_returnable_win(win) then
      last_focus_win = win
    end
  end,
})

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

-- Terminal-normal mod: terminalde Esc normal moda gecirir; normal modda Esc
-- calisan uygulamaya ESC bayti olarak gider. Mapler yalnizca terminal buffer'ina
-- ozeldir, metin pencerelerini etkilemez.
local function send_escape_to_job()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then
    return
  end
  local job = vim.b[buf].terminal_job_id
  if job and job > 0 then
    pcall(vim.api.nvim_chan_send, job, "\27")
  end
end

local function attach_terminal_maps(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then
    return
  end
  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { buffer = buf, desc = "Terminal-normal mod" })
  vim.keymap.set("n", "<Esc>", send_escape_to_job, { buffer = buf, desc = "Esc'i terminal uygulamasina gonder" })
end

vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("TerminalNormalMode", { clear = true }),
  callback = function(args)
    attach_terminal_maps(args.buf)
  end,
})

local function open_split_with(buf)
  local target = find_text_win() or vim.api.nvim_get_current_win()
  text_win = target
  if target ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_set_current_win(target)
  end

  vim.cmd("belowright split")
  local term_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(term_win, buf)
  -- UI yeniden boyutlanirken alt pencerenin tüm yeni satırları yutmasını
  -- engelle; yüksekliği VimResized'da orana göre yeniden uyguluyoruz.
  vim.wo[term_win].winfixheight = true
  apply_term_height(term_win)
  return term_win
end

-- Tam ekran giriş/çıkışı ve pencere boyutu değişimlerinde terminal
-- yüksekliğini güncel yüksekliğe göre yeniden hesapla.
vim.api.nvim_create_autocmd("VimResized", {
  group = vim.api.nvim_create_augroup("TerminalHeight", { clear = true }),
  callback = function()
    if not (term_buf and vim.api.nvim_buf_is_valid(term_buf)) then
      return
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == term_buf then
        apply_term_height(win)
      end
    end
  end,
})

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
  attach_terminal_maps(buf)
  vim.cmd("startinsert")
end

local function close_terminal(term_win)
  -- Terminale nereden gelindiyse oraya don: neo-tree, opencode, metin...
  local target = return_win
  if not is_returnable_win(target) or target == term_win then
    target = last_focus_win
  end
  if not is_returnable_win(target) or target == term_win then
    target = find_text_win()
  end
  return_win = nil
  pcall(vim.api.nvim_win_close, term_win, false)
  if is_returnable_win(target) then
    vim.api.nvim_set_current_win(target)
  end
end

local function focus_terminal(term_win)
  if is_returnable_win(vim.api.nvim_get_current_win()) then
    return_win = vim.api.nvim_get_current_win()
  end
  focusing_terminal = true
  vim.api.nvim_set_current_win(term_win)
  vim.cmd("startinsert")
  vim.schedule(function()
    focusing_terminal = false
  end)
end

function M.toggle()
  guard_layout()
  local current = vim.api.nvim_get_current_win()
  local term_win = find_term_win()

  if term_win then
    if current == term_win then
      close_terminal(term_win)
    else
      focus_terminal(term_win)
    end
    return
  end

  if is_returnable_win(current) then
    return_win = current
  end

  focusing_terminal = true
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    open_split_with(term_buf)
    vim.cmd("startinsert")
  else
    start_terminal()
  end
  vim.schedule(function()
    focusing_terminal = false
  end)
end

return M
