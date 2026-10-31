return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  keys = {
    {
      "<leader>f",
      function()
        require("conform").format({ async = true, lsp_format = "fallback" })
      end,
      mode = "",
      desc = "Format buffer",
    },
  },
  opts = function()
    -- Indent kaynagi tek: config.indent_sync. Formatter argumanlari buradan
    -- uretilir; boylece yazarken gorunen girinti ile format sonrasi ayni olur.
    local indent_sync = require("config.indent_sync")

    local formatters_by_ft = {
      lua = { "stylua" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      html = { "prettier" },
      htmlangular = { "prettier" },
      css = { "prettier" },
      scss = { "prettier" },
      less = { "prettier" },
      json = { "prettier" },
      jsonc = { "prettier" },
      yaml = { "prettier" },
      kotlin = { "ktlint" },
      -- NOTE: markdown kasitli olarak listelenmez. Obsidian tarzi ham yazim
      -- icin prettier otomatik formatlamasi kaldirildi (bkz. format_on_save).
    }

    -- clang-format yoksa C/C++ icin LSP fallback (clangd) devreye girsin.
    if vim.fn.executable("clang-format") == 1 then
      formatters_by_ft.c = { "clang_format" }
      formatters_by_ft.cpp = { "clang_format" }
      formatters_by_ft.objc = { "clang_format" }
      formatters_by_ft.objcpp = { "clang_format" }
    end

    return {
      formatters_by_ft = formatters_by_ft,
      format_on_save = function(bufnr)
        local ft = vim.bo[bufnr].filetype
        -- Markdown hic otomatik bicimlendirilmez (Obsidian gibi ham yazilir)
        -- prettier markdown'i 80 sutuna yeniden sarar ve emphasis toggle'i bozar.
        if ft == "markdown" or ft == "opencode_output" then
          return nil
        end
        local timeout = 500
        if ft == "kotlin" or ft == "java" then
          timeout = 3000
        end
        return { timeout_ms = timeout, lsp_format = "fallback" }
      end,
      formatters = {
        -- Proje config'i varsa formatter kendi kuralini uygular, arguman yok.
        -- Yoksa buffer indent ayarlari acikca gecirilir.
        prettier = {
          prepend_args = function(_, ctx)
            return indent_sync.prettier_args(ctx.buf)
          end,
        },
        stylua = {
          prepend_args = function(_, ctx)
            return indent_sync.stylua_args(ctx.buf)
          end,
        },
        clang_format = {
          prepend_args = function(_, ctx)
            return { indent_sync.clang_style(ctx.buf) }
          end,
        },
      },
    }
  end,
}
