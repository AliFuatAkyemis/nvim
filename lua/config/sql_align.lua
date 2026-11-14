-- CREATE TABLE kolon tanimlarini dikey hizalar.
--
--   CREATE TABLE t (
--       id         BIGSERIAL PRIMARY KEY,
--       created_at TIMESTAMP   NOT NULL DEFAULT now()
--   );
--
-- Yalnizca tek satirlik kolon tanimlari hizalanir; cok satirli tanimlar,
-- table-level constraint'ler ve yorumlu satirlar dokunulmadan birakilir.
-- Formatter zincirinin en sonunda calisir (sqlfluff -> sql_align).

local M = {}

local CONSTRAINT_WORDS = {
  CONSTRAINT = true,
  PRIMARY = true,
  FOREIGN = true,
  UNIQUE = true,
  CHECK = true,
  NOT = true,
  NULL = true,
  DEFAULT = true,
  REFERENCES = true,
  GENERATED = true,
  COLLATE = true,
  DEFERRABLE = true,
  INITIALLY = true,
  EXCLUDE = true,
  LIKE = true,
}

---@param text string
---@return integer
local function width(text)
  return vim.fn.strdisplaywidth(text)
end

---Parantez/dize disindaki ilk constraint kelimesinin baslangic pozisyonu.
---@param rest string
---@return integer|nil
local function constraint_start(rest)
  local index, depth, quote = 1, 0, nil
  while index <= #rest do
    local char = rest:sub(index, index)
    if quote then
      if char == quote then
        quote = nil
      end
    elseif char == "'" or char == '"' then
      quote = char
    elseif char == "(" or char == "[" then
      depth = depth + 1
    elseif char == ")" or char == "]" then
      depth = math.max(0, depth - 1)
    elseif depth == 0 and char:match("[%a_]") and not rest:sub(index - 1, index - 1):match("[%w_%.]") then
      local word = rest:match("^[%a_]+", index)
      if word and CONSTRAINT_WORDS[word:upper()] then
        return index
      end
      index = index + #word - 1
    end
    index = index + 1
  end
  return nil
end

---@param line string
---@return { indent: string, name: string, type: string, constraints: string, comma: boolean }|nil
local function parse_column(line)
  local indent, content = line:match("^(%s*)(.*)$")
  if content == "" or content:find("--", 1, true) then
    return nil
  end

  local comma = content:match(",%s*$") ~= nil
  content = content:gsub(",%s*$", "")

  local name, rest
  if content:sub(1, 1) == '"' then
    name, rest = content:match('^(".-")%s+(.*)$')
  else
    name, rest = content:match("^([%w_$%.]+)%s+(.*)$")
  end
  if not name or not rest then
    return nil
  end
  if CONSTRAINT_WORDS[name:upper()] then
    return nil
  end

  local start = constraint_start(rest)
  local type = start and rest:sub(1, start - 1) or rest
  local constraints = start and rest:sub(start) or ""
  type = type:gsub("%s+$", "")
  if type == "" then
    return nil
  end

  return { indent = indent, name = name, type = type, constraints = constraints, comma = comma }
end

---@param lines string[]
---@param first integer
---@param last integer
local function align_block(lines, first, last)
  ---@type { index: integer, column: table }[]
  local columns = {}

  for index = first, last do
    local line = lines[index]
    if line:match("%S") then
      local indent = #(line:match("^%s*"))
      local next_line = lines[index + 1] or ""
      local next_indent = #(next_line:match("^%s*"))
      local continuation = next_line:match("%S") ~= nil and next_indent > indent
      local ends_block = next_line:match("^%s*%)") ~= nil
      local column = parse_column(line)

      if column and not continuation and (column.comma or ends_block) then
        columns[#columns + 1] = { index = index, column = column }
      end
    end
  end

  if #columns < 2 then
    return
  end

  local name_width, type_width = 0, 0
  for _, entry in ipairs(columns) do
    name_width = math.max(name_width, width(entry.column.name))
    type_width = math.max(type_width, width(entry.column.type))
  end

  for _, entry in ipairs(columns) do
    local column = entry.column
    local constraints = ""
    if column.constraints ~= "" then
      constraints = string.rep(" ", type_width - width(column.type) + 1) .. column.constraints
    end
    local line = column.indent
      .. column.name
      .. string.rep(" ", name_width - width(column.name) + 1)
      .. column.type
      .. constraints
      .. (column.comma and "," or "")
    lines[entry.index] = line:gsub("%s+$", "")
  end
end

---@param lines string[]
---@return string[]
function M.align(lines)
  local result = vim.deepcopy(lines)
  local index = 1

  while index <= #result do
    if result[index]:lower():match("^%s*create%s+table%s") then
      local open = index
      while open <= #result and not result[open]:find("(", 1, true) do
        open = open + 1
      end

      if open <= #result then
        local depth, close = 0, nil
        local line = open
        while line <= #result and not close do
          local text = result[line]:gsub("'[^']*'", "")
          for char in text:gmatch("[()]") do
            depth = depth + (char == "(" and 1 or -1)
          end
          if depth <= 0 then
            close = line
          end
          line = line + 1
        end

        if close and close > open + 1 then
          align_block(result, open + 1, close - 1)
          index = close + 1
        end
      end
    end
    index = index + 1
  end

  return result
end

return M
