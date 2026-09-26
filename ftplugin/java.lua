local jdtls = require("jdtls")

-- Helper to find the home directory
local home = os.getenv("HOME")
local mason_path = home .. "/.local/share/nvim/mason/packages"

-- JDTLS installation path
local jdtls_path = mason_path .. "/jdtls"

-- Find the launcher jar
local launcher_jar = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar", true)
if type(launcher_jar) == "table" then
  launcher_jar = launcher_jar[1]
end

-- Find the configuration path (linux)
local config_path = jdtls_path .. "/config_linux"

-- Find Lombok
local lombok_jar = vim.fn.getcwd() .. "/lib/lombok.jar"
if vim.fn.filereadable(lombok_jar) == 0 then
  lombok_jar = vim.fn.stdpath("config") .. "/lib/lombok.jar"
end
if vim.fn.filereadable(lombok_jar) == 0 then
  lombok_jar = jdtls_path .. "/lombok.jar"
end

-- Workspace data path
local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
local workspace_path = home .. "/.local/share/nvim/jdtls-workspace/" .. project_name

-- Ensure workspace directory exists (parent)
vim.fn.mkdir(home .. "/.local/share/nvim/jdtls-workspace", "p")

-- If we don't have the essentials, don't start to avoid error spam
if not launcher_jar or launcher_jar == "" or vim.fn.filereadable(launcher_jar) == 0 then
  print("JDTLS: Launcher jar not found. Is jdtls installed in Mason?")
  return
end

local config = {
  cmd = {
    "java",
    "-Declipse.application=org.eclipse.jdt.ls.core.id1",
    "-Dosgi.bundles.defaultStartLevel=4",
    "-Declipse.product=org.eclipse.jdt.ls.core.product",
    "-Dlog.protocol=true",
    "-Dlog.level=ALL",
    "-Xms1g",
    "--add-modules=ALL-SYSTEM",
    "--add-opens",
    "java.base/java.util=ALL-UNNAMED",
    "--add-opens",
    "java.base/java.lang=ALL-UNNAMED",
    -- Add Lombok Support
    "-javaagent:" .. lombok_jar,
    "-jar",
    launcher_jar,
    "-configuration",
    config_path,
    "-data",
    workspace_path,
  },
  root_dir = jdtls.setup.find_root({ ".git", "gradlew", "mvnw", "pom.xml" }),
  settings = {
    java = {
      configuration = {
        updateBuildConfiguration = "interactive",
        runtimes = {
          {
            name = "JavaSE-21",
            path = "/usr/lib/jvm/java-21-openjdk",
            default = true,
          },
        },
      },
      completion = {
        favoriteStaticMembers = {
          "org.junit.Assert.*",
          "org.junit.Assume.*",
          "org.junit.jupiter.api.Assertions.*",
          "org.junit.jupiter.api.Assumptions.*",
          "org.mockito.Mockito.*",
        },
      },
    },
  },
  init_options = {
    bundles = vim.fn.glob(
      mason_path .. "/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
      true,
      true
    ),
    extendedClientCapabilities = {
      classFileContentsSupport = true,
      generateToStringPromptSupport = true,
      hashCodeEqualsPromptSupport = true,
      advancedOrganizeImportsSupport = true,
      resolveAdditionalTextEditsSupport = true,
      advancedGenerateAccessorsSupport = true,
      overrideMethodsSupport = true,
    },
  },
}

-- Add test bundles
local test_bundles = vim.fn.glob(mason_path .. "/java-test/extension/server/*.jar", true, true)
if #test_bundles > 0 then
  vim.list_extend(config.init_options.bundles, test_bundles)
end

-- Start or attach
jdtls.start_or_attach(config)

-- Keymaps
local opts = { buffer = true }
vim.keymap.set("n", "<leader>jo", jdtls.organize_imports, vim.tbl_extend("force", opts, { desc = "Organize imports" }))
vim.keymap.set("n", "<leader>jc", jdtls.extract_constant, vim.tbl_extend("force", opts, { desc = "Extract constant" }))
vim.keymap.set("n", "<leader>jv", jdtls.extract_variable, vim.tbl_extend("force", opts, { desc = "Extract variable" }))
vim.keymap.set("n", "<leader>jt", jdtls.test_class, vim.tbl_extend("force", opts, { desc = "Test class" }))
vim.keymap.set("n", "<leader>jT", jdtls.test_nearest_method, vim.tbl_extend("force", opts, { desc = "Test method" }))
vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Show documentation" }))
vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
