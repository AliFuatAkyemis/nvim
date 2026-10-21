-- LSP: alti cizili eksik sembol icin import code action'i.
--
-- <M-CR>      : menusuz, akilli secimle import ekler (mevcut import satiriyla
--               eslesen modul once, yoksa sunucunun ilk adayi).
-- <C-M-CR>    : tum code action listesini acar.

local M = {}

--- @param action table
--- @return boolean
function M.is_import_action(action)
  local title = ((action and action.title) or ""):lower()
  if title == "" or not title:find("import", 1, true) then
    return false
  end
  -- quickfix disi aksiyonlar (source.*, refactor.*) import degildir. Baslikta
  -- proje adi yuzunden "import" gecebilir; kind varsa onu esas al.
  local kind = action and action.kind
  if kind and kind ~= "quickfix" and not vim.startswith(kind, "quickfix.") then
    return false
  end
  if
    title:find("unused", 1, true)
    or title:find("organize imports", 1, true)
    or title:find("organise imports", 1, true)
    or title:find("optimize imports", 1, true)
  then
    return false
  end
  return true
end

--- Imlecin altindaki/bitisigindeki diagnostic'i dondurur.
--- @param bufnr integer
--- @param cursor integer[] {row, col} (1,0-indexed)
--- @param insert boolean insert modda imlec ekleme noktasidir
--- @return table?
function M.diagnostic_at(bufnr, cursor, insert)
  local row, col = cursor[1], cursor[2]
  local positions = { col }
  if insert and col > 0 then
    -- Insert imleci karakterin ustunde veya ekleme noktasinda olabilir; iki
    -- konumu da dene. Boylece kelimenin ilk karakteri de sonu da kapsanir.
    table.insert(positions, col - 1)
  end

  local best, best_dist
  for _, d in ipairs(vim.diagnostic.get(bufnr, { lnum = row - 1 })) do
    local start_col = d.col
    local end_col = d.end_col or d.col
    for _, pos in ipairs(positions) do
      if start_col <= pos and pos < end_col then
        local dist = math.abs(pos - start_col)
        if not best or dist < best_dist then
          best, best_dist = d, dist
        end
        break
      end
    end
  end
  return best
end

--- Altindaki diagnostic'e gore code action icin hedef konumu dondurur.
--- @param bufnr integer
--- @param cursor integer[] {row, col} (1,0-indexed)
--- @param insert boolean insert modda imlec ekleme noktasidir
--- @return integer[]? {row, col}
function M.target_position(bufnr, cursor, insert)
  local d = M.diagnostic_at(bufnr, cursor, insert)
  if d then
    return { d.lnum + 1, d.col }
  end
  return nil
end

--- Aksiyon basligindaki modul/sembol token'larini cikarir.
--- @param title string
--- @return string[]
local function action_tokens(title)
  local tokens = {}
  for t in title:gmatch("[\"'`]([^\"'`]+)[\"'`]") do
    table.insert(tokens, t)
  end
  for t in title:gmatch("%(([%w_%.]+)%)") do
    table.insert(tokens, t)
  end
  return tokens
end

--- Dosyadaki import benzeri satirlari birlestirir (skor referansi).
--- @param lines string[]
--- @return string
local function import_text(lines)
  local parts = {}
  for _, line in ipairs(lines) do
    if
      line:match("^%s*#include")
      or line:match("^%s*import")
      or line:match("^%s*from")
      or line:match("^%s*use%s")
      or line:match("^%s*using")
      or line:match("^%s*require")
      or line:match("^%s*package")
    then
      table.insert(parts, line)
    end
  end
  return table.concat(parts, "\n")
end

--- Adaylar arasindan en iyisini secer: basligindaki token dosyada zaten
--- kullanilan bir import satirinda geciyorsa o aday one cikar. Esitlikte ve
--- hic eslesme yoksa ilk aday korunur (sunucu sirasi).
--- @param candidates table[] {action, client_id}
--- @param lines string[] buffer satirlari
--- @return table?
function M.pick_import_action(candidates, lines)
  if #candidates == 0 then
    return nil
  end
  local text = import_text(lines)
  local best, best_score
  for _, entry in ipairs(candidates) do
    local score = 0
    for _, token in ipairs(action_tokens(entry.action.title or "")) do
      if text:find(token, 1, true) then
        score = score + #token
      end
    end
    if not best or score > best_score then
      best, best_score = entry, score
    end
  end
  return best
end

--- buf_request_all sonuclarindan {action, client_id} listesi cikarir.
--- @param results table<integer, {err: table?, result: table?}>
--- @return table[]
function M.action_entries(results)
  local entries = {}
  for client_id, res in pairs(results) do
    for _, action in ipairs(res.result or {}) do
      table.insert(entries, { action = action, client_id = client_id })
    end
  end
  return entries
end

--- Secilen aksiyonu uygular (resolve gerekiyorsa once resolve eder).
--- @param entry table {action, client_id}
--- @param bufnr integer
function M.apply_action(entry, bufnr)
  local client = vim.lsp.get_client_by_id(entry.client_id)
  if not client then
    return
  end

  local function do_apply(action)
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
    end
    local cmd = action.command
    if cmd then
      local command = type(cmd) == "table" and cmd or action
      client:exec_cmd(command, { bufnr = bufnr })
    end
  end

  local action = entry.action
  if not (action.edit and action.command) and client:supports_method("codeAction/resolve") then
    client:request("codeAction/resolve", action, function(err, resolved)
      if err then
        if action.edit or action.command then
          do_apply(action)
        else
          vim.notify(err.message, vim.log.levels.ERROR)
        end
      else
        do_apply(resolved)
      end
    end, bufnr)
  else
    do_apply(action)
  end
end

--- Code action istegi icin konum/params uretir.
--- @param bufnr integer
--- @param pos integer[] {row, col}
--- @param diag table?
--- @return fun(client: table): table
local function params_fn(bufnr, pos, diag)
  local diagnostics = {}
  if diag and diag.user_data and diag.user_data.lsp then
    diagnostics = { diag.user_data.lsp }
  end
  return function(client)
    local params = vim.lsp.util.make_given_range_params(pos, pos, bufnr, client.offset_encoding)
    params.context = {
      diagnostics = diagnostics,
      triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
    }
    return params
  end
end

--- Code action listesini Telescope picker ile gosterir; Telescope yoksa
--- vim.ui.select'e duser.
--- @param entries table[]
--- @param bufnr integer
function M.show_actions(entries, bufnr)
  local ok_pickers, pickers = pcall(require, "telescope.pickers")
  local ok_finders, finders = pcall(require, "telescope.finders")
  local ok_conf, conf = pcall(require, "telescope.config")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_state, action_state = pcall(require, "telescope.actions.state")

  if not (ok_pickers and ok_finders and ok_conf and ok_actions and ok_state) then
    vim.ui.select(entries, {
      prompt = "Code actions:",
      format_item = function(entry)
        return entry.action.title
      end,
    }, function(choice)
      if choice then
        M.apply_action(choice, bufnr)
      end
    end)
    return
  end

  pickers
    .new({}, {
      prompt_title = "Code actions",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.action.title,
            ordinal = entry.action.title,
          }
        end,
      }),
      sorter = conf.values.generic_sorter({}),
      previewer = false,
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            M.apply_action(selection.value, bufnr)
          end
        end)
        return true
      end,
    })
    :find()
end

--- <M-CR>: menusuz import ekle.
function M.run()
  local bufnr = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" }) == 0 then
    return
  end

  local original = vim.api.nvim_win_get_cursor(0)
  local insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
  local diag = M.diagnostic_at(bufnr, original, insert)
  local pos = diag and { diag.lnum + 1, diag.col } or original

  vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", params_fn(bufnr, pos, diag), function(results)
    local entries = {}
    for _, entry in ipairs(M.action_entries(results)) do
      if M.is_import_action(entry.action) then
        table.insert(entries, entry)
      end
    end

    if #entries == 0 then
      vim.notify("Import aksiyonu bulunamadi", vim.log.levels.INFO)
      return
    end

    local chosen = M.pick_import_action(entries, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    M.apply_action(chosen, bufnr)
    vim.notify("Import: " .. (chosen.action.title or ""), vim.log.levels.INFO)
  end)
end

--- <C-M-CR>: tum code action listesi (Telescope). Insert modda once normal
--- moda gecer ki picker girdisi kullanilabilir olsun.
function M.actions()
  local bufnr = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" }) == 0 then
    return
  end

  local original = vim.api.nvim_win_get_cursor(0)
  local insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
  if insert then
    vim.cmd("stopinsert")
  end
  local diag = M.diagnostic_at(bufnr, original, insert)
  local pos = diag and { diag.lnum + 1, diag.col } or original

  vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", params_fn(bufnr, pos, diag), function(results)
    local entries = M.action_entries(results)
    if #entries == 0 then
      vim.notify("Code action bulunamadi", vim.log.levels.INFO)
      return
    end
    M.show_actions(entries, bufnr)
  end)
end

return M
