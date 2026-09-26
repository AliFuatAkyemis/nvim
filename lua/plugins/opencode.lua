return {
  "sudo-tee/opencode.nvim",
  config = function()
    require("opencode").setup({
      preferred_picker = "telescope",
      preferred_completion = "nvim-cmp",
      default_global_keymaps = true,
      default_mode = "build",
      keymap_prefix = "<leader>o",
      keymap = {
        editor = {
          ["<leader>ott"] = false,
          ["<leader>otr"] = false,
          ["<leader>otm"] = false,
          ["<leader>out"] = { "toggle_tool_output", desc = "Toggle tool output" },
          ["<leader>our"] = { "toggle_reasoning_output", desc = "Toggle reasoning output" },
          ["<leader>oum"] = { "toggle_max_messages", desc = "Toggle max messages" },
        },
      },

      ui = {
        position = "right",
        window_width = math.max(0.20, math.min(0.45, 45 / vim.o.columns)),
        zoom_width = 0.8,
        display_model = true,
        display_context_size = true,
        display_cost = true,
        input = {
          min_height = 0.10,
          max_height = 0.25,
        },
        output = {
          tools = {
            show_output = true,
            show_reasoning_output = true,
            use_folds = true,
          },
        },
      },

      context = {
        enabled = true,
        current_file = {
          enabled = true,
          show_full_path = true,
        },
        selection = {
          enabled = true,
        },
        diagnostics = {
          warning = true,
          error = true,
        },
      },
    })
  end,
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "hrsh7th/nvim-cmp",
  },
}
