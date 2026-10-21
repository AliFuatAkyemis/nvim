-- tests/templates_spec.lua
-- Yeni dosya sablonlari icin headless entegrasyon testi.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/templates_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.expandtab = true
vim.opt.shiftwidth = 4

require("config.templates")

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

local failures, total = 0, 0
local function check(cond, label)
  total = total + 1
  if cond then
    io.write("ok   - " .. label .. "\n")
  else
    failures = failures + 1
    io.write("FAIL - " .. label .. "\n")
  end
end

local function newfile(relpath)
  local path = tmpdir .. "/" .. relpath
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.api.nvim_win_get_cursor(0)
end

-- Java: package yok (tekil dosya) -> main de eklenir
do
  local lines, cur = newfile("Foo.java")
  check(
    vim.deep_equal(lines, {
      "public class Foo {",
      "    public static void main(String[] args) {",
      "",
      "    }",
      "}",
    }),
    "java: tekil dosyada class + main"
  )
  check(vim.deep_equal(cur, { 3, 0 }), "java: imlec main govdesinde")
end

-- Java: src/main/java altinda package tespiti
do
  local lines = newfile("proje/src/main/java/com/example/Foo.java")
  check(
    vim.deep_equal(lines, {
      "package com.example;",
      "",
      "public class Foo {",
      "",
      "}",
    }),
    "java: package yoldan turetilir"
  )
end

-- Java: dosya adi -> class adi
do
  local lines = newfile("my-class.java")
  check(lines[1] == "public class MyClass {", "java: dosya adi PascalCase olur")
end

-- C
do
  local lines, cur = newfile("main.c")
  check(
    vim.deep_equal(lines, {
      "#include <stdio.h>",
      "",
      "int main(void) {",
      "    return 0;",
      "}",
    }),
    "c: stdio + main iskeleti"
  )
  check(cur[1] == 4, "c: imlec main govdesinde")
end

-- C++
do
  local lines = newfile("main.cpp")
  check(
    vim.deep_equal(lines, {
      "#include <iostream>",
      "",
      "int main() {",
      "    return 0;",
      "}",
    }),
    "cpp: iostream + main iskeleti"
  )
end

-- Header
do
  local lines = newfile("my-file.hpp")
  check(
    vim.deep_equal(lines, {
      "#ifndef MY_FILE_HPP",
      "#define MY_FILE_HPP",
      "",
      "#endif",
    }),
    "header: include guard"
  )
end

-- Python: bos kalmali
do
  local lines = newfile("script.py")
  check(vim.deep_equal(lines, { "" }), "python: sablon yok")
end

-- C#
do
  local lines, cur = newfile("Program.cs")
  check(
    vim.deep_equal(lines, {
      "public class Program",
      "{",
      "    public static void Main(string[] args)",
      "    {",
      "",
      "    }",
      "}",
    }),
    "csharp: class + Main iskeleti"
  )
  check(cur[1] == 5, "csharp: imlec Main govdesinde")
end

-- Go
do
  local lines = newfile("main.go")
  check(
    vim.deep_equal(lines, {
      "package main",
      "",
      "func main() {",
      "",
      "}",
    }),
    "go: package main + func main"
  )
end

-- Kotlin
do
  local lines = newfile("Main.kt")
  check(vim.deep_equal(lines, { "fun main() {", "", "}" }), "kotlin: fun main")
end

-- Rust
do
  local lines = newfile("main.rs")
  check(vim.deep_equal(lines, { "fn main() {", "", "}" }), "rust: fn main")
end

-- PHP
do
  local lines, cur = newfile("index.php")
  check(vim.deep_equal(lines, { "<?php", "" }), "php: <?php basligi")
  check(cur[1] == 2, "php: imlec basligin altinda")
end

-- Ruby: bos kalmali
do
  local lines = newfile("script.rb")
  check(vim.deep_equal(lines, { "" }), "ruby: sablon yok")
end

-- C#: csproj bazli namespace
do
  local proj = tmpdir .. "/nsproj"
  vim.fn.mkdir(proj, "p")
  vim.fn.writefile({ '<Project Sdk="Microsoft.NET.Sdk" />' }, proj .. "/MyApp.csproj")

  local lines = newfile("nsproj/Services/Foo.cs")
  check(lines[1] == "namespace MyApp.Services;", "csharp: namespace csproj + klasorden")
  check(lines[2] == "", "csharp: namespace sonrasi bos satir")
  check(lines[3] == "public class Foo", "csharp: class namespace'ten sonra")

  local root_lines = newfile("nsproj/Bar.cs")
  check(root_lines[1] == "namespace MyApp;", "csharp: kok dosyada csproj adi")

  -- En yakin csproj kazanir
  local nested = proj .. "/Modules/Api"
  vim.fn.mkdir(nested, "p")
  vim.fn.writefile({ '<Project Sdk="Microsoft.NET.Sdk" />' }, nested .. "/Api.csproj")
  local nested_lines = newfile("nsproj/Modules/Api/Baz.cs")
  check(nested_lines[1] == "namespace Api;", "csharp: en yakin csproj kullanilir")
end

-- Neo-tree tarzi dogrudan dosya olusturma (file_added)
do
  local path = tmpdir .. "/neotree/Widget.java"
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({}, path)
  require("config.templates").seed_file(path)
  check(
    vim.deep_equal(vim.fn.readfile(path), {
      "public class Widget {",
      "    public static void main(String[] args) {",
      "",
      "    }",
      "}",
    }),
    "seed_file: bos dosyaya sablon yazar"
  )
end

-- seed_file dolu dosyaya dokunmaz
do
  local path = tmpdir .. "/neotree/Existing.java"
  vim.fn.writefile({ "int keep = 1;" }, path)
  require("config.templates").seed_file(path)
  check(
    vim.deep_equal(vim.fn.readfile(path), { "int keep = 1;" }),
    "seed_file: dolu dosyaya dokunmaz"
  )
end

-- seed_file sablonu olmayan uzantiyi bos birakir
do
  local path = tmpdir .. "/neotree/notes.txt"
  vim.fn.writefile({}, path)
  require("config.templates").seed_file(path)
  check(vim.fn.getfsize(path) == 0, "seed_file: sablonsuz uzanti bos kalir")
end

-- Mevcut dosya korunmali
do
  local path = tmpdir .. "/existing/main.c"
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ "int keep = 1;" }, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  check(
    vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "int keep = 1;" }),
    "mevcut dosya degismez"
  )
end

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
