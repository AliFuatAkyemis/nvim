return {
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile", "InsertLeave" },
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = {
        html = { "htmlhint" },
        htmlangular = { "htmlhint" },
      }

      -- Suppress "doctype-first" and "attr-lowercase" errors for Angular files or Angular-like attributes
      local htmlhint = lint.linters.htmlhint
      if htmlhint then
        local original_parser = htmlhint.parser
        if original_parser then
          htmlhint.parser = function(output, bufnr)
            local diagnostics = original_parser(output, bufnr)
            local filepath = vim.api.nvim_buf_get_name(bufnr or 0)
            if filepath ~= "" then
              local dir = vim.fs.dirname(filepath)
              -- Check if this is an Angular project by searching upwards for angular.json or project.json
              local is_angular = #vim.fs.find({ "angular.json", "project.json" }, { path = dir, upward = true }) > 0

              local filtered = {}
              for _, diag in ipairs(diagnostics) do
                local keep = true
                -- 1. Suppress doctype-first in Angular projects
                if is_angular and diag.code == "doctype-first" then
                  keep = false
                -- 2. Suppress attr-lowercase in Angular projects
                elseif is_angular and diag.code == "attr-lowercase" then
                  keep = false
                -- 3. Also suppress attr-lowercase if the attribute is Angular/Vue/Svelte syntax (e.g. starts with #, *, (, [)
                elseif diag.code == "attr-lowercase" then
                  local attr = diag.message:match("The attribute name of %[%s*(.-)%s*%] must be in lowercase%.")
                  if attr and attr:sub(1, 1):find("[#%*%(%[%@]") then
                    keep = false
                  end
                end

                if keep then
                  table.insert(filtered, diag)
                end
              end
              return filtered
            end
            return diagnostics
          end
        end
      end

      -- Create autocommand to run linter
      local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },
}
