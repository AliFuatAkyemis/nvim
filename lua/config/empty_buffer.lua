-- Bos [No Name] buffer temizligi.
-- Neovim acilirken ve <leader>x ile son dosya kapatilirken listede anonim bir
-- buffer kalir. Bir dosya acildiginda bu buffer'lar sekmede gorunmemeli.
local M = {}

local function is_blank(buf)
  -- Yüklenmemiş buffer'ın kaydedilmemiş içeriği olamaz; boş kabul edilir.
  if not vim.api.nvim_buf_is_loaded(buf) then
    return true
  end
  return vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function is_empty_unnamed(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buflisted
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) == ""
    and not vim.bo[buf].modified
    and is_blank(buf)
end

local function is_disposable(buf, current)
  return buf ~= current and is_empty_unnamed(buf) and #vim.fn.win_findbuf(buf) == 0
end

local function first_named_file()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buflisted
      and vim.bo[buf].buftype == ""
      and vim.api.nvim_buf_get_name(buf) ~= ""
    then
      return buf
    end
  end
  return nil
end

-- Sadece bos buffer'lardan olusan tabpage'leri kapatir. Ornek: Unity/Neovide
-- dosyayi ayri sekmede acinca ilk [No Name] sekmesi arkada kalir.
local function close_empty_tabpages()
  if #vim.api.nvim_list_tabpages() < 2 then
    return
  end

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    -- Onceki kapatmalar son tabpage'i biraktiysa dur.
    if #vim.api.nvim_list_tabpages() < 2 then
      return
    end
    if vim.api.nvim_tabpage_is_valid(tab) then
      local all_empty = true
      local wins = vim.api.nvim_tabpage_list_wins(tab)
      for _, win in ipairs(wins) do
        if not is_empty_unnamed(vim.api.nvim_win_get_buf(win)) then
          all_empty = false
          break
        end
      end
      if all_empty then
        if tab ~= vim.api.nvim_get_current_tabpage() then
          vim.api.nvim_set_current_tabpage(tab)
        end
        pcall(vim.cmd, "tabclose")
      end
    end
  end
end

-- Acilista dosya verilmisse arkada kalan [No Name] buffer/sekmesini temizler.
-- Dosya yoksa hicbir sey yapmaz; bos Neovim acilisi [No Name] olarak kalir.
function M.cleanup_startup()
  if not first_named_file() then
    return
  end

  close_empty_tabpages()

  local current = vim.api.nvim_get_current_buf()
  if is_empty_unnamed(current) then
    local target = first_named_file()
    if target then
      pcall(vim.api.nvim_win_set_buf, 0, target)
      current = target
    end
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_disposable(buf, current) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

function M.cleanup()
  local current = vim.api.nvim_get_current_buf()

  -- Sadece gercek bir dosya buffer'indayken temizle. Dosya yoksa [No Name]
  -- sekmesi kalabilir.
  if vim.bo[current].buftype ~= "" or vim.api.nvim_buf_get_name(current) == "" then
    return
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_disposable(buf, current) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- Bufferline, dosya varken bos anonim buffer'i sekme olarak gostermesin.
function M.is_bufferline_visible(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if not is_empty_unnamed(buf) then
    return true
  end
  return first_named_file() == nil
end

function M.setup()
  local group = vim.api.nvim_create_augroup("EmptyBufferCleanup", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      vim.schedule(M.cleanup)
    end,
  })

  -- Dosya argumanlari VimEnter'dan once yuklenir; acilista bir defa agresif
  -- temizlik yap. Normal kullanimda bos split'leri kapatma.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function()
      if vim.v.vim_did_enter == 0 then
        vim.schedule(M.cleanup_startup)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      vim.schedule(M.cleanup_startup)
    end,
  })
end

return M
