-- tests/sql_align_spec.lua
-- CREATE TABLE kolon hizalama testleri.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/sql_align_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local align = require("config.sql_align")

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

local function eq(actual, expected, label)
  check(actual == expected, label .. " (beklenen: " .. tostring(expected) .. ", gelen: " .. tostring(actual) .. ")")
end

local function eqlines(actual, expected, label)
  local ok = #actual == #expected
  if ok then
    for i = 1, #actual do
      if actual[i] ~= expected[i] then
        ok = false
        break
      end
    end
  end
  check(ok, label)
  if not ok then
    io.write("  beklenen:\n")
    for _, line in ipairs(expected) do
      io.write("    |" .. line .. "|\n")
    end
    io.write("  gelen:\n")
    for _, line in ipairs(actual) do
      io.write("    |" .. line .. "|\n")
    end
  end
end

-- isim + tip + constraint kolonlari hizalanir
local input = {
  "CREATE TABLE rawg_api_keys (",
  "    id BIGSERIAL PRIMARY KEY,",
  "    api_key VARCHAR(128) NOT NULL UNIQUE,",
  "    label VARCHAR(64),",
  "    created_at TIMESTAMP NOT NULL DEFAULT now()",
  ");",
}
eqlines(align.align(input), {
  "CREATE TABLE rawg_api_keys (",
  "    id         BIGSERIAL    PRIMARY KEY,",
  "    api_key    VARCHAR(128) NOT NULL UNIQUE,",
  "    label      VARCHAR(64),",
  "    created_at TIMESTAMP    NOT NULL DEFAULT now()",
  ");",
}, "isim/tip/constraint hizasi")

-- table-level constraint hizalamayi bozmaz ve dokunulmaz
eqlines(
  align.align({
    "CREATE TABLE t (",
    "    a BIGINT NOT NULL,",
    "    b BIGINT NOT NULL,",
    "    c TEXT,",
    "    PRIMARY KEY (a, b)",
    ");",
  }),
  {
    "CREATE TABLE t (",
    "    a BIGINT NOT NULL,",
    "    b BIGINT NOT NULL,",
    "    c TEXT,",
    "    PRIMARY KEY (a, b)",
    ");",
  },
  "table-level PK korunur"
)

-- cok satirli kolon tanimi hizaya katilmaz
eqlines(
  align.align({
    "CREATE TABLE u (",
    "    id BIGINT NOT NULL,",
    "    note TEXT",
    "        CHECK (note <> ''),",
    "    created_at TIMESTAMP NOT NULL",
    ");",
  }),
  {
    "CREATE TABLE u (",
    "    id         BIGINT    NOT NULL,",
    "    note TEXT",
    "        CHECK (note <> ''),",
    "    created_at TIMESTAMP NOT NULL",
    ");",
  },
  "cok satirli tanim atlanir"
)

-- CREATE TABLE disi icerik degismez
eqlines(
  align.align({
    "SELECT id, name FROM users;",
    "",
    "ALTER TABLE x ADD COLUMN y BIGINT;",
  }),
  {
    "SELECT id, name FROM users;",
    "",
    "ALTER TABLE x ADD COLUMN y BIGINT;",
  },
  "DDL disi dokunulmaz"
)

-- iki kez uygulamak ayni sonucu verir
local once = align.align(input)
eqlines(align.align(once), once, "idempotent")

-- yorum iceren satir hizalanmaz, digerleri hizalanir
eqlines(
  align.align({
    "CREATE TABLE c (",
    "    id BIGINT, -- pk",
    "    long_name TEXT",
    ");",
  }),
  {
    "CREATE TABLE c (",
    "    id BIGINT, -- pk",
    "    long_name TEXT",
    ");",
  },
  "yorumlu satir korunur"
)

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
