-- kumiko: the Kanban board of the focused pane's repository, from the terminal.
--
-- leader K   (shift+k) a picker over the board's cards still to start or under way
--            (Kumiko's active columns first, then intake); choosing one types
--            `<id> ("<title>")` into the pane, without Enter, the way a card
--            is named in a commit or in a message to an agent.
-- In the palette (leader :): `card [board]` is the same picker, on another
-- board when one is named; `board [board]` opens a screen of those cards by
-- column, with each one's labels, description and checklist under it. On it:
--   enter  type the reference into the pane     y  copy it
--   v      the card whole: description, checklist (esc comes back; enter, y)
--   p      pin it to the bar (again: unpin)      w  open it in the browser
--   r      fetch again
-- The bar: a module named `kumiko` shows the repository's In Progress card
-- (the pinned one, else the first), cut to kumiko.width, and `+N` for the
-- others; a click opens the screen. It fetches when focus or a pane's
-- directory moves to a repository it has not fetched, and every
-- kumiko.refresh seconds, only while the bar shows it, never per frame.
--
-- Another key: ranma.bind(KEY, function() ranma.emit("kumiko_card") end), or
-- "kumiko_board" for the screen; a board's slug as emit's data names one.
--
-- Which board: kumiko.boards maps a repository's directory name to a board
-- slug (`kumiko=work-hours *.ranma=ranma`); any other repository uses the
-- board whose slug is its name, and with none the picker asks which board. A
-- worktree counts as its main checkout. Pins are kept in ranma.store("kumiko").
-- Read-only: it never creates, moves or edits a card. The API token is read
-- from the environment variable kumiko.token_env and reaches curl on its
-- stdin, never in a process's arguments.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pickers and
-- prompts", "Screens", "Timers and processes", "The bar").

ranma.option("kumiko.url", {
  type = "string", default = "https://kumiko.ink/api/kanban",
  name = "API", desc = "The Kanban API's base URL: /boards and /cards are under it.",
})
ranma.option("kumiko.token_env", {
  type = "string", default = "LATTICE_MCP_TOKEN",
  name = "Token variable", desc = "The environment variable holding the API token, in the environment ranma's server started with.",
})
ranma.option("kumiko.boards", {
  type = "string",
  default = "kumiko=work-hours wayfarer=main kuji=rents-due hansei=heimdall kizuna=ai-session *.ranma=ranma",
  name = "Boards", desc = "repository=board pairs, space-separated; *.suffix matches the end of a name. Any other repository uses the board named like it.",
})
ranma.option("kumiko.refresh", {
  type = "int", min = 30, max = 3600, step = 30, default = 300, slider = false,
  name = "Refresh", desc = "Seconds between the bar's fetches of a board.",
})
ranma.option("kumiko.width", {
  type = "int", min = 8, max = 80, default = 32,
  name = "Bar width", desc = "The most characters of a card's title the bar shows.",
})

local store = ranma.store("kumiko")

local function fail(err)
  ranma.toast("kumiko: " .. tostring(err), { urgent = true })
end

-- The characters of a string, at most n of them, the last an ellipsis when cut.
local function cut(s, n)
  local len = utf8.len(s)
  if not len then return s:sub(1, n) end
  if len <= n then return s end
  return s:sub(1, utf8.offset(s, n) - 1) .. "…"
end

local function encode(s)
  return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- An open that works on a directory too (reading it then fails with EISDIR).
local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

-- A directory's repository name, by the nearest .git above it; cached, since
-- the bar asks on every tick.
local repos = {}
local function repo_of(cwd)
  if not cwd then return nil end
  local known = repos[cwd]
  if known ~= nil then return known or nil end
  local dir, name = cwd, false
  while dir ~= "" do
    local git = dir .. "/.git"
    if exists(git) then
      -- A worktree's .git is a file pointing into its main checkout's .git.
      local text = read(git)
      local main = text and text:match("gitdir:%s*(.-)/%.git/worktrees/")
      name = (main or dir):match("[^/]+$") or false
      break
    end
    dir = dir:match("^(.*)/[^/]*$") or ""
  end
  repos[cwd] = name
  return name or nil
end

-- The board slug for a repository, and whether kumiko.boards named it.
local function board_for(repo)
  local suffixed
  for pair in ranma.get("kumiko.boards"):gmatch("%S+") do
    local key, slug = pair:match("^(.-)=(.+)$")
    if key == repo then return slug, true end
    local tail = key and key:match("^%*(.+)$")
    if tail and not suffixed and #repo > #tail and repo:sub(-#tail) == tail then suffixed = slug end
  end
  if suffixed then return suffixed, true end
  return repo, false
end

-- The focused pane, its board's slug and whether that was mapped, or nil.
local function here()
  local p = ranma.pane()
  if not p then return nil end
  local repo = repo_of(p:cwd())
  if not repo then return p end
  return p, board_for(repo)
end

-- GET a path under kumiko.url; done(data) or done(nil, why, status).
local function fetch(path, done)
  local var = ranma.get("kumiko.token_env")
  if not var:match("^[%a_][%w_]*$") then return done(nil, "kumiko.token_env is not a variable name: " .. var) end
  if (os.getenv(var) or "") == "" then return done(nil, var .. " is not set in ranma's environment") end
  local url = ranma.get("kumiko.url"):gsub("/+$", "") .. path
  -- printf is the shell's own, so the token goes down the pipe and never
  -- into an argument list `ps` would show.
  local script = [[printf 'header = "Authorization: Bearer %s"\n' "$]] .. var
    .. [[" | curl -sS --max-time 15 -w '\n%{http_code}' --config - -- "$1"]]
  ranma.spawn({ "sh", "-c", script, "sh", url }, {
    timeout = 20,
    on_exit = function(r)
      if r.error then return done(nil, r.error) end
      if r.code ~= 0 then
        local why = (r.stderr or ""):gsub("%s+$", "")
        return done(nil, why ~= "" and why or "curl failed")
      end
      local body, status = (r.stdout or ""):match("^(.*)\n(%d+)$")
      local ok, data = pcall(ranma.json.decode, body or "")
      if status ~= "200" then
        local why = ok and type(data) == "table" and type(data.error) == "table" and data.error.message
        return done(nil, why or ("HTTP " .. tostring(status)), status)
      end
      if not ok or type(data) ~= "table" then return done(nil, "the answer was not JSON") end
      done(data)
    end,
  })
end

local FIELDS = "title,columnTitle,description,checklist,labels"

-- The board's active cards, then its intake ones: two requests, since a card
-- does not say its column's role and the API lists by priority across columns.
local function cards(slug, done)
  local function get(role, next)
    fetch("/cards?board=" .. encode(slug) .. "&role=" .. role .. "&fields=" .. FIELDS, function(data, err, status)
      if not data then return done(nil, err, status) end
      next(data.cards or {})
    end)
  end
  get("active", function(active)
    get("intake", function(intake)
      for _, c in ipairs(intake) do active[#active + 1] = c end
      done(active)
    end)
  end)
end

local boards = {}   -- slugs, for the palette's completion, once fetched

-- The boards, as picker items; the slugs are kept for the palette too.
local function list_boards(done)
  fetch("/boards", function(data, err)
    if not data then return done(nil, err) end
    local items = {}
    boards = {}
    for _, b in ipairs(data.boards or {}) do
      local slug = b.slug
      if slug then
        boards[#boards + 1] = slug
        items[#items + 1] = { label = b.name or slug, detail = slug, slug = slug }
      end
    end
    done(items)
  end)
end

local function choose_board(title, done)
  list_boards(function(items, err)
    if not items then return fail(err) end
    ranma.picker { title = title, items = items, on_select = function(item) done(item.slug) end }
  end)
end

-- The cards of a board named, or of the focused pane's, asking which board
-- when there is none or the guessed one does not exist.
local function with_cards(arg, done)
  if #boards == 0 then list_boards(function() end) end
  local named = arg and arg:match("^%s*(%S+)")
  local _, slug, mapped = here()
  slug = named or slug
  local function go(s, guessed)
    cards(s, function(list, err, status)
      if list then return done(s, list) end
      if guessed and status == "404" then
        return choose_board("kumiko: no board " .. s .. "; which one?", function(b) go(b, false) end)
      end
      fail(s .. ": " .. err)
    end)
  end
  if not slug then return choose_board("kumiko: which board?", function(b) go(b, false) end) end
  go(slug, not named and not mapped)
end

local function ref(card)
  return card.id .. ' ("' .. (card.title or "") .. '")'
end

-- Types the reference into a pane, without Enter: the line is the user's to finish.
local function type_ref(p, card)
  if not (p and p:alive()) then return fail("the pane is gone") end
  p:send(ref(card))
end

local function pick(arg)
  local p = ranma.pane()
  with_cards(arg, function(slug, list)
    if #list == 0 then return ranma.toast("kumiko: nothing open on " .. slug) end
    local items = {}
    for _, c in ipairs(list) do
      items[#items + 1] = { label = c.title or c.id, detail = (c.columnTitle or "") .. "  " .. c.id, card = c }
    end
    ranma.picker {
      title = slug,
      items = items,
      on_select = function(item) type_ref(p, item.card) end,
    }
  end)
end

-- The bar ------------------------------------------------------------------

local bar = {}       -- slug -> { at = os.time(), cards = { ... } }
local fetching = {}
local shown = 0      -- when the module last rendered: the bar shows it

local function pins() return store:get("pins") or {} end

local function refresh(slug, force)
  if os.time() - shown > 10 or not slug or fetching[slug] then return end
  local c = bar[slug]
  if c and not force and os.time() - c.at < ranma.get("kumiko.refresh") then return end
  fetching[slug] = true
  fetch("/cards?board=" .. encode(slug) .. "&role=active&fields=title,columnTitle", function(data)
    fetching[slug] = nil
    -- A failure is kept as nothing until the next refresh, not retried every tick.
    bar[slug] = { at = os.time(), cards = data and data.cards or {} }
  end)
end

local function refresh_here()
  local _, slug = here()
  refresh(slug)
end

local open_screen

ranma.module("kumiko", {
  interval = 2,
  render = function()
    shown = os.time()
    local _, slug = here()
    if not slug then return nil end
    local c = bar[slug]
    if not c then refresh(slug) return nil end
    local list = c.cards
    if #list == 0 then return nil end
    local pin, card = pins()[slug], list[1]
    for _, k in ipairs(list) do
      if k.id == pin then card = k end
    end
    local text = "◆ " .. cut(card.title or card.id, ranma.get("kumiko.width"))
    if #list > 1 then text = text .. " +" .. (#list - 1) end
    return { text = text, style = card.id == pin and "accent" or "normal" }
  end,
  on_click = function() open_screen() end,
})

ranma.on("focus_change", refresh_here)
ranma.on("cwd_change", refresh_here)
ranma.every(30000, refresh_here)

-- The screen ---------------------------------------------------------------

local screen = { s = nil, slug = nil, list = nil, pane = nil }

local function by_id(id)
  for _, c in ipairs(screen.list or {}) do
    if c.id == id then return c end
  end
end

local function open_url(url)
  if ranma.client().remote then
    ranma.copy(url)
    return ranma.toast("kumiko: ranma runs elsewhere; copied the address instead")
  end
  ranma.spawn({ "xdg-open", url }, { timeout = 10 })
end

-- A card's checklist: how many are done, and one line per item.
local function checklist(c)
  local done, lines = 0, {}
  for _, item in ipairs(c.checklist or {}) do
    if item.done == true then done = done + 1 end
    lines[#lines + 1] = (item.done == true and "✓ " or "· ") .. (item.text or "")
  end
  return done, lines
end

local function label_names(c)
  local names = {}
  for _, l in ipairs(c.labels or {}) do names[#names + 1] = l.name or "?" end
  return names
end

local function facts(c, names)
  return { "facts", { "card", c.id }, { "column", c.columnTitle or "" },
    { "labels", #names > 0 and table.concat(names, ", ") or "none" } }
end

-- Cards come by priority, not by column: gather them by column, the columns
-- in the order they first appear (the active ones lead, as cards() fetches).
local function by_column(list)
  local order, groups = {}, {}
  for _, c in ipairs(list) do
    local col = c.columnTitle or ""
    if not groups[col] then
      groups[col] = {}
      order[#order + 1] = col
    end
    table.insert(groups[col], c)
  end
  return order, groups
end

local function body(keys)
  local out = {}
  local pinned = pins()[screen.slug]
  local order, groups = by_column(screen.list)
  for _, col in ipairs(order) do
    out[#out + 1] = { "heading", col, count = #groups[col] }
    for _, c in ipairs(groups[col]) do
      local done, lines = checklist(c)
      local names = label_names(c)
      local detail = { facts(c, names) }
      local desc = (c.description or ""):gsub("%s+", " ")
      if desc ~= "" then detail[#detail + 1] = { "text", desc, max = 4 } end
      if #lines > 0 then
        detail[#detail + 1] = { "progress", label = "checklist", frac = done / #lines, num = done .. "/" .. #lines }
      end
      out[#out + 1] = {
        "row", id = c.id, name = c.title or c.id,
        mark = c.id == pinned and { "◆", "accent" } or nil,
        note = #names > 0 and table.concat(names, " ") or nil,
        value = #lines > 0 and { done .. "/" .. #lines, "dim" } or nil,
        keys = keys,
        detail = detail,
      }
    end
  end
  return out
end

-- One card whole: its description line by line, then its checklist.
local function view(c)
  local done, lines = checklist(c)
  local out = { { "heading", c.title or c.id }, facts(c, label_names(c)), { "separator" } }
  local desc = c.description or ""
  if desc == "" then
    out[#out + 1] = { "text", "No description.", "dim" }
  else
    for line in (desc .. "\n"):gmatch("(.-)\r?\n") do
      out[#out + 1] = line == "" and { "space" } or { "text", line }
    end
  end
  if #lines > 0 then
    out[#out + 1] = { "separator" }
    out[#out + 1] = { "progress", label = "checklist", frac = done / #lines, num = done .. "/" .. #lines }
    for _, l in ipairs(lines) do out[#out + 1] = { "text", l } end
  end
  return out
end

local show

local function close()
  if screen.s then screen.s:close() end
  screen.s = nil
end

-- The keys every row has; each finds its card by the row's id.
local ROW_KEYS = {
  { "enter", "type it", function(id)
    local c = by_id(id)
    if not c then return end
    close()
    type_ref(screen.pane, c)
  end },
  { "v", "view", function(id)
    local c = by_id(id)
    if c and screen.s then
      screen.s:push {
        body = view(c), subtitle = c.id, filter = false,
        keys = {
          { "enter", "type it", function() close() type_ref(screen.pane, c) end },
          { "y", "copy", function() ranma.copy(ref(c)) ranma.toast("kumiko: copied " .. c.id) end },
        },
      }
    end
  end },
  { "y", "copy", function(id)
    local c = by_id(id)
    if c then ranma.copy(ref(c)) ranma.toast("kumiko: copied " .. c.id) end
  end },
  { "p", "pin", function(id)
    local all = pins()
    all[screen.slug] = all[screen.slug] ~= id and id or nil
    store:set("pins", all)
    show(screen.slug, screen.list)
  end },
  { "w", "browser", function(id)
    local c = by_id(id)
    local url = c and c.url
    if url then open_url(url) end
  end },
}

function show(slug, list)
  screen.slug, screen.list = slug, list
  local t = { title = "kumiko · " .. slug, body = body(ROW_KEYS),
              count = #list .. (#list == 1 and " card" or " cards") }
  if screen.s then return screen.s:set(t) end
  t.chip = "KANBAN"
  t.filter = "names"
  t.detail = 8
  t.options = true
  t.group = "kumiko"
  t.empty = "nothing open on this board"
  t.keys = {
    { "r", "fetch", function()
      cards(screen.slug, function(l, err)
        if not l then return fail(err) end
        if screen.s then show(screen.slug, l) end
        refresh(screen.slug, true)
      end)
    end },
  }
  t.card = {
    { "enter", "type `<id> (\"<title>\")` into the pane, no Enter" },
    { "v", "the card whole: description and checklist" },
    { "y", "copy that reference" },
    { "p", "pin the card to the bar; again unpins" },
    { "w", "open the card in the browser" },
    { "r", "fetch the board again" },
  }
  t.on_close = function() screen.s = nil end
  screen.s = ranma.screen(t)
end

function open_screen(arg)
  screen.pane = ranma.pane()
  close()
  with_cards(arg, show)
end

-- The palette offers the boards' slugs; the first time, they are not fetched
-- yet, so this starts the fetch for the next time.
local function complete()
  if #boards == 0 then pcall(list_boards, function() end) end
  return boards
end

ranma.command("card", pick, { desc = "a Kumiko card's reference, typed into the pane", args = "[board]", complete = complete })
ranma.command("board", open_screen, { desc = "the Kumiko board of this repository", args = "[board]", complete = complete })

-- For a key of your own: ranma.bind("<key>", function() ranma.emit("kumiko_card") end),
-- with a board's slug as the data to name one; "kumiko_board" for the screen.
local function slug_of(data) return type(data) == "string" and data or nil end
ranma.on("user:kumiko_card", function(data) pick(slug_of(data)) end)
ranma.on("user:kumiko_board", function(data) open_screen(slug_of(data)) end)

-- WM mode ends as the picker opens: it has the keyboard from there.
ranma.bind("shift+k", function() pick() end, { desc = "kumiko card", exit = true })
