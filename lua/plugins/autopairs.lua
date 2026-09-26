return {
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    dependencies = { "hrsh7th/nvim-cmp" },
    config = function()
      local npairs = require("nvim-autopairs")
      local Rule = require("nvim-autopairs.rule")
      local cond = require("nvim-autopairs.conds")

      npairs.setup({
        check_ts = true,
        map_cr = true, -- Kendi <CR> mapping'imiz nvim-cmp ile çakıştığından map_cr aktif edildi.
        ts_config = {
          lua = { "string" },
          javascript = { "template_string" },
          typescript = { "template_string" },
        },
      })

      -- Akıllı { kuralı — girinti tabanlı:
      --
      --  { yazıldığında altındaki ilk dolu satıra bakılır:
      --    • "}" ile başlıyor VE mevcut satırdan DAHA AZ girintili → dış bloğa ait,
      --      pair OLUŞTUR (while/for/if kendi }}'sine ihtiyaç duyar)
      --    • "}" ile başlıyor VE aynı / daha fazla girintili → bu bloğun }}'i zaten var,
      --      pair OLUŞTURMA
      --    • "}" ile başlamıyor → pair OLUŞTUR
      --
      local function smart_brace_condition()
        return function(_opts)
          local bufnr = vim.api.nvim_get_current_buf()
          local row = vim.api.nvim_win_get_cursor(0)[1] -- 1-indexed
          local total = vim.api.nvim_buf_line_count(bufnr)

          -- Mevcut satırın girinti genişliği
          local cur_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
          local cur_indent = #(cur_line:match("^(%s*)") or "")

          -- İmleçten sonraki satırları tara (0-indexed: row = bir sonraki satır)
          for lnum = row, total - 1 do
            local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
            if not line then
              break
            end

            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
              if trimmed:match("^}") then
                local line_indent = #(line:match("^(%s*)") or "")
                -- Dış bloğun }}'si → pair oluştur
                -- Aynı bloğun }}'si → pair oluşturma
                return line_indent < cur_indent
              else
                return true -- Altta } yok, pair oluştur
              end
            end
          end

          return true -- Dosyanın geri kalanında hiç } yok
        end
      end

      -- Varsayılan { kuralını kaldır, yerine akıllı olanı ekle
      npairs.remove_rule("{")
      npairs.add_rule(
        Rule("{", "}"):with_pair(smart_brace_condition()):with_pair(cond.not_before_text("}")) -- imleç zaten } öncesindeyse de açma
      )

      -- <CR> mapping'deki "<80>ýal! ====" hatası (cmp fallback bug) nedeniyle
      -- custom vim.keymap.set kaldırıldı. npairs.autopairs_cr() map_cr=true ile
      -- otomatik ve sorunsuz bir şekilde pair-split işlemini yönetir.
      -- indentexpr (config/indent.lua) kaldığı yerden çalışmaya devam eder.

      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      local cmp = require("cmp")
      cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
  },
}
