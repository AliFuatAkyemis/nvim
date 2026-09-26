return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
      -- {"3rd/image.nvim", opts = {}}, -- Optional image support in preview window: See `# Preview Mode` for more information
    },
    lazy = false, -- neo-tree will lazily load itself
    ---@module "neo-tree"
    -----@type neotree.Config?
    opts = {
      open_files_do_not_replace_types = { "terminal", "trouble", "qf", "opencode", "opencode_output" },
      window = {
        position = "left",
        width = function()
          return math.max(30, math.min(50, math.floor(vim.o.columns * 0.25)))
        end,
      },
      filesystem = {
        use_libuv_file_watcher = true,
        filtered_items = {
          visible = false,
          hide_gitignored = true,
          hide_hidden = true,
          hide_dotfiles = true,
        },
      },
    },
    config = function(_, opts)
      require("neo-tree").setup(opts)
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufDelete", "QuitPre", "WinClosed" }, {
        callback = function()
          vim.schedule(function()
            pcall(function()
              local utils = require("neo-tree.utils")
              local manager = require("neo-tree.sources.manager")
              manager.opened_buffers_changed("filesystem", { opened_buffers = utils.get_opened_buffers() })
            end)
          end)
        end,
      })
    end,
  },
  {
    "nvim-tree/nvim-web-devicons",
    opts = {},
  },
}
