# Generic SQL DB Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Herhangi bir dil/framework projesinde `.sql` dosyası için DB bağlantısını otomatik tespit edip doğru LSP'yi, tip completion'ını ve syntax'ı devreye almak.

**Architecture:** `lua/config/db/` altında tek bir tespit çekirdeği (`detect.lua`) + saf adaptörler. DB türüne göre `root_dir` kapılamasıyla tek LSP attach edilir: PostgreSQL → pgls, MySQL/SQLite → sqls. Tipler PostgreSQL'de canlı katalogdan, diğerlerinde statik listeden gelir.

**Tech Stack:** Neovim 0.12 Lua, nvim-cmp, nvim-lspconfig, Mason (postgres-language-server, sqls), psql, sqlfluff (formatter, değişmiyor).

**Spec:** `docs/superpowers/specs/2026-11-14-generic-sql-db-detection-design.md`

## Global Constraints

- Lua 5.1 / LuaJIT (Neovim runtime). `vim.tbl_*`, `vim.fs`, `vim.system` kullanılabilir.
- Stil: `stylua` — 2 boşluk, çift tırnak, 120 sütun, LF.
- Test düzeni: headless spec, `nvim --headless -u NONE -l tests/<spec>.lua`; `ok/FAIL` satırları, sonda `N/M passed`, hata varsa `os.exit(1)`. Her yeni spec, `tests/comments_spec.lua` içindeki `check`/`eq` yardımcılarını ve `runtimepath` prepend bloğunu kopyalar.
- Alt süreçler yalnızca liste argümanıyla (`vim.system`), shell string yok.
- Proje dosyalarına yazılmaz; yalnızca okunur.
- Tespit edilemeyen/bozuk girdi `nil` döner; hata fırlatmaz.
- Parola hiçbir log/notify/komut çıktısında açık görünmez.
- Tip kaynağı yalnızca DDL bağlamında çalışır (`CREATE TABLE ... (` içi, `ALTER TABLE ... ADD COLUMN` sonrası).
- cmp kaynak adı: `db_types`. Öncelik: 900.
- Komut adları: `:DbDetectInfo`, `:DbDetectRefresh`, `:DbTypesRefresh`.
- Formatter davranışı değişmez (conform + sqlfluff).

## Review Focus

- **Bozuk/özel karakterli DSN:** `user:p@ss:w0rd@host:5432/db` gibi parolalar parse'ı patlatmamalı; `mask()` doğru çalışmalı.
- **Config var, DB erişilemez:** psql çağrısı UI'yı bloklamamalı; 30 sn backoff; statik tipe düşmeli.
- **Proje dışı düz `.sql`:** config yokken hata/uyarı fırtınası olmamalı; yalnızca bir kez bilgi, snippet + statik tip.
- **Çoklu aday:** env, `.env`, Spring aynı anda varsa sıra deterministik olmalı (env > `.env` > framework).
- **Kök dışı okuma:** symlink/`../` ile proje kökü dışındaki dosyalar okunmamalı.

---

### Task 1: DSN normalizasyonu

**Files:**
- Create: `lua/config/db/url.lua`
- Test: `tests/db_url_spec.lua`

**Interfaces:**
- Produces:
  - `M.parse(input: string): { kind: "postgres"|"mysql"|"sqlite", dsn: string }|nil`
  - `M.from_parts(kind: string, parts: table): string|nil` — `parts = { host, port, user, password, database, path }`
  - `M.mask(dsn: string): string`
  - `M.to_go_mysql(dsn: string): string|nil`
  - `M.sqlite_path(dsn: string, root: string): string|nil`

- [ ] **Step 1: Write the failing test**

`tests/db_url_spec.lua` — mevcut spec başlığını kopyala, sonra:

```lua
local url = require("config.db.url")

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
eq(url.parse("host=127.0.0.1 dbname=testdb user=postgres"), { kind = "postgres", dsn = "postgresql://postgres@127.0.0.1/testdb" }, "libpq key=value")
eq((url.to_go_mysql("mysql://u:p@h:3306/db")), "u:p@tcp(h:3306)/db", "mysql uri -> go dsn")
eq(url.mask("postgresql://u:secret@h/db"), "postgresql://u:***@h/db", "parola maskelenir")
check(url.parse("not-a-dsn") == nil, "gecersiz dsn nil")
check(url.parse("") == nil, "bos dsn nil")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_url_spec.lua`
Expected: FAIL `module 'config.db.url' not found`

- [ ] **Step 3: Implement `lua/config/db/url.lua`**

`parse` sırası: doğrudan şema (`postgres`, `postgresql`, `mysql`, `mariadb`, `sqlite`, `file:`) → `jdbc:` sıyır → libpq `=` formu → Go MySQL DSN (`@tcp(`). `from_parts`, parçalardan URI kurar; eksik zorunlu alanda `nil`. `mask`, authority içindeki `:parola@` bölümünü `:***@` yapar. `to_go_mysql`, URI'yi `user[:pass]@tcp(host[:port])/database[?params]` biçimine çevirir.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_url_spec.lua`
Expected: `... passed`, çıkış kodu 0

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/url.lua tests/db_url_spec.lua
git commit -m "feat(db): add DSN normalization helpers"
```

---

### Task 2: Proje kökü

**Files:**
- Create: `lua/config/db/project.lua`
- Test: `tests/db_project_spec.lua`

**Interfaces:**
- Produces: `M.root(bufnr: integer): string|nil` — en yakın işaret dizini; yoksa buffer dosyasının dizini; dosya adı boşsa `nil`.

- [ ] **Step 1: Write the failing test**

Test, `vim.fn.tempname()` altında geçici ağaç kurar: `proj/pom.xml`, `proj/src/main/x.sql` → kök `proj`. Ayrıca `node/p/package.json`, `solo/x.sql` (işaret yok) → `solo`.

```lua
local project = require("config.db.project")
-- ... tempname ile ağaç kur ...
eq(project.root(buf_with("proj/src/main/x.sql")), proj, "pom.xml kok")
eq(project.root(buf_with("node/p/y.sql")), nodep, "package.json kok")
eq(project.root(buf_with("solo/z.sql")), solo, "isaretsiz dosya dizini")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_project_spec.lua`
Expected: FAIL module not found

- [ ] **Step 3: Implement `project.lua`**

`ROOT_MARKERS` spec'teki liste. `vim.fs.root(bufnr, ROOT_MARKERS)`; `nil` ise `vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))`; boş ad ise `nil`. `M.markers` alanını testler için açık bırak.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_project_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/project.lua tests/db_project_spec.lua
git commit -m "feat(db): detect project root"
```

---

### Task 3: Minimal YAML okuyucu

**Files:**
- Create: `lua/config/db/yaml.lua`
- Test: `tests/db_yaml_spec.lua`

**Interfaces:**
- Produces: `M.read(path: string): table|nil` — iç içe Lua tablosu; yorum/a boş satır atlanır; skalerler string.
- Produces: `M.parse(text: string): table`.

- [ ] **Step 1: Write the failing test**

```lua
local yaml = require("config.db.yaml")
local t = yaml.parse([[
spring:
  datasource:
    url: jdbc:postgresql://h:5432/db
    username: postgres
  profiles:
    active: dev
]])
eq(t.spring.datasource.url, "jdbc:postgresql://h:5432/db", "ic ice anahtar")
eq(t.spring.datasource.username, "postgres", "kardes anahtar")
eq(t.spring.profiles.active, "dev", "ucuncu seviye")
eq(yaml.parse("a:\n  b: 'x' # yorum").a.b, "x", "tirnak ve yorum")
check(yaml.parse("bozuk: [") ~= nil, "bozuk yaml nil dondurmez")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_yaml_spec.lua`
Expected: FAIL module not found

- [ ] **Step 3: Implement `yaml.lua`**

Girinti yığını (`{indent, key}`) ile anahtar yolu kur; değer boşsa yeni seviye, doluysa skaler. Tırnakları ve satır sonu `#` yorumunu temizle. Liste (`- `) desteği yok; o satırlar atlanır. `read` `pcall(io.open)` ile güvenli.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_yaml_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/yaml.lua tests/db_yaml_spec.lua
git commit -m "feat(db): add minimal YAML reader"
```

---

### Task 4: env ve dotenv adaptörleri

**Files:**
- Create: `lua/config/db/fs.lua`
- Create: `lua/config/db/adapters/env.lua`
- Create: `lua/config/db/adapters/dotenv.lua`
- Test: `tests/db_adapters_env_spec.lua`

**Interfaces:**
- Her adaptör: `M.detect(root: string): { kind: string, dsn: string, source: string }|nil`
- `dotenv.lookup(name: string, root: string): string|nil` — sonraki adaptörler (prisma, django) kullanır.
- `fs.read(path: string, root: string): string|nil` — kök dışına çıkan yolu (symlink/`..`) reddeder.

- [ ] **Step 1: Write the failing test**

```lua
local env = require("config.db.adapters.env")
local dotenv = require("config.db.adapters.dotenv")
local fs = require("config.db.fs")

local root = vim.fn.getcwd()
vim.env.DATABASE_URL = "postgresql://u:p@h:5432/db"
eq(env.detect(root).kind, "postgres", "env DATABASE_URL")
eq(env.detect(root).source, "env:DATABASE_URL", "env kaynak etiketi")
vim.env.DATABASE_URL = nil

-- fixture: dotenv/.env.local icinde DATABASE_URL=mysql://u:p@h/db
eq(dotenv.detect(dotenv_fixture).kind, "mysql", "dotenv DATABASE_URL")
eq(dotenv.lookup("DATABASE_URL", dotenv_fixture), "mysql://u:p@h/db", "dotenv lookup")
```

Fixture: `tests/fixtures/db/dotenv/.env.local` (yukarıdaki satır), `.env` içinde farklı bir URL (`.env.local` kazanmalı).

Ek test: kök dışını gösteren symlink için `fs.read(path, root) == nil`.

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_adapters_env_spec.lua`
Expected: FAIL module not found

- [ ] **Step 3: Implement adaptörler**

`env`: sırayla `DATABASE_URL`, `DB_URL`, `POSTGRES_URL`, `MYSQL_URL`; yoksa `PGHOST`+`PGDATABASE` (port 5432, kullanıcı `vim.env.USER`), yoksa `MYSQL_HOST`+`MYSQL_DATABASE` (port 3306) parçalarından DSN. `source` = `"env:<KEY>"` / `"env:PG*"` / `"env:MYSQL_*"`.

`dotenv`: dosya sırası `.env.local`, `.env.development`, `.env.dev`, `.env`; ilk bulunan değer. `export ` öneki, tek/çift tırnak, `${VAR}` ve `${VAR:default}` çözümü. `lookup` aynı sırayı kullanır. Tüm okumalar `fs.read` ile; `fs.read` `vim.fs.normalize` + `vim.uv.fs_realpath` sonrası `root` ile `vim.startswith` kontrolü yapar ve kök dışını reddeder (`nil`).

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_adapters_env_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/fs.lua lua/config/db/adapters/env.lua lua/config/db/adapters/dotenv.lua tests/db_adapters_env_spec.lua tests/fixtures/db/dotenv
git commit -m "feat(db): add env and dotenv adapters"
```

---

### Task 5: Spring adaptörü

**Files:**
- Create: `lua/config/db/adapters/spring.lua`
- Test: `tests/db_adapters_spring_spec.lua`
- Fixtures: `tests/fixtures/db/spring_props/src/main/resources/application.properties`, `tests/fixtures/db/spring_yml/src/main/resources/application.yml`

**Interfaces:**
- Produces: `M.detect(root): conn|nil`; `M.read_properties(path): table` (test edilebilir).

- [ ] **Step 1: Write the failing test**

```lua
local spring = require("config.db.adapters.spring")
eq(spring.detect(props_root).kind, "postgres", "properties jdbc postgresql")
eq(spring.detect(props_root).dsn, "postgresql://postgres:secret@127.0.0.1:5432/expensetracker", "properties dsn")
eq(spring.detect(yml_root).kind, "mysql", "yml jdbc mysql")
eq(spring.read_properties(path).username, "postgres", "properties okuma")
```

Fixture properties:

```
spring.datasource.url=jdbc:postgresql://127.0.0.1:5432/expensetracker
spring.datasource.username=postgres
spring.datasource.password=secret
```

URL'de kullanıcı bilgisi yoksa `username`/`password` prop'ları DSN'e eklenir.

Fixture yml:

```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/app
    username: root
    password: root
```

Ek test: `${DB_NAME:fallback}` placeholder çözümü.

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_adapters_spring_spec.lua`
Expected: FAIL module not found

- [ ] **Step 3: Implement `spring.lua`**

`application.properties`, `.yml`, `.yaml`, `application-*` varyantlarını sırala (base önce, sonra alfabetik). Dosyaları `fs.read(path, root)` ile oku; yml için `yaml.parse`. Değerleri birleştir; `url`/`hikari.jdbc-url` + username/password ile `url.from_parts` veya `url.parse`. Placeholder çözümü `env`/`dotenv.lookup` ile. `source = "spring:<relative path>"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_adapters_spring_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/adapters/spring.lua tests/db_adapters_spring_spec.lua tests/fixtures/db/spring_props tests/fixtures/db/spring_yml
git commit -m "feat(db): add Spring Boot datasource adapter"
```

---

### Task 6: Rails adaptörü

**Files:**
- Create: `lua/config/db/adapters/rails.lua`
- Test: `tests/db_adapters_rails_spec.lua`
- Fixture: `tests/fixtures/db/rails/config/database.yml`

**Interfaces:**
- Produces: `M.detect(root): conn|nil`.

- [ ] **Step 1: Write the failing test**

Fixture:

```yaml
development:
  adapter: postgresql
  host: localhost
  port: 5432
  database: app_dev
  username: postgres
  password: secret
test:
  adapter: mysql2
  database: app_test
```

```lua
local rails = require("config.db.adapters.rails")
eq(rails.detect(root).kind, "postgres", "development postgres secilir")
eq(rails.detect(root).dsn, "postgresql://postgres:secret@localhost:5432/app_dev", "rails dsn")
```

Ek test: `url:` dolu olduğunda parçalar yerine URL kullanılır; adapter `sqlite3` + `database: db/development.sqlite3` → sqlite yolu köke göre mutlak.

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_adapters_rails_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement `rails.lua`**

`yaml.parse(fs.read(root .. "/config/database.yml", root))`; `development` → ilk anahtar. `url` varsa `url.parse`; yoksa `adapter` eşlemesi (`postgresql`, `mysql2`, `trilogy`, `sqlite3`) + `url.from_parts`. ERB (`<%=`) içeren değer varsa `nil`.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_adapters_rails_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/adapters/rails.lua tests/db_adapters_rails_spec.lua tests/fixtures/db/rails
git commit -m "feat(db): add Rails database.yml adapter"
```

---

### Task 7: Prisma adaptörü

**Files:**
- Create: `lua/config/db/adapters/prisma.lua`
- Test: `tests/db_adapters_prisma_spec.lua`
- Fixtures: `tests/fixtures/db/prisma/prisma/schema.prisma` (literal sqlite), `tests/fixtures/db/prisma_env/prisma/schema.prisma` (`env("SPECIAL_DB_URL")`) + `.env.local`

**Interfaces:**
- Produces: `M.detect(root): conn|nil`.

- [ ] **Step 1: Write the failing test**

```lua
local prisma = require("config.db.adapters.prisma")
eq(prisma.detect(sqlite_root).kind, "sqlite", "prisma sqlite")
eq(prisma.detect(sqlite_root).dsn, "sqlite://" .. sqlite_root .. "/prisma/dev.db", "file: yolu koke gore")
eq(prisma.detect(env_root).kind, "postgres", "prisma env(...) cozulur")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_adapters_prisma_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement `prisma.lua`**

`fs.read(root .. "/prisma/schema.prisma", root)` içinden `datasource <name> { ... }` bloğunu bul; `provider` ve `url` satırlarını regex ile al. `env("X")` → `dotenv.lookup("X", root)` (yoksa `vim.env.X`). Literal `file:` değerini `url.parse` + `url.sqlite_path` ile köke göre çöz; adaptör DSN'i mutlak `sqlite://<root>/<path>` biçiminde döndürür. `provider` ile şema çelişirse provider kazanır.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_adapters_prisma_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/adapters/prisma.lua tests/db_adapters_prisma_spec.lua tests/fixtures/db/prisma tests/fixtures/db/prisma_env
git commit -m "feat(db): add Prisma schema adapter"
```

---

### Task 8: Django adaptörü

**Files:**
- Create: `lua/config/db/adapters/django.lua`
- Test: `tests/db_adapters_django_spec.lua`
- Fixtures: `tests/fixtures/db/django/settings.py` (DATABASES sözlüğü), `tests/fixtures/db/django_env/settings.py` (DATABASE_URL satırı)

**Interfaces:**
- Produces: `M.detect(root): conn|nil`.

- [ ] **Step 1: Write the failing test**

Settings fixture:

```python
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "appdb",
        "USER": "postgres",
        "PASSWORD": "secret",
        "HOST": "127.0.0.1",
        "PORT": "5432",
    }
}
```

```lua
local django = require("config.db.adapters.django")
eq(django.detect(root).kind, "postgres", "django engine")
eq(django.detect(root).dsn, "postgresql://postgres:secret@127.0.0.1:5432/appdb", "django dsn")
-- sqlite fixture: NAME = BASE_DIR / "db.sqlite3"
eq(django.detect(sqlite_root).kind, "sqlite", "django sqlite")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_adapters_django_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement `django.lua`**

`settings.py` ve bir alt seviye `*/settings.py` ara; dosyaları `fs.read` ile oku. Önce `DATABASE_URL = "..."` satırını dene. Yoksa `DATABASES = {` bloğunda ilk `"default"` girdisini regex ile çıkar: `ENGINE`, `NAME`, `USER`, `PASSWORD`, `HOST`, `PORT`. `ENGINE` sonundaki `postgresql|mysql|sqlite3` türü belirler. `NAME = BASE_DIR / "..."` → köke göre yol. Karmaşık ifadelerde `nil`.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_adapters_django_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/adapters/django.lua tests/db_adapters_django_spec.lua tests/fixtures/db/django tests/fixtures/db/django_env
git commit -m "feat(db): add Django settings adapter"
```

---

### Task 9: Compose adaptörü ve adaptör kaydı

**Files:**
- Create: `lua/config/db/adapters/compose.lua`
- Create: `lua/config/db/adapters/init.lua`
- Test: `tests/db_adapters_compose_spec.lua`
- Fixture: `tests/fixtures/db/compose/docker-compose.yml`

**Interfaces:**
- `compose.detect(root): conn|nil`
- `init.order: string[]` = `{ "env", "dotenv", "spring", "rails", "prisma", "django", "compose" }`
- `init.run(root): conn|nil` — sırayla `pcall` ile çağırır, ilk sonucu döner.

- [ ] **Step 1: Write the failing test**

Fixture:

```yaml
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret
    ports:
      - "55432:5432"
```

```lua
local compose = require("config.db.adapters.compose")
eq(compose.detect(root).kind, "postgres", "compose postgres")
eq(compose.detect(root).dsn, "postgresql://postgres:secret@localhost:55432/appdb", "compose port mapping")

local adapters = require("config.db.adapters.init")
eq(#adapters.order, 7, "yedi adaptor")
eq(adapters.order[1], "env", "env ilk")
eq(adapters.order[7], "compose", "compose son")
```

Ek test: port yayınlanmamışsa `nil`; `DATABASE_URL` environment'ta varsa doğrudan kullanılır; bozuk adaptör `init.run` içinde atlanır (geçici bir adaptör enjekte et).

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_adapters_compose_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement `compose.lua` ve `init.lua`**

`docker-compose*.yml` / `compose*.yml` dosyalarını `vim.fn.glob` ile bul; `fs.read` + `yaml.parse` ile oku. `services.*.environment` tablo veya `KEY=VALUE` listesi olabilir — ikisini de normalize et. `DATABASE_URL` varsa `url.parse`. Yoksa `POSTGRES_*` / `MYSQL_*` + `ports` ilk `"host:container"` eşlemesinden `localhost:<host>` DSN kur. `source = "compose:<file>"`.

`init.lua` yalnızca kayıt + sıralı çalıştırma; adaptörler `require` ile yüklenir.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_adapters_compose_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/adapters/compose.lua lua/config/db/adapters/init.lua tests/db_adapters_compose_spec.lua tests/fixtures/db/compose
git commit -m "feat(db): add compose adapter and adapter registry"
```

---

### Task 10: Tespit çekirdeği ve komutlar

**Files:**
- Create: `lua/config/db/detect.lua`
- Test: `tests/db_detect_spec.lua`

**Interfaces:**
- Consumes: `project.root`, `adapters.init.run`.
- Produces:
  - `M.connection(bufnr: integer): { kind: string, dsn: string, source: string, root: string }|nil`
  - `M.kind(bufnr: integer): string|nil`
  - `M.invalidate()`
  - `M.setup()` — komutları kaydeder.

- [ ] **Step 1: Write the failing test**

Fixture köklerinde sıra testi: env varken Spring yok sayılır; `.env` varken Spring yok sayılır; cache aynı sonucu döner; `invalidate()` sonrası yeniden okunur.

```lua
local detect = require("config.db.detect")
detect.invalidate()
vim.env.DATABASE_URL = "postgresql://env@h/envdb"
eq(detect.connection(spring_buf).source, "env:DATABASE_URL", "env > spring")
vim.env.DATABASE_URL = nil
detect.invalidate()
eq(detect.connection(dotenv_buf).source, "dotenv:.env.local", "dotenv > spring")
detect.invalidate()
eq(detect.connection(spring_buf).kind, "postgres", "spring bulunur")
eq(detect.connection(empty_buf), nil, "config yoksa nil")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_detect_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement `detect.lua`**

`cache[root]`; `connection` → `project.root(bufnr)` → cache → `adapters.init.run(root)` → `{ ..., root = root }`. `invalidate()` cache'i temizler. `setup()`:
- `:DbDetectInfo` → buffer bağlantısı varsa `kind`, `source`, `url.mask(dsn)`, attach LSP adları (`vim.lsp.get_clients({ bufnr = 0 })`), PG ise "pgls daemon değişmiş olabilir" satırı; yoksa "bağlantı yok, statik tipler".
- `:DbDetectRefresh` → `invalidate()`; `vim.notify` ile bilgi; açık SQL buffer'larında `postgres_lsp`/`sqls` istemcilerini `client:stop()` ile durdur, `vim.cmd("doautocmd FileType sql")`.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_detect_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/detect.lua tests/db_detect_spec.lua
git commit -m "feat(db): add detection core and commands"
```

---

### Task 11: LSP yardımcıları

**Files:**
- Create: `lua/config/db/lsp.lua`
- Test: `tests/db_lsp_spec.lua`

**Interfaces:**
- Produces:
  - `M.pgls_env(conn: table, base: table): table` — `DATABASE_URL` eklenmiş kopya (postgres değilse `base`).
  - `M.sqls_connection(conn: table): table|nil` — `{ driver, dataSourceName }`.
  - `M.override(kind: string|nil): string|nil` — postgres→`"postgres"`, mysql→`"mysql"`, sqlite/nil→`nil`.

- [ ] **Step 1: Write the failing test**

```lua
local lsp = require("config.db.lsp")
eq(lsp.sqls_connection({ kind = "mysql", dsn = "mysql://u:p@h:3306/db" }),
  { driver = "mysql", dataSourceName = "u:p@tcp(h:3306)/db" }, "mysql sqls ayari")
eq(lsp.sqls_connection({ kind = "sqlite", dsn = "sqlite:///tmp/x.db" }),
  { driver = "sqlite3", dataSourceName = "/tmp/x.db" }, "sqlite sqls ayari")
eq(lsp.pgls_env({ kind = "postgres", dsn = "postgresql://u@h/db" }, { A = "1" }).A, "1", "mevcut env korunur")
eq(lsp.pgls_env({ kind = "postgres", dsn = "postgresql://u@h/db" }, {}).DATABASE_URL, "postgresql://u@h/db", "dsn env'e eklenir")
eq(lsp.pgls_env({ kind = "mysql", dsn = "mysql://u@h/db" }, {}).DATABASE_URL, nil, "postgres degilse eklenmez")
eq(lsp.override("postgres"), "postgres", "postgres override")
eq(lsp.override("sqlite"), nil, "sqlite override yok")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_lsp_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement `lsp.lua`**

`sqls_connection`: mysql → `url.to_go_mysql`; sqlite → `url.sqlite_path(dsn, root)` (conn'da `root` yoksa `vim.fn.getcwd()`); diğer → `nil`. Tabloları her çağrıda yeni üret.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_lsp_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/lsp.lua tests/db_lsp_spec.lua
git commit -m "feat(db): add LSP wiring helpers"
```

---

### Task 12: Tip kaynakları

**Files:**
- Create: `lua/config/db/types.lua`
- Test: `tests/db_types_spec.lua`

**Interfaces:**
- Produces:
  - `M.static(kind: string|nil): string[]` — `postgres` (varsayılan), `mysql`, `sqlite`.
  - `M.postgres_query: string`
  - `M.alias_map: table<string, string[]>`
  - `M.normalize(raw: string[], kind: string): string[]` — PG satırlarını büyük harfe çevirip alias ekler; MySQL/SQLite'ta yalnızca `raw`.

- [ ] **Step 1: Write the failing test**

```lua
local types = require("config.db.types")
local pg = types.normalize({ "character varying", "integer", "uuid" }, "postgres")
check(vim.tbl_contains(pg, "VARCHAR"), "varchar alias")
check(vim.tbl_contains(pg, "VARCHAR(255)"), "varchar(255) alias")
check(vim.tbl_contains(pg, "INT"), "int alias")
check(vim.tbl_contains(pg, "UUID"), "uuid buyuk harf")
check(#types.static("mysql") > 10, "mysql statik liste")
check(#types.static("sqlite") > 5, "sqlite statik liste")
check(types.static(nil)[1] ~= nil, "bilinmeyen turde varsayilan PG")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_types_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement `types.lua`**

Spec'teki PG sorgusunu sabitle. Alias map: `CHARACTER VARYING`, `CHARACTER`, `NUMERIC`, `INTEGER`, `BOOLEAN`, `TIMESTAMP WITH TIME ZONE`, `TIME WITH TIME ZONE`. MySQL ve SQLite statik listeleri spec'teki adlarla. `normalize` dedupe eder, sırayı korur.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_types_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/db/types.lua tests/db_types_spec.lua
git commit -m "feat(db): add dialect type sources"
```

---

### Task 13: `sql_assist.lua` refactor + cmp kaynağı

**Files:**
- Modify: `lua/config/sql_assist.lua`
- Modify: `lua/plugins/cmp.lua` (`pg_types` → `db_types`)
- Test: `tests/db_sql_assist_spec.lua`

**Interfaces:**
- Consumes: `db.detect.connection`, `db.types`.
- Produces: `M.source` (cmp kaynağı sınıfı), `M.setup()`, `:DbTypesRefresh`.

- [ ] **Step 1: Write the failing test**

Buffer'a DDL ve DML içeriği koy; kaynağı doğrudan çağır:

```lua
local assist = require("config.sql_assist")
local src = assist.source.new()
local function items(lines, row)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  local res
  src:complete({ context = { bufnr = 0, cursor = { row = row, col = 0 }, cursor_before_line = lines[row] } }, function(r) res = r end)
  return res.items
end

check(#items({ "create table x (", "  id " }, 2) > 10, "DDL icinde tipler")
eq(#items({ "select  from t;" }, 1), 0, "DDL disinda bos")
check(vim.tbl_contains(vim.tbl_map(function(i) return i.label end, items({ "create table x (", "  id " }, 2)), "VARCHAR"), "statik yedekte VARCHAR")
```

Ek test: `pg_types` yerine `db_types` kaydı `setup()` sonrası mevcut; `:DbTypesRefresh` komutu tanımlı.

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_sql_assist_spec.lua`
Expected: FAIL (eski `pg_types` / `PG` sabitleri)

- [ ] **Step 3: Refactor `sql_assist.lua`**

Snippet'leri koru. Tip mantığını `db.types` + `db.detect` üzerinden kur:
- `conn = detect.connection(bufnr)`.
- DDL bağlamı değilse boş dön.
- `conn.kind == "postgres"` ve `psql` varsa: asenkron sorgu, prefetch, `kind..":"..dsn` cache, 30 sn başarısız backoff.
- Aksi halde `types.static(conn.kind)`; conn yoksa `types.static(nil)`.
- Bir kez "PostgreSQL bağlantısı yok..." bilgisi (yalnızca PG varsayılanında).
- `:DbTypesRefresh` cache temizler.
- `cmp.register_source("db_types", source.new())`.

`cmp.lua` kaynağı `{ name = "db_types", priority = 900 }`.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_sql_assist_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/config/sql_assist.lua lua/plugins/cmp.lua tests/db_sql_assist_spec.lua
git commit -m "refactor(sql): use generic DB detection for type completion"
```

---

### Task 14: LSP kapılama + temizlik + tam doğrulama

**Files:**
- Modify: `lua/config/db/lsp.lua`
- Modify: `lua/plugins/mason.lua`
- Modify: `init.lua`
- Delete: `lua/config/pg_env.lua`
- Modify: `lua/plugins/cmp.lua` (kaynak adı kaldıysa)
- Test: `tests/db_lsp_attach_spec.lua` (kapılama fonksiyonları)

**Interfaces:**
- Consumes: `db.detect`, `db.lsp`.
- Produces: `postgres_lsp`/`sqls` için kapılanmış `root_dir`; `b:sql_type_override` autocmd; Mason `ensure_installed` listesi.

- [ ] **Step 1: Write the failing test**

Test edilebilir kapılama fonksiyonu mason'dan ayrı dursun diye `db.lsp`e eklenir:

```lua
eq(lsp.attach_kind("postgres"), "postgres_lsp", "pg -> pgls")
eq(lsp.attach_kind("mysql"), "sqls", "mysql -> sqls")
eq(lsp.attach_kind("sqlite"), "sqls", "sqlite -> sqls")
eq(lsp.attach_kind(nil), nil, "baglanti yoksa lsp yok")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -l tests/db_lsp_attach_spec.lua`
Expected: FAIL `attach_kind`

- [ ] **Step 3: Implement**

- `db/lsp.lua`: `M.attach_kind(kind)`.
- `mason.lua`:
  - `ensure_installed`: `postgres-language-server`, `sqls`, `sqlfluff`.
  - `automatic_enable.exclude`: `jdtls`, `postgres_lsp`, `sqls`.
  - `vim.lsp.config("postgres_lsp", { filetypes = { "sql" }, root_dir = function(bufnr, on_dir) if detect.kind(bufnr) == "postgres" then on_dir(project.root(bufnr) or dirname) end end, cmd = function(dispatchers, config) ... lsp.pgls_env ... end })`.
  - `vim.lsp.config("sqls", { filetypes = { "sql", "mysql" }, root_dir = ... mysql/sqlite ..., before_init = function(_, config) local conn = detect.connection(bufnr) ... config.settings.sqls.connections = { lsp.sqls_connection(conn) } end })`.
  - `sqls` dosya türü `mysql` olsa da `before_init` buffer'ı `config.bufnr` üzerinden alır.
  - `vim.api.nvim_create_autocmd("FileType", { pattern = "sql", callback = function() local k = detect.kind(0); local o = lsp.override(k); if o then vim.b.sql_type_override = o end end })`.
  - `require("config.db.detect").setup()` init sırasında çağrılır (kök `init.lua`, `lua/plugins/cmp.lua` setup'ından önce).
- `pg_env.lua` silinir; kalan referanslar `grep -rn "pg_env" lua/` ile temizlenir.

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -l tests/db_lsp_attach_spec.lua`
Expected: PASS

- [ ] **Step 5: Full verification**

Run:
```bash
for f in tests/db_*_spec.lua; do nvim --headless -u NONE -l "$f" || exit 1; done
nvim --headless -u NONE -l tests/comments_spec.lua
nvim --headless -u NONE -l tests/indent_sync_spec.lua
```

Expected: tüm spec'ler `passed`, çıkış kodu 0.
Manuel duman testi:
1. Spring fixture'ı geçici projede aç → `:DbDetectInfo` postgres + spring kaynağı.
2. `.env` ekle → refresh sonrası kaynak `dotenv`.
3. Proje dışı `/tmp/x.sql` → LSP yok, snippet + statik tipler.
4. `:DbTypesRefresh` ve `:DbDetectRefresh` çalışır.
5. SQL buffer'da `b:sql_type_override` doğru değer (`postgres`/`mysql`, sqlite için boş).

- [ ] **Step 6: Stil ve commit**

```bash
stylua --check lua/config/db lua/config/sql_assist.lua lua/plugins/mason.lua
git add init.lua lua/config/db lua/config/sql_assist.lua lua/plugins/mason.lua lua/plugins/cmp.lua tests
git rm lua/config/pg_env.lua
git commit -m "feat(sql): wire DB detection to LSP and remove pg_env"
```
