-- tests/db_url_spec.lua
-- DSN normalizasyonu, parca birlestirme ve parola maskeleme testleri.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_url_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local url = require("config.db.url")

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
  local same = vim.deep_equal(actual, expected)
  if same then
    check(true, label)
  else
    check(false, label .. " (beklenen: " .. vim.inspect(expected) .. ", gelen: " .. vim.inspect(actual) .. ")")
  end
end

local function parse_kind(input, kind)
  local r = url.parse(input)
  check(r ~= nil and r.kind == kind, "parse " .. input .. " -> " .. kind)
end

parse_kind("postgresql://u:p@h:5432/db", "postgres")
parse_kind("postgres://u@h/db", "postgres")
parse_kind("jdbc:postgresql://h:5432/db", "postgres")
parse_kind("mysql://u:p@h:3306/db", "mysql")
parse_kind("jdbc:mysql://h/db", "mysql")
parse_kind("mariadb://u@h/db", "mysql")
parse_kind("sqlite:///tmp/x.db", "sqlite")
parse_kind("file:./dev.db", "sqlite")
parse_kind("jdbc:sqlite:/tmp/app.db", "sqlite")
eq(
  url.parse("host=127.0.0.1 dbname=testdb user=postgres"),
  { kind = "postgres", dsn = "postgresql://postgres@127.0.0.1/testdb" },
  "libpq key=value"
)
eq((url.to_go_mysql("mysql://u:p@h:3306/db")), "u:p@tcp(h:3306)/db", "mysql uri -> go dsn")
eq(url.mask("postgresql://u:secret@h/db"), "postgresql://u:***@h/db", "parola maskelenir")
check(url.parse("not-a-dsn") == nil, "gecersiz dsn nil")
check(url.parse("") == nil, "bos dsn nil")

-- Uretilen arayuzun kalan parcalari: from_parts / sqlite_path / kenar durumlar.
eq(
  url.from_parts("postgres", { host = "h", port = 5432, user = "u", password = "p", database = "db" }),
  "postgresql://u:p@h:5432/db",
  "parcalardan postgres"
)
eq(
  url.from_parts("mysql", { host = "h", port = 3306, user = "u", database = "db" }),
  "mysql://u@h:3306/db",
  "parcalardan mysql"
)
eq(url.from_parts("sqlite", { path = "db/dev.sqlite3" }), "sqlite://db/dev.sqlite3", "parcalardan sqlite")
check(url.from_parts("postgres", { database = "db" }) == nil, "eksik host nil")
check(url.from_parts("postgres", { host = "h" }) == nil, "eksik database nil")
check(url.from_parts("bogus", { host = "h", database = "db" }) == nil, "bilinmeyen kind nil")

eq(url.sqlite_path("sqlite:///tmp/x.db", "/proj"), "/tmp/x.db", "mutlak sqlite yolu")
eq(url.sqlite_path("file:./dev.db", "/proj"), "/proj/dev.db", "goreli sqlite yolu koke gore")
check(url.sqlite_path("postgresql://h/db", "/proj") == nil, "sqlite olmayan dsn nil")

eq(url.mask("postgresql://user:p@ss:w0rd@h/db"), "postgresql://user:***@h/db", "parolada @ ve : maskelenir")
eq(url.mask("postgresql://u:secret@h/db@x"), "postgresql://u:***@h/db@x", "yoldaki @ maskeyi bozmaz")
eq(url.mask("postgresql://u@h/db"), "postgresql://u@h/db", "parolasiz dsn degismez")
eq(url.mask("postgresql://u:p/ss@h/db"), "postgresql://u:***@h/db", "parolada / maskelenir")
eq(url.mask("postgresql://u:p?ss@h/db"), "postgresql://u:***@h/db", "parolada ? maskelenir")
eq(url.mask("postgresql://u:p#ss@h/db"), "postgresql://u:***@h/db", "parolada # maskelenir")
eq(url.mask("postgresql://h/db?user=a:b@c"), "postgresql://h/db?user=a:b@c", "query icindeki @ maskelenmez")
local sanitized, password = url.without_password("postgresql://u:p%40ss%3Aword@h/db")
eq(sanitized, "postgresql://u@h/db", "without_password argv'den parolayi cikarir")
eq(password, "p@ss:word", "without_password yuzde kodunu cozer")

eq(
  url.parse("postgresql://u@h/db?ssl=true"),
  { kind = "postgres", dsn = "postgresql://u@h/db?sslmode=require" },
  "ssl=true -> sslmode=require"
)
parse_kind("u:p@tcp(h:3306)/db", "mysql")
eq(
  url.parse("host=h dbname=db user=u password=p"),
  { kind = "postgres", dsn = "postgresql://u:p@h/db" },
  "libpq parola"
)
check(url.to_go_mysql("postgresql://h/db") == nil, "postgres dsn go mysql nil")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
