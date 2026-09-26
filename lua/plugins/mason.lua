return {
  {
    "williamboman/mason.nvim",
    event = "VeryLazy",
    opts = {
      ensure_installed = {
        "lua-language-server",
        "jdtls",
        "java-debug-adapter",
        "java-test",
        "marksman",
        "pyright",
        "vtsls",
        "html-lsp",
        "css-lsp",
        "json-lsp",
        "eslint-lsp",
        "tailwindcss-language-server",
        "clangd",
        "gopls",
        "rust-analyzer",
        "bash-language-server",
        "dockerfile-language-server",
        "yaml-language-server",
        "prettier",
        "stylua",
        "angular-language-server",
        "htmlhint",
        "kotlin-language-server",
        "ktlint",
      },
    },
    config = function(_, opts)
      require("mason").setup(opts)
      local mr = require("mason-registry")
      for _, name in ipairs(opts.ensure_installed or {}) do
        local ok, p = pcall(mr.get_package, name)
        if ok and not p:is_installed() then
          p:install()
        end
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      -- Force enable file watching capabilities on Linux
      if not capabilities.workspace then
        capabilities.workspace = {}
      end
      capabilities.workspace.didChangeWatchedFiles = {
        dynamicRegistration = true,
      }
      local mason_path = vim.fn.stdpath("data") .. "/mason"
      local ng_cmd = mason_path .. "/bin/ngserver"
      local ng_modules = mason_path .. "/packages/angular-language-server/node_modules"

      -- Tüm serverlar için capabilities
      vim.lsp.config("*", { capabilities = capabilities })

      -- Server'a özel ayarlar
      vim.lsp.config("vtsls", {
        settings = {
          javascript = { suggest = { autoImports = true } },
          typescript = { suggest = { autoImports = true } },
        },
      })

      vim.lsp.config("kotlin_language_server", {
        cmd_env = {
          ANDROID_HOME = "/opt/android-sdk",
          JAVA_HOME = "/usr/lib/jvm/java-21-openjdk",
          GRADLE_OPTS = "-Dorg.gradle.configuration-cache=false",
        },
        init_options = {
          storagePath = vim.fn.stdpath("data") .. "/kotlin-language-server",
        },
        -- Kotlin LSP hover/completion ayarları
        settings = {
          kotlin = {
            completion = {
              snippets = { enabled = true },
            },
            compiler = {
              jvm = {
                -- Projedeki jvmToolchain(17) ile eşleşmeli
                target = "17",
              },
            },
            -- ÖNEMLİ: androidx/Compose gibi kaynak kodu olmayan
            -- kütüphaneler için KLS .class dosyalarını Kotlin'e
            -- decompile ederek hover dokümantasyonu üretir.
            -- Mavi sembollerin (setContent, Surface, MaterialTheme vb.)
            -- hover'ının null dönmesini bu ayar çözer.
            externalSources = {
              -- KLS kendi URI şemasını kullanarak decompile edilmiş
              -- kaynakları gösterir (kaynak JAR yoksa çalışır)
              useKlsScheme = true,
              -- .class → .kt dönüşümü: hover için Kotlin kodu gösterir
              autoConvertToKotlin = true,
            },
            -- Inlay hint'leri devre dışı bırak (performansı artırır, hover'ı hızlandırır)
            inlayHints = {
              typeHints = { enabled = false },
              parameterHints = { enabled = false },
              chainedHints = { enabled = false },
            },
          },
        },
        -- Gradle root dosyalarını tanı
        root_markers = {
          "settings.gradle",
          "settings.gradle.kts",
          "build.gradle",
          "build.gradle.kts",
          "gradlew",
        },
      })

      vim.lsp.config("html", {
        filetypes = { "html", "htmlangular", "javascriptreact", "typescriptreact" },
        get_language_id = function(bufnr, filetype)
          if filetype == "htmlangular" then
            return "html"
          end
          return filetype
        end,
        settings = {
          css = {
            lint = {
              validProperties = {},
            },
          },
        },
      })

      local function get_angular_core_version(root_dir)
        local package_json = vim.fs.joinpath(root_dir, "package.json")
        if not vim.uv.fs_stat(package_json) then
          return ""
        end
        local f = io.open(package_json, "r")
        if not f then
          return ""
        end
        local content = f:read("*a")
        f:close()
        local ok, json = pcall(vim.json.decode, content)
        if not ok or not json then
          return ""
        end
        local version = (json.dependencies or {})["@angular/core"]
          or (json.devDependencies or {})["@angular/core"]
          or ""
        return version:match("%d+%.%d+%.%d+") or ""
      end

      vim.lsp.config("angularls", {
        cmd = function(dispatchers, config)
          local root_dir = (config and config.root_dir) or vim.fn.getcwd()
          local node_paths = {}

          -- Project node_modules
          local project_node = vim.fs.joinpath(root_dir, "node_modules")
          if vim.uv.fs_stat(project_node) then
            table.insert(node_paths, project_node)
          end

          -- Mason fallback node_modules
          local mason_node = mason_path .. "/packages/angular-language-server/node_modules"
          if vim.uv.fs_stat(mason_node) then
            table.insert(node_paths, mason_node)
          end

          local ts_probe = table.concat(node_paths, ",")
          local ng_probe_paths = {}
          for _, p in ipairs(node_paths) do
            local ng_path = vim.fs.joinpath(p, "@angular/language-server/node_modules")
            if vim.uv.fs_stat(ng_path) then
              table.insert(ng_probe_paths, ng_path)
            else
              table.insert(ng_probe_paths, p)
            end
          end
          local ng_probe = table.concat(ng_probe_paths, ",")

          local cmd = {
            ng_cmd,
            "--stdio",
            "--tsProbeLocations",
            ts_probe,
            "--ngProbeLocations",
            ng_probe,
            "--angularCoreVersion",
            get_angular_core_version(root_dir),
          }
          return vim.lsp.rpc.start(cmd, dispatchers)
        end,
        filetypes = { "typescript", "html", "typescriptreact", "typescript.tsx", "htmlangular" },
        root_markers = { "angular.json", "project.json" },
      })

      vim.lsp.config("tailwindcss", {
        root_dir = function(bufnr, on_dir)
          local util = require("lspconfig.util")
          local fname = vim.api.nvim_buf_get_name(bufnr)
          local root_files = {
            "tailwind.config.js",
            "tailwind.config.cjs",
            "tailwind.config.mjs",
            "tailwind.config.ts",
            "postcss.config.js",
            "postcss.config.cjs",
            "postcss.config.mjs",
            "postcss.config.ts",
          }
          root_files = util.insert_package_json(root_files, "tailwindcss", fname)
          local match = vim.fs.find(root_files, { path = fname, upward = true })[1]
          if match then
            on_dir(vim.fs.dirname(match))
          end
        end,
      })

      -- Pyright: .venv içindeki paketleri resolve et
      vim.lsp.config("pyright", {
        settings = {
          python = {
            analysis = {
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "workspace",
            },
          },
        },
        -- Proje kökündeki .venv'i otomatik bul
        before_init = function(_, config)
          local venv_names = { ".venv", "venv", ".virtualenvs" }
          local root = config.root_dir or vim.fn.getcwd()
          for _, name in ipairs(venv_names) do
            local venv_path = root .. "/" .. name
            local stat = vim.uv.fs_stat(venv_path)
            if stat and stat.type == "directory" then
              local python_bin = venv_path .. "/bin/python"
              if vim.uv.fs_stat(python_bin) then
                config.settings.python = config.settings.python or {}
                config.settings.python.pythonPath = python_bin
                config.settings.python.venvPath = root
                config.settings.python.venv = name
                break
              end
            end
          end
        end,
      })

      -- Mason-lspconfig: kurulu serverları otomatik enable et
      -- jdtls hariç (jdtls = nvim-jdtls ile ayrıca yönetilir)
      require("mason-lspconfig").setup({
        automatic_enable = {
          exclude = { "jdtls" },
        },
      })

      -- LSP Keybinds (only when LSP is attached)
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local opts = { buffer = ev.buf }
          local client = vim.lsp.get_client_by_id(ev.data.client_id)

          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
          vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)

          -- Kotlin LSP için akıllı hover: indexing bitmeden null dönebilir,
          -- bu yüzden retry mekanizması ekliyoruz
          if client and client.name == "kotlin_language_server" then
            vim.keymap.set("n", "K", function()
              -- Önce normal hover'ı dene
              local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
              client:request("textDocument/hover", params, function(err, result)
                if err then
                  vim.notify("KLS hover hatası: " .. tostring(err.message), vim.log.levels.WARN)
                  return
                end
                if result and result.contents then
                  -- Sonuç var, normal göster
                  vim.lsp.buf.hover()
                else
                  -- KLS null döndü → indexing devam ediyor olabilir
                  vim.notify("⏳ KLS indeksleniyor, 1.5s içinde tekrar deneniyor...", vim.log.levels.INFO)
                  vim.defer_fn(function()
                    client:request("textDocument/hover", params, function(_, result2)
                      if result2 and result2.contents then
                        vim.lsp.buf.hover()
                      else
                        vim.notify(
                          "ℹ️ Bu sembol için hover dokümantasyonu yok.\n"
                            .. "KLS indeksleme sürüyorsa biraz bekleyin.",
                          vim.log.levels.WARN
                        )
                      end
                    end, ev.buf)
                  end, 1500)
                end
              end, ev.buf)
            end, opts)
          else
            vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          end
        end,
      })
    end,
  },
}
