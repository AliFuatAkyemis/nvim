-- DSN normalizasyonu: URI, JDBC, libpq key=value ve Go MySQL DSN'lerini
-- tek bir { kind, dsn } bicimine cevirir.
--
-- Bozuk/taninmayan girdi nil doner; fonksiyonlar hata firlatmaz.

local M = {}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Bos olmayan string ya da sayiyi string'e cevirir.
---@param value any
---@return string|nil
local function value_string(value)
  if type(value) == "number" then
    return tostring(value)
  end
  if type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

---Zorunlu alan: string'e cevirip kirpar, bos ise nil.
---@param value any
---@return string|nil
local function required(value)
  local result = value_string(value)
  if not result then
    return nil
  end
  result = trim(result)
  if result == "" then
    return nil
  end
  return result
end

local function encode_component(value)
  return (value:gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function decode_component(value)
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function format_host(host)
  if host:sub(1, 1) ~= "[" and host:find(":", 1, true) then
    return "[" .. host .. "]"
  end
  return host
end

---authority -> { user, password, host, port }; gecersizse nil.
local function split_authority(authority)
  if authority == "" then
    return nil
  end
  local userinfo, hostport = authority:match("^(.*)@(.*)$")
  if not hostport then
    hostport = authority
  end

  local host, port
  if hostport:sub(1, 1) == "[" then
    local inner, rest = hostport:match("^%[([^%]]*)%](.*)$")
    if not inner then
      return nil
    end
    host = "[" .. inner .. "]"
    port = rest:match("^:?(.*)$")
  else
    local bare_host, bare_port = hostport:match("^([^:]*):(.*)$")
    if bare_host then
      host, port = bare_host, bare_port
    else
      host = hostport
    end
  end
  if not host or host == "" then
    return nil
  end
  if port == "" then
    port = nil
  end

  local user, password
  if userinfo then
    user, password = userinfo:match("^([^:]*):(.*)$")
    if not user then
      user = userinfo
    end
  end

  return { user = user, password = password, host = host, port = port }
end

local function split_path_and_query(value)
  local index = value:find("?", 1, true)
  if not index then
    return value, nil
  end
  return value:sub(1, index - 1), value:sub(index + 1)
end

---PostgreSQL icin ssl=true/false -> sslmode=require/disable.
local function normalize_pg_query(query)
  if not query or query == "" then
    return query
  end

  local pieces = {}
  local ssl_mode
  for piece in query:gmatch("[^&]+") do
    local key, value = piece:match("^([^=]*)=(.*)$")
    if key and key:lower() == "ssl" then
      local flag = value:lower()
      if flag == "true" or flag == "1" then
        ssl_mode = "require"
      elseif flag == "false" or flag == "0" then
        ssl_mode = "disable"
      else
        pieces[#pieces + 1] = piece
      end
    else
      pieces[#pieces + 1] = piece
    end
  end

  if ssl_mode then
    local replaced = false
    for index, piece in ipairs(pieces) do
      local key = piece:match("^([^=]*)=")
      if key and key:lower() == "sslmode" then
        pieces[index] = "sslmode=" .. ssl_mode
        replaced = true
        break
      end
    end
    if not replaced then
      pieces[#pieces + 1] = "sslmode=" .. ssl_mode
    end
  end

  return table.concat(pieces, "&")
end

---scheme://... formunu normalizes eder.
local function parse_direct(input)
  local scheme, rest = input:match("^([%a][%w+.-]*)://(.*)$")
  if not scheme then
    return nil
  end
  scheme = scheme:lower()

  if scheme == "sqlite" then
    if rest == "" then
      return nil
    end
    return { kind = "sqlite", dsn = "sqlite://" .. rest }
  end

  local kind, canonical
  if scheme == "postgres" or scheme == "postgresql" then
    kind, canonical = "postgres", "postgresql"
  elseif scheme == "mysql" or scheme == "mariadb" then
    kind, canonical = "mysql", "mysql"
  else
    return nil
  end

  local authority, path = rest:match("^([^/?#]*)(.*)$")
  if not split_authority(authority) then
    return nil
  end

  local path_only, query = split_path_and_query(path)
  if kind == "postgres" then
    query = normalize_pg_query(query)
  end

  local dsn = canonical .. "://" .. authority .. path_only
  if query and query ~= "" then
    dsn = dsn .. "?" .. query
  end
  return { kind = kind, dsn = dsn }
end

local function split_tokens(input)
  local tokens, buffer = {}, {}
  local quote
  for index = 1, #input do
    local c = input:sub(index, index)
    if quote then
      if c == quote then
        quote = nil
      else
        buffer[#buffer + 1] = c
      end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c:match("%s") then
      if #buffer > 0 then
        tokens[#tokens + 1] = table.concat(buffer)
        buffer = {}
      end
    else
      buffer[#buffer + 1] = c
    end
  end
  if quote then
    return nil
  end
  if #buffer > 0 then
    tokens[#tokens + 1] = table.concat(buffer)
  end
  return tokens
end

local LIBPQ_KEYS = {
  host = true,
  port = true,
  user = true,
  password = true,
  dbname = true,
}

---libpq "host=... dbname=..." formunu postgres URI'sine cevirir.
local function parse_libpq(input)
  if not input:find("=", 1, true) or input:find("://", 1, true) then
    return nil
  end
  local tokens = split_tokens(input)
  if not tokens or #tokens == 0 then
    return nil
  end

  local values, extras = {}, {}
  for _, token in ipairs(tokens) do
    local key, value = token:match("^([%w_]+)=(.*)$")
    if not key then
      return nil
    end
    key = key:lower()
    values[key] = value
    if not LIBPQ_KEYS[key] then
      extras[#extras + 1] = token
    end
  end

  local database = required(values.dbname)
  if not database then
    return nil
  end
  local host = required(values.host) or "localhost"
  local user = required(values.user)
  local password = value_string(values.password)

  local authority = format_host(host)
  if user then
    local auth = encode_component(user)
    if password then
      auth = auth .. ":" .. encode_component(password)
    end
    authority = auth .. "@" .. authority
  end
  local port = required(values.port)
  if port then
    authority = authority .. ":" .. port
  end

  local dsn = "postgresql://" .. authority .. "/" .. encode_component(database)
  if #extras > 0 then
    dsn = dsn .. "?" .. table.concat(extras, "&")
  end
  return { kind = "postgres", dsn = dsn }
end

---Go MySQL DSN: user[:pass]@tcp(host[:port])/database[?params]
local function parse_go_mysql(input)
  if not input:find("@tcp(", 1, true) then
    return nil
  end
  local userinfo, hostport, rest = input:match("^(.*)@tcp%(([^%)]*)%)(.*)$")
  if not userinfo or userinfo == "" or not hostport or hostport == "" then
    return nil
  end
  local database, query = rest:match("^/([^%?]*)(.*)$")
  if not database then
    return nil
  end
  if query:sub(1, 1) == "?" then
    query = query:sub(2)
  end

  local user, password = userinfo:match("^([^:]*):(.*)$")
  if not user then
    user = userinfo
  end
  local auth = encode_component(user)
  if password then
    auth = auth .. ":" .. encode_component(password)
  end

  local dsn = "mysql://" .. auth .. "@" .. hostport .. "/" .. database
  if query ~= "" then
    dsn = dsn .. "?" .. query
  end
  return { kind = "mysql", dsn = dsn }
end

---DSN'i tanir ve normalize eder.
---@param input string
---@return { kind: string, dsn: string }|nil
function M.parse(input)
  if type(input) ~= "string" then
    return nil
  end
  local value = trim(input)
  if value == "" then
    return nil
  end

  local direct = parse_direct(value)
  if direct then
    return direct
  end

  if value:sub(1, 5):lower() == "file:" then
    local path = value:sub(6)
    if path:sub(1, 2) == "//" then
      path = path:sub(3)
    end
    if path == "" then
      return nil
    end
    return { kind = "sqlite", dsn = "sqlite://" .. path }
  end

  if value:sub(1, 5):lower() == "jdbc:" then
    direct = parse_direct(value:sub(6))
    if direct then
      return direct
    end
  end

  local libpq = parse_libpq(value)
  if libpq then
    return libpq
  end

  return parse_go_mysql(value)
end

local function network_uri(scheme, parts)
  local host = required(parts.host)
  local database = required(parts.database)
  if not host or not database then
    return nil
  end

  local authority = format_host(host)
  local user = required(parts.user)
  if user then
    local auth = encode_component(user)
    local password = value_string(parts.password)
    if password then
      auth = auth .. ":" .. encode_component(password)
    end
    authority = auth .. "@" .. authority
  end
  local port = required(parts.port)
  if port then
    authority = authority .. ":" .. port
  end

  return scheme .. "://" .. authority .. "/" .. encode_component(database)
end

---Parcalardan DSN kurar; zorunlu alan eksikse nil.
---@param kind string
---@param parts table
---@return string|nil
function M.from_parts(kind, parts)
  if type(kind) ~= "string" or type(parts) ~= "table" then
    return nil
  end
  kind = kind:lower()

  if kind == "postgres" or kind == "postgresql" then
    return network_uri("postgresql", parts)
  end
  if kind == "mysql" or kind == "mariadb" then
    return network_uri("mysql", parts)
  end
  if kind == "sqlite" or kind == "sqlite3" then
    local path = required(parts.path) or required(parts.database)
    if not path then
      return nil
    end
    return "sqlite://" .. path
  end
  return nil
end

---Authority icindeki parolayi *** ile maskeler; diger girdiler degismez.
---@param dsn string
---@return string
function M.mask(dsn)
  if type(dsn) ~= "string" or dsn == "" then
    return dsn
  end
  local prefix, rest = dsn:match("^([%a][%w+.-]*://)(.*)$")
  if not prefix then
    return dsn
  end
  local path_index = rest:find("[/%?#]")
  local authority = path_index and rest:sub(1, path_index - 1) or rest
  local suffix = path_index and rest:sub(path_index) or ""
  local at = authority:match("^.*()@")
  if not at then
    return dsn
  end
  local userinfo = authority:sub(1, at - 1)
  local user = userinfo:match("^([^:]*):")
  if not user then
    return dsn
  end
  return prefix .. user .. ":***" .. authority:sub(at) .. suffix
end

---MySQL URI'sini Go surucu DSN'ine cevirir.
---@param dsn string
---@return string|nil
function M.to_go_mysql(dsn)
  if type(dsn) ~= "string" then
    return nil
  end
  local parsed = M.parse(dsn)
  if not parsed or parsed.kind ~= "mysql" then
    return nil
  end

  local _, rest = parsed.dsn:match("^([%a][%w+.-]*)://(.*)$")
  if not rest then
    return nil
  end
  local authority, path = rest:match("^([^/?#]*)(.*)$")
  local parts = split_authority(authority)
  if not parts then
    return nil
  end

  local database = path:match("^/([^%?]*)") or ""
  local _, query = split_path_and_query(path)

  local auth = ""
  if parts.user and parts.user ~= "" then
    auth = decode_component(parts.user)
    if parts.password then
      auth = auth .. ":" .. decode_component(parts.password)
    end
    auth = auth .. "@"
  end

  local hostport = parts.host
  if parts.port then
    hostport = hostport .. ":" .. parts.port
  end

  local result = auth .. "tcp(" .. hostport .. ")/" .. decode_component(database)
  if query and query ~= "" then
    result = result .. "?" .. query
  end
  return result
end

---SQLite DSN'indeki dosya yolunu kok dizine gore cozer.
---@param dsn string
---@param root string
---@return string|nil
function M.sqlite_path(dsn, root)
  if type(dsn) ~= "string" then
    return nil
  end
  local parsed = M.parse(dsn)
  if not parsed or parsed.kind ~= "sqlite" then
    return nil
  end

  local path = parsed.dsn:match("^sqlite://(.*)$")
  if not path or path == "" then
    return nil
  end
  path = path:match("^([^?]*)") or path
  path = decode_component(path)
  if path == "" then
    return nil
  end
  if path == ":memory:" then
    return path
  end
  if path:sub(1, 1) == "/" then
    return vim.fs.normalize(path)
  end
  if type(root) ~= "string" or root == "" then
    return nil
  end
  return vim.fs.normalize(vim.fs.joinpath(root, path))
end

return M
