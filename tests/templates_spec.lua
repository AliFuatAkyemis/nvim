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

-- Java: package yok
do
  local lines, cur = newfile("Foo.java")
  check(
    vim.deep_equal(lines, { "public class Foo {", "", "}" }),
    "java: public class + govde satiri"
  )
  check(vim.deep_equal(cur, { 2, 0 }), "java: imlec govde satirinda")
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
