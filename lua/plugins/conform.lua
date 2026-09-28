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
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      html = { "prettier" },
      htmlangular = { "prettier" },
      css = { "prettier" },
      json = { "prettier" },
      yaml = { "prettier" },
      kotlin = { "ktlint" },
      -- NOTE: markdown kasıtlı olarak listelenmez. Obsidian tarzı ham yazım
      -- için prettier otomatik formatlaması kaldırıldı (bkz. format_on_save).
    },
    format_on_save = function(bufnr)
      local ft = vim.bo[bufnr].filetype
      -- Markdown hiç otomatik biçimlendirilmez (Obsidian gibi ham yazılır)
      -- prettier markdown'ı 80 sütuna yeniden sarar ve emphasis toggle'ı bozar.
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
      prettier = {
        prepend_args = { "--tab-width", "4" },
      },
      stylua = {
        prepend_args = { "--indent-width", "4", "--indent-type", "Spaces" },
      },
    },
  },
}
