# Generic SQL DB Detection — Tasarım Spec'i

Tarih: 2026-11-14
Durum: Onaylandı (uygulama planı bekliyor)

## Amaç

Herhangi bir dil/framework projesinde `.sql` dosyası açıldığında veritabanı
bağlantısını otomatik tespit etmek; tespit edilen DB türüne göre doğru LSP'yi,
tip completion'ını ve syntax highlight'ını devreye almak. Kullanıcı hiçbir
noktada tip/fonksiyon listesi elle yazmayacak.

## Hedefler

- PostgreSQL, MySQL/MariaDB ve SQLite desteği.
- Bağlantı kaynakları: ortam değişkenleri, `.env*`, yaygın framework config'leri.
- DB türüne göre tek LSP: PostgreSQL → postgres_lsp, MySQL/SQLite → sqls.
- PostgreSQL tipleri canlı katalogdan; MySQL/SQLite tipleri statik yedekten.
- Bağlantı yoksa snippet + statik tip yedeği ile çalışmaya devam.
- Parolalar log'a, bildirime veya diske yazılmaz.

## Kapsam Dışı

- MSSQL, Oracle, ClickHouse vb. ek motorlar.
- ORM modellerinden şema çıkarımı (Prisma modelleri, Django modelleri vb.).
- Migration linting / DB linter.
- Bağlantı kurulamayan DB'de yeniden bağlanma dışında otomatik düzeltme.
- Proje dosyalarını değiştirme.

## Mevcut Durum

- `lua/config/pg_env.lua`: yalnızca `DATABASE_URL` ve proje kökündeki
  `.env.local` / `.env` okunuyor.
- `lua/config/sql_assist.lua`: snippet'ler + `pg_types` cmp kaynağı.
  PostgreSQL kataloğu `psql` ile okunuyor; bağlantı yoksa 40 tiplik statik
  yedek kullanılıyor. Tip kaynağı yalnızca DDL bağlamında çalışıyor.
- `lua/plugins/mason.lua`: `postgres_lsp` için `cmd`/`root_dir` tanımı var.
  `sqls` kaldırılmış durumda.
- `lua/plugins/conform.lua`: kaydetmede `sqlfluff`.
- Proje kökü yalnızca `.git` / `postgres-language-server.jsonc` ile bulunuyor.
- Spring, Rails, Django, Prisma, compose tespiti yok.
- MySQL/SQLite LSP'si yok.

## Mimari

Yeni modüller `lua/config/db/` altında:

| Modül | Sorumluluk |
|---|---|
| `detect.lua` | Tek giriş noktası. `connection(bufnr)` → `{ kind, dsn, source, root }`. Cache ve `invalidate()`. |
| `project.lua` | Proje kökü tespiti. |
| `url.lua` | DSN normalizasyonu, parça birleştirme, parola maskeleme. |
| `adapters/init.lua` | Adaptör listesi ve sıralı çalıştırma. |
| `adapters/env.lua` | Ortam değişkenleri. |
| `adapters/dotenv.lua` | `.env` dosyaları. |
| `adapters/spring.lua` | Spring Boot properties/yml. |
| `adapters/rails.lua` | Rails database.yml. |
| `adapters/prisma.lua` | Prisma schema.prisma. |
| `adapters/django.lua` | Django settings.py. |
| `adapters/compose.lua` | docker-compose / compose. |

Mevcut `lua/config/pg_env.lua` kaldırılır; bağlantı tespiti `db/detect.lua`
üzerinden yapılır. `lua/config/sql_assist.lua` yalnızca snippet + cmp
`db_types` kaynağı olarak kalır.

### Proje kökü

`project.lua` sırayla yukarı doğru şu işaretleri arar:

```
.git
package.json
pom.xml
build.gradle / build.gradle.kts
settings.gradle / settings.gradle.kts
Gemfile
manage.py
composer.json
go.mod
mix.exs
Cargo.toml
postgres-language-server.jsonc
```

Bulunamazsa dosyanın kendi dizini döner.

### Genel akış

1. SQL buffer açılır, proje kökü bulunur.
2. `detect.connection(root)` sırayla kaynakları dener.
3. İlk geçerli bağlantı root bazında cache'lenir.
4. DB türüne göre LSP kapılanır (tek LSP):
   - postgres → postgres_lsp
   - mysql / sqlite → sqls
5. pgls süreç env'ine `DATABASE_URL` verilir; sqls `connections` ayarı
   tespit edilen DSN'den kurulur.
6. Tip kaynağı cache'i ısıtılır.
7. Bağlantı yoksa hiçbir SQL LSP'si attach edilmez; snippet + statik tipler.

## Bağlantı Tespiti

### Öncelik

1. `env`
2. `dotenv`
3. framework adaptörleri: `spring` → `rails` → `prisma` → `django` → `compose`

İlk geçerli sonuç kazanır. Aynı adaptör içinde adaylar dosya sırasına göre
değerlendirilir.

### env

Desteklenen anahtarlar:

- Doğrudan URL: `DATABASE_URL`, `DB_URL`, `POSTGRES_URL`, `MYSQL_URL`
- PostgreSQL parçaları: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`
- MySQL parçaları: `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`,
  `MYSQL_DATABASE`
- SQLite yolu: `DATABASE_PATH`, `SQLITE_PATH`

URL varsa doğrudan normalize edilir. URL yoksa parçalar birleştirilir.
PostgreSQL'de DSN üretmek için `PGHOST` ve `PGDATABASE` zorunlu; `PGPORT`
verilmezse 5432, `PGUSER` verilmezse işletim sistemi kullanıcısı varsayılır.
MySQL'de `MYSQL_HOST` ve `MYSQL_DATABASE` zorunlu; port varsayılanı 3306.

### dotenv

Dosyalar, özgülden genele (ilk bulunan kazanır):

```
.env.local
.env.development
.env.dev
.env
```

Desteklenen sözdizimi:

- `KEY=VALUE`
- `export KEY=VALUE`
- Tek/çift tırnak
- `${VAR}` ve `${VAR:default}` yer tutucuları

Anahtarlar: `DATABASE_URL`, `DB_URL`, `POSTGRES_URL`, `MYSQL_URL`,
`DATABASE_PATH`, `SQLITE_PATH`; ayrıca `DB_HOST`, `DB_PORT`, `DB_USER`,
`DB_PASSWORD`, `DB_NAME`, `DB_DATABASE`, `DB_CONNECTION`.

`DB_CONNECTION` değeri `pgsql` / `postgres` / `mysql` / `mariadb` / `sqlite`
ise tür belirlemede kullanılır.

### spring

Dosyalar: `src/main/resources/application.properties`,
`application.yml`, `application.yaml` ve bunların `application-*` varyantları.

Okunan anahtarlar:

- `spring.datasource.url`
- `spring.datasource.hikari.jdbc-url`
- `spring.datasource.username`
- `spring.datasource.password`
- `spring.datasource.driver-class-name`

Kurallar:

- `jdbc:postgresql://`, `jdbc:mysql://`, `jdbc:sqlite:` normalize edilir.
- `${VAR}` ve `${VAR:default}` çözülür.
- Önce `application.*`; URL yoksa `application-*` dosyaları alfabetik.
- `driver-class-name` tür çelişkisinde URL şeması kazanır.

### rails

Dosya: `config/database.yml`.

- `development` bölümü öncelikli; yoksa dosyadaki ilk bağlantı.
- `url:` varsa doğrudan normalize edilir.
- Parçalar: `adapter`, `host`, `port`, `database`, `username`, `password`.
- `adapter` eşlemesi:
  - `postgresql` → postgres
  - `mysql2` / `trilogy` → mysql
  - `sqlite3` → sqlite
- `pool`, `timeout` gibi anahtarlar yok sayılır.

### prisma

Dosya: `prisma/schema.prisma`.

```
datasource db {
  provider = "postgresql" | "mysql" | "sqlite"
  url      = env("DATABASE_URL") | "literal"
}
```

- `provider` türü belirler.
- `env(...)` kullanılıyorsa URL `env`/`dotenv` adaptörlerinden gelir.
- Literal URL normalize edilir.
- SQLite `file:./dev.db` proje köküne göre mutlak yola çevrilir.

### django

Dosyalar: `settings.py` ve bir seviye altındaki `*/settings.py`.

- `DATABASE_URL` satırı varsa doğrudan.
- Yoksa `DATABASES` sözlüğündeki `default` girdisi:
  - `ENGINE = django.db.backends.postgresql` → postgres
  - `ENGINE = django.db.backends.mysql` → mysql
  - `ENGINE = django.db.backends.sqlite3` → sqlite
  - `HOST`, `PORT`, `NAME`, `USER`, `PASSWORD`
- `NAME = BASE_DIR / "db.sqlite3"` → `<root>/db.sqlite3`
- Sözlük ayrıştırması basit regex ile yapılır; karmaşık Python ifadeleri
  desteklenmez ve adaptör o adayı atlar.

### compose

Dosyalar: `docker-compose*.yml`, `compose*.yml`.

- `services.*.environment` içinde `DATABASE_URL` varsa doğrudan.
- `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` veya
  `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD` + `ports: "5432:5432"`
  varsa `localhost:<published_port>` DSN üretilir.
- Port yayınlanmamışsa veya host portu boşsa atlanır.
- En düşük öncelikli, best-effort adaptör.

## URL Normalizasyonu (`url.lua`)

Desteklenen girdiler:

| Girdi | Çıktı kind |
|---|---|
| `postgresql://...`, `postgres://...` | postgres |
| `jdbc:postgresql://...` | postgres |
| `mysql://...`, `mariadb://...` | mysql |
| `jdbc:mysql://...` | mysql |
| `sqlite:///path`, `sqlite://relative`, `file:./x.db` | sqlite |
| `host=... dbname=... user=...` | postgres |
| `user:pass@tcp(host:port)/db` | mysql |

Kurallar:

- `jdbc:postgresql://` → `postgresql://`
- `jdbc:mysql://` → `mysql://`
- SQLite yolu proje köküne göre mutlaklaştırılır.
- `ssl=true` → `sslmode=require`, `ssl=false` → `sslmode=disable`
  (yalnızca PostgreSQL).
- Boş DSN, şema yok veya tanınmayan şema → `nil` döner.
- `mask(dsn)`: kullanıcı:parola kısmındaki parolayı `***` yapar.

## LSP Entegrasyonu

### postgres_lsp (pgls)

- `root_dir`: yalnızca `kind == "postgres"` ise `on_dir(root)`; değilse
  çağrılmaz.
- `cmd`: `vim.lsp.rpc.start` ile `postgres-language-server lsp-proxy`;
  env = mevcut ortam + `DATABASE_URL=<dsn>`.
- `filetypes = { "sql" }`.

### sqls (MySQL/SQLite)

- `root_dir`: yalnızca `kind == "mysql"` veya `kind == "sqlite"` ise attach.
- `before_init`: `config.settings.sqls.connections` kurulur:
  - MySQL: `{ driver = "mysql", dataSourceName = "<go-dsn>" }`
  - SQLite: `{ driver = "sqlite3", dataSourceName = "<path>" }`
- `lowercaseKeywords = false`.
- `filetypes = { "sql", "mysql" }`.

### Mason

- `ensure_installed`: `postgres-language-server`, `sqls`, `sqlfluff`.
- `mason-lspconfig.automatic_enable` dışlamasına `postgres_lsp` ve `sqls`
  eklenir; enable işlemi `vim.lsp.config` + kapılanmış `root_dir` ile yapılır.

### Bağlantı yoksa

- Hiçbir SQL LSP'si attach olmaz.
- Snippet'ler, `db_types` statik yedeği ve buffer/path kaynakları çalışır.
- Bir kez `vim.notify` ile bilgi verilir.

## Tip Completion

cmp kaynağı: `db_types` (eski `pg_types`).

- Yalnızca DDL bağlamı:
  - `CREATE TABLE ... (` parantezleri açıkken
  - `ALTER TABLE ... ADD COLUMN` sonrası
- PostgreSQL:
  - Bağlantı ve `psql` varsa `pg_type` + `format_type()` canlı sorgu.
  - Dosya açılışında prefetch; oturum cache.
  - Sorgu:
    ```sql
    select distinct upper(format_type(t.oid, null))
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typtype in ('b','e','d','r','m')
      and t.typelem = 0
      and t.typisdefined
      and n.nspname <> 'information_schema'
      and t.typname not like '\_%'
    order by 1;
    ```
  - küçük takma ad eşlemesi: `VARCHAR`, `VARCHAR(255)`, `INT`, `DECIMAL`,
    `TIMESTAMPTZ`, `CHAR`, `BOOL`.
- MySQL: statik liste (`INT`, `BIGINT`, `VARCHAR`, `TEXT`, `DATETIME`,
  `TIMESTAMP`, `DECIMAL`, `JSON`, `ENUM(...)`, `BLOB`...).
- SQLite: statik liste (`INTEGER`, `TEXT`, `REAL`, `BLOB`, `NUMERIC`,
  `BOOLEAN`, `DATE`, `DATETIME`...).
- Bağlantı yok / CLI yok / DB erişilemez: ilgili türün statik yedeği.
- Cache anahtarı `kind + dsn`; başarısız denemede 30 sn backoff.
- Kaynak önceliği 900 (LSP alanlarından önce).

## Sözdizimi

Buffer bazında:

- postgres → `b:sql_type_override = "postgres"`
- mysql → `b:sql_type_override = "mysql"`
- sqlite / bilinmiyor → ayarlanmaz (Vim varsayılan `sql` syntax'ı)

Yerleşik `syntax/sql.vim` kullanılır; ek plugin yok.

## Komutlar

| Komut | Davranış |
|---|---|
| `:DbDetectInfo` | Kök, tür, kaynak dosya, maskeli DSN, attach LSP, tip kaynağı (canlı/statik), pgls daemon uyarısı. |
| `:DbDetectRefresh` | Tespit cache'ini temizler; açık SQL buffer'larında pgls/sqls istemcilerini durdurup yeniden dener. |
| `:DbTypesRefresh` | Tip cache'ini temizler. |

## Güvenlik

- Parolalar yalnızca bellekte ve alt süreç env'inde tutulur; diske yazılmaz.
- `vim.system` liste argümanlarıyla çalışır; shell string interpolasyonu yok.
- DSN log'a, bildirime veya `:DbDetectInfo` çıktısına maskesiz basılmaz.
- `.env` değerleri global `vim.env`'e yazılmaz; yalnızca ilgili alt sürece verilir.
- Config dosyaları yalnızca okunur.
- Okuma proje köküyle sınırlıdır; kök dışına symlink takip edilmez.

## Hata Yönetimi

- Her adaptör `pcall` ile izole edilir.
- Eksik/bozuk dosya sessizce atlanır, sıradaki aday denenir.
- Ayrıştırılamayan DSN → `nil`; LSP attach edilmez.
- `psql` yok / DB erişilemez → statik tipler, 30 sn backoff.
- psql çağrısı asenkron ve zaman aşımlı; UI bloklanmaz.
- pgls daemon env'i ilk açılışta alır; `:DbDetectInfo` yeniden başlatma
  gerekebileceğini bildirir.

## Dosya Değişiklikleri

Yeni:

```
lua/config/db/detect.lua
lua/config/db/project.lua
lua/config/db/url.lua
lua/config/db/adapters/init.lua
lua/config/db/adapters/env.lua
lua/config/db/adapters/dotenv.lua
lua/config/db/adapters/spring.lua
lua/config/db/adapters/rails.lua
lua/config/db/adapters/prisma.lua
lua/config/db/adapters/django.lua
lua/config/db/adapters/compose.lua
```

Değişen:

```
lua/config/sql_assist.lua   (db_types + snippet)
lua/plugins/mason.lua       (pgls/sqls kapılama)
lua/plugins/cmp.lua         (kaynak adı db_types)
```

Silinen:

```
lua/config/pg_env.lua
```

## Testler

Gerçek DB gerektirmeyen birim testleri (`tests/`):

Fixture projeleri:

```
tests/fixtures/db/spring_props/
tests/fixtures/db/spring_yml/
tests/fixtures/db/rails/
tests/fixtures/db/prisma/
tests/fixtures/db/django/
tests/fixtures/db/dotenv/
tests/fixtures/db/compose/
tests/fixtures/db/empty/
```

Test başlıkları:

1. URL normalizasyonu: JDBC PG/MySQL, MySQL URI, SQLite URI/`file:`,
   libpq key=value, Go DSN; geçersiz girdi `nil`.
2. Spring properties ve yml; placeholder çözümü; `application-*` sırası.
3. Rails `development` seçimi; adapter→kind eşlemesi; `url:` önceliği.
4. Prisma literal URL ve `env(...)` davranışı; SQLite yol mutlaklaştırma.
5. Django `DATABASE_URL` ve `DATABASES` sözlüğü; sqlite `BASE_DIR`.
6. Compose yayınlanan port eşlemesi; port yoksa atlama.
7. Öncelik: env > .env > framework.
8. Bozuk adaptör izolasyonu (bir adaptör hata verince tespit devam eder).
9. Parola maskeleme.
10. Proje kökü tespiti (dil işaretleri).

Canlı PostgreSQL testi manuel: geçici `initdb` cluster + `psql` ile tip
sorgusu; CI'da çalıştırılmaz.

Test çalıştırma: mevcut repo düzeniyle headless,
`nvim --headless -u NONE -l tests/db_detect_spec.lua`.

## Kabul Kriterleri

1. Spring `jdbc:postgresql://...` projesinde kind postgres; pgls attach;
   `:DbDetectInfo` doğru kaynak ve maskeli DSN gösterir.
2. Rails `mysql2` projesinde sqls attach; MySQL tip listesi gelir.
3. Prisma `file:./dev.db` projesinde sqls attach; SQLite tip listesi gelir.
4. `.env` içindeki URL Spring config'ini yener; gerçek env `.env`'i yener.
5. Config yoksa LSP yok; snippet + varsayılan PG statik tipleri; tek bildirim.
6. DDL'de tip completion üç DB türünde de çalışır; `SELECT` içinde çalışmaz.
7. `b:sql_type_override` postgres/mysql için doğru set edilir.
8. Formatter davranışı değişmez (sqlfluff, kaydetmede uppercase).
9. Log/notify/komut çıktısında parola görünmez.
10. `:DbDetectRefresh` config değişikliğini yeniden tespit eder.

## Riskler ve Açık Konular

- **pgls daemon env'i:** Kalıcı `__run_server` süreci env'i ilk açılışta alır.
  DSN değişince yeniden başlatma gerekir; komut çıktısı bunu hatırlatır.
- **sqls MySQL DSN:** URI → Go driver DSN dönüşümü şema/parametre
  farklılıklarında eksik kalabilir; testlerde yaygın biçimler kapsanır.
- **Compose:** Container içi adresler host'tan erişilemez; yalnızca yayınlanan
  portlar kullanılır. Best-effort.
- **Django settings.py:** Python kodu tam ayrıştırılmaz; yalnızca basit
  literal sözlükler ve `DATABASE_URL` desteklenir.
- **Rails database.yml:** ERB (`<%= ENV[...] %>`) desteklenmez; bu durumda
  aday atlanır ve `.env`/env yolu denenir.
- **MySQL/SQLite tip listeleri statik:** Bu motorlarda tipler katalogdan
  otomatik gelmez; liste güncellemesi gerekebilir.
```
