local builtin = require("telescope.builtin")

-- Telescope
vim.keymap.set("n", "<C-p>", builtin.find_files, { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })

-- Neo-tree
vim.keymap.set("n", "<C-n>", ":Neotree filesystem reveal left<CR>", { desc = "Toggle Neo-tree" })

-- Diagnostics
vim.keymap.set("n", "<C-k>", vim.diagnostic.open_float, { desc = "Open floating diagnostic" })

-- General
vim.keymap.set("n", "<leader>w", ":w<CR>", { desc = "Save file" })

-- Sistem Clipboard
-- y/p  → yalnızca Neovim'in iç register'ı (sistem clipboard'una dokunmaz)
-- "+y  → sistem clipboard'una kopyala (normal: mevcut satır, visual: seçili alan)
-- "+p  → sistem clipboard'undan yapıştır
vim.keymap.set("n", "<leader>y", '"+yy', { desc = "Sistem clipboard'una satırı kopyala" })
vim.keymap.set("v", "<leader>y", '"+y', { desc = "Sistem clipboard'una seçimi kopyala" })
vim.keymap.set("n", "<leader>p", '"+p', { desc = "Sistem clipboard'undan yapıştır (sonra)" })
vim.keymap.set("n", "<leader>P", '"+P', { desc = "Sistem clipboard'undan yapıştır (önce)" })
-- jk -> ESC mapping kaldırıldı: insert modunda "j" yazarken timeoutlen
-- kadar gecikmeye (Neovim jk sequence bekler) neden oluyordu.
-- ESC veya <C-[> kullanın.

-- Buffers
-- Neo-tree penceresindeyken L/H tuşları sidebar'ı bozmasın diye filetype kontrolü yapılıyor
local function buf_nav(cmd)
  return function()
    if vim.bo.filetype == "neo-tree" then
      return
    end
    vim.cmd(cmd)
  end
end
vim.keymap.set("n", "L", buf_nav("bnext"), { desc = "Next buffer" })
vim.keymap.set("n", "H", buf_nav("bprevious"), { desc = "Previous buffer" })

-- Close buffer without closing the split window/layout
local function close_buffer()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  -- Don't close special buffers (like Neo-tree, Opencode)
  local ft = vim.bo[current_buf].filetype
  if ft == "neo-tree" or ft == "opencode" or ft == "opencode_output" or ft == "opencode_footer" then
    return
  end

  -- Get all listed buffers
  local bufs = vim.api.nvim_list_bufs()
  local alternate_buf = nil
  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and buf ~= current_buf then
      alternate_buf = buf
      break
    end
  end

  if alternate_buf then
    vim.api.nvim_win_set_buf(current_win, alternate_buf)
  else
    -- Create an empty scratch buffer
    local scratch = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_win_set_buf(current_win, scratch)
  end

  -- Delete the original buffer
  pcall(vim.api.nvim_buf_delete, current_buf, { force = false })
end
vim.keymap.set("n", "<leader>x", close_buffer, { desc = "Close buffer (keep layout)" })
vim.keymap.set("n", "<leader>bp", ":BufferLineTogglePin<CR>", { desc = "Toggle pin buffer" })

-- Toggle LSP progress
vim.keymap.set("n", "<leader>up", function()
  if vim.g.lsp_progress_show == false then
    vim.g.lsp_progress_show = true
    vim.notify("LSP Progress Gösteriliyor", vim.log.levels.INFO)
  else
    vim.g.lsp_progress_show = false
    vim.notify("LSP Progress Gizlendi", vim.log.levels.INFO)
  end
end, { desc = "Toggle LSP progress" })

-- Fix Ctrl+Backspace to delete word by word
vim.keymap.set("i", "<C-H>", "<C-W>", { noremap = true, silent = true })
vim.keymap.set("c", "<C-H>", "<C-W>", { noremap = true, silent = true })
-- Some terminals send <C-BS> instead of <C-H>
vim.keymap.set("i", "<C-BS>", "<C-W>", { noremap = true, silent = true })
vim.keymap.set("c", "<C-BS>", "<C-W>", { noremap = true, silent = true })

-- Fix Ctrl+Delete to delete next word
vim.keymap.set("i", "<C-Del>", "<C-o>dw", { noremap = true, silent = true })
vim.keymap.set("c", "<C-Del>", "<C-Right><C-W>", { noremap = true, silent = true })

-- Neovide specific keymaps
if vim.g.neovide then
  vim.keymap.set("n", "<F11>", function()
    vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
  end, { desc = "Toggle Fullscreen" })

  vim.keymap.set({ "n", "v", "i" }, "<C-S-n>", function()
    vim.fn.jobstart({ "alacritty", "--working-directory", vim.fn.getcwd() }, { detach = true })
  end, { desc = "Open Alacritty in current directory" })
end

-- Terminal benzeri Copy/Paste kısayolları
-- Alacritty 0.13+ Kitty Keyboard Protocol sayesinde terminal Neovim'de de çalışır.
vim.keymap.set("n", "<C-S-v>", '"+P', { desc = "Paste from clipboard" })
vim.keymap.set("v", "<C-S-v>", '"+P', { desc = "Paste from clipboard" })
vim.keymap.set("c", "<C-S-v>", "<C-R>+", { desc = "Paste from clipboard" })
vim.keymap.set("i", "<C-S-v>", "<C-R><C-O>+", { desc = "Paste from clipboard" })
vim.keymap.set("v", "<C-S-c>", '"+y', { desc = "Copy to clipboard" })

-- =============================================================================
-- WINDOW TILING & LAYOUT MANAGER (KWin-inspired sidebar stabilizer)
-- =============================================================================
vim.g.last_win_count = #vim.api.nvim_tabpage_list_wins(0)
vim.g.last_columns = vim.o.columns

local layout_group = vim.api.nvim_create_augroup("NeotreeLayoutManager", { clear = true })
local is_adjusting = false

-- Automatically enforce widths on layout change (to prevent Neo-tree/Opencode from stretching)
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinClosed", "WinEnter", "WinResized" }, {
  group = layout_group,
  callback = function()
    if is_adjusting then
      return
    end
    vim.schedule(function()
      if is_adjusting then
        return
      end
      local neotree_win = nil
      local opencode_win = nil
      local other_wins = {}

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == "" then
          local buf = vim.api.nvim_win_get_buf(win)
          local ft = vim.bo[buf].filetype
          if ft == "neo-tree" then
            neotree_win = win
          elseif ft == "opencode" or ft == "opencode_output" or ft == "opencode_footer" then
            opencode_win = win
            table.insert(other_wins, win)
          else
            table.insert(other_wins, win)
          end
        end
      end

      -- Update win count and columns before adjusting to prevent the saver from interpreting it as manual resize
      vim.g.last_win_count = #vim.api.nvim_tabpage_list_wins(0)
      vim.g.last_columns = vim.o.columns

      local total_regular_wins = (neotree_win and 1 or 0) + #other_wins
      if total_regular_wins > 1 then
        is_adjusting = true

        -- Enforce Neo-tree position (far left)
        if neotree_win then
          local _, col = unpack(vim.api.nvim_win_get_position(neotree_win))
          if col > 0 then
            pcall(vim.api.nvim_win_call, neotree_win, function()
              vim.cmd("wincmd H")
            end)
          end
        end

        -- Enforce Opencode position (far right)
        if opencode_win then
          local _, col = unpack(vim.api.nvim_win_get_position(opencode_win))
          local width = vim.api.nvim_win_get_width(opencode_win)
          if col + width < vim.o.columns then
            pcall(vim.api.nvim_win_call, opencode_win, function()
              vim.cmd("wincmd L")
            end)
          end
        end

        -- Enforce Neo-tree width (default 25%)
        local target_neotree = 0
        if neotree_win then
          target_neotree = math.max(30, math.min(50, math.floor(vim.o.columns * 0.25)))
          if vim.api.nvim_win_get_width(neotree_win) ~= target_neotree then
            pcall(vim.api.nvim_win_set_width, neotree_win, target_neotree)
          end
        end

        -- Enforce focused window width based on remaining space
        -- Filter out special layout windows like quickfix/help/lazy to get actual resize targets
        local resize_targets = {}
        for _, win in ipairs(other_wins) do
          local buf = vim.api.nvim_win_get_buf(win)
          local ft = vim.bo[buf].filetype
          if ft ~= "qf" and ft ~= "help" and ft ~= "lazy" then
            table.insert(resize_targets, win)
          end
        end

        if #resize_targets > 1 then
          local current_win = vim.api.nvim_get_current_win()
          local is_target_focused = false
          for _, win in ipairs(resize_targets) do
            if win == current_win then
              is_target_focused = true
              break
            end
          end

          if is_target_focused then
            local buf = vim.api.nvim_win_get_buf(current_win)
            local ft = vim.bo[buf].filetype
            local buftype = vim.bo[buf].buftype

            local ratio = 0.50 -- Default ratio
            if ft == "opencode" or ft == "opencode_output" or ft == "opencode_footer" then
              ratio = 0.40
            elseif buftype == "" then
              ratio = 0.70
            end

            local remaining_columns = vim.o.columns - target_neotree
            local target_width = math.floor(remaining_columns * ratio)
            if vim.api.nvim_win_get_width(current_win) ~= target_width then
              pcall(vim.api.nvim_win_set_width, current_win, target_width)
            end
          end
        end

        -- Reset flag after layout has settled
        vim.defer_fn(function()
          is_adjusting = false
        end, 50)
      end
    end)
  end,
})

-- Force Neo-tree to always be scrolled to the far left (column 0)
vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled", "BufEnter" }, {
  group = layout_group,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neo-tree" then
        local view = vim.fn.winsaveview()
        if view.leftcol > 0 then
          view.leftcol = 0
          vim.fn.winrestview(view)
        end
      end
    end
  end,
})

-- Opencode input window custom scrolloff setting
vim.api.nvim_create_autocmd("FileType", {
  group = layout_group,
  pattern = { "opencode", "opencode_output" },
  callback = function()
    vim.opt_local.scrolloff = 3
  end,
})
