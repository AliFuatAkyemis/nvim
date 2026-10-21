-- Yeni dosya sablonlari.
-- Sadece BufNewFile ile, yani dosya ilk kez olusturulurken calisir.
-- Mevcut dosyalara ve dolu buffer'lara dokunmaz.

local M = {}

local function shiftwidth_indent()
  if vim.o.expandtab then
    local sw = vim.fn.shiftwidth()
    if sw < 1 then
      sw = 4
    end
    return string.rep(" ", sw)
  end
  return "\t"
end

-- my-class.java -> MyClass, 2foo.java -> _2foo
local function pascal_case(stem)
  local words = {}
  for word in stem:gmatch("[%w]+") do
    words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
  end
  local name = table.concat(words)
  if name == "" then
    name = "Main"
  end
  if name:match("^%d") then
    name = "_" .. name
  end
  return name
end

-- src/main/java/com/example/Foo.java -> com.example
local function java_package(path)
  local normalized = path:gsub("\\", "/")
  local rel = normalized:match("src/main/java/(.+)/[^/]+$")
    or normalized:match("src/test/java/(.+)/[^/]+$")
  if not rel then
    return nil
  end
  return (rel:gsub("/", "."))
end

local function header_guard(path)
  return vim.fn.fnamemodify(path, ":t"):upper():gsub("[^%w]", "_")
end

local function is_pristine(buf)
  if vim.bo[buf].modified then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return #lines == 1 and lines[1] == ""
end

local function apply(buf, lines, cursor)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if vim.api.nvim_get_current_buf() == buf then
    vim.api.nvim_win_set_cursor(0, cursor)
  end
end

local function java_template(path)
  local lines = {}
  local package = java_package(path)
  if package then
    lines[#lines + 1] = "package " .. package .. ";"
    lines[#lines + 1] = ""
  end

  local class_name = pascal_case(vim.fn.fnamemodify(path, ":t:r"))
  local class_line = #lines + 1
  lines[#lines + 1] = "public class " .. class_name .. " {"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "}"
  return lines, { class_line + 1, 0 }
end

local function c_template()
  local indent = shiftwidth_indent()
  return {
    "#include <stdio.h>",
    "",
    "int main(void) {",
    indent .. "return 0;",
    "}",
  }, { 4, #indent }
end

local function cpp_template()
  local indent = shiftwidth_indent()
  return {
    "#include <iostream>",
    "",
    "int main() {",
    indent .. "return 0;",
    "}",
  }, { 4, #indent }
end

local function header_template(path)
  local guard = header_guard(path)
  return {
    "#ifndef " .. guard,
    "#define " .. guard,
    "",
    "#endif",
  }, { 3, 0 }
end

local function csharp_namespace(path)
  local dir = vim.fn.fnamemodify(path, ":p:h")
  local project = vim.fs.find(function(name)
    return name:match("%.csproj$") ~= nil
  end, { path = dir, upward = true, type = "file" })[1]
  if not project then
    return nil
  end

  local function segment(value)
    local clean = value:gsub("[^%w_]", "_")
    if clean == "" then
      return nil
    end
    if clean:match("^%d") then
      clean = "_" .. clean
    end
    return clean
  end

  local root = vim.fn.fnamemodify(project, ":h")
  local parts = { segment(vim.fn.fnamemodify(project, ":t:r")) }
  local rel = dir:gsub("\\", "/"):sub(#root:gsub("\\", "/") + 1):gsub("^/", "")
  for part in rel:gmatch("[^/]+") do
    parts[#parts + 1] = segment(part)
  end

  local out = {}
  for _, part in ipairs(parts) do
    if part then
      out[#out + 1] = part
    end
  end
  if #out == 0 then
    return nil
  end
  return table.concat(out, ".")
end

local function csharp_template(path)
  local indent = shiftwidth_indent()
  local class_name = pascal_case(vim.fn.fnamemodify(path, ":t:r"))
  local lines = {}
  local namespace = csharp_namespace(path)
  if namespace then
    lines[#lines + 1] = "namespace " .. namespace .. ";"
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "public class " .. class_name
  lines[#lines + 1] = "{"
  lines[#lines + 1] = indent .. "public static void Main(string[] args)"
  lines[#lines + 1] = indent .. "{"
  lines[#lines + 1] = ""
  lines[#lines + 1] = indent .. "}"
  lines[#lines + 1] = "}"
  return lines, { #lines - 2, 0 }
end

local function go_template()
  return {
    "package main",
    "",
    "func main() {",
    "",
    "}",
  }, { 4, 0 }
end

local function kotlin_template()
  return {
    "fun main() {",
    "",
    "}",
  }, { 2, 0 }
end

local function rust_template()
  return {
    "fn main() {",
    "",
    "}",
  }, { 2, 0 }
end

local function php_template()
  return {
    "<?php",
    "",
  }, { 2, 0 }
end

local templates = {
  java = java_template,
  c = c_template,
  cpp = cpp_template,
  header = header_template,
  csharp = csharp_template,
  go = go_template,
  kotlin = kotlin_template,
  rust = rust_template,
  php = php_template,
}

local extension_map = {
  java = "java",
  c = "c",
  h = "header",
  hpp = "header",
  hh = "header",
  cpp = "cpp",
  cc = "cpp",
  cxx = "cpp",
  cs = "csharp",
  go = "go",
  kt = "kotlin",
  rs = "rust",
  php = "php",
}

vim.api.nvim_create_autocmd("BufNewFile", {
  group = vim.api.nvim_create_augroup("FileTemplates", { clear = true }),
  pattern = {
    "*.java",
    "*.c",
    "*.h",
    "*.hpp",
    "*.hh",
    "*.cpp",
    "*.cc",
    "*.cxx",
    "*.cs",
    "*.go",
    "*.kt",
    "*.rs",
    "*.php",
  },
  callback = function(ev)
    if not is_pristine(ev.buf) then
      return
    end

    local path = vim.api.nvim_buf_get_name(ev.buf)
    local extension = path:match("%.([%w]+)$")
    local kind = extension and extension_map[extension:lower()]
    local build = kind and templates[kind]
    if not build then
      return
    end

    local lines, cursor = build(path)
    apply(ev.buf, lines, cursor)
  end,
})

return M
