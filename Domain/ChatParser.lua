-- Summon Circle: does a chat line ask for a summon to our city?
--
-- Pure function, no game calls, so every rule is testable line by line
-- (tests/chat_lines.txt). A line is a request only if it
--   1. doesn't look like someone selling (or a guild recruiting),
--   2. names a summon (or a portal: a summon gets them here just as well),
--   3. names our city (ambiguous nicknames like "if" only next to a summon word).
-- Buying intent and an offered price are noted but not required.
local ADDON, ns = ...
local ChatParser = ns:Module("ChatParser")

local function set(list)
  local t = {}
  for _, w in ipairs(list) do t[w] = true end
  return t
end

ChatParser.SELLING = set { "wts", "selling", "lfw", "recruiting", "recruit" }
ChatParser.SUMMON = set { "summon", "summons", "summ", "sum", "summo", "lock", "warlock", "port", "portal" }
ChatParser.INTENT = set { "wtb", "lf", "need", "buying", "anyone" }

local function tokens(text)
  local out = {}
  for w in ns.Locations.Normalize(text):gmatch("%S+") do out[#out + 1] = w end
  return out
end
ChatParser.Tokens = tokens

-- Does the token sequence `alias` appear in `words`? Returns its first and
-- last index.
local function find(words, alias)
  local n = #alias
  for i = 1, #words - n + 1 do
    local hit = true
    for k = 1, n do
      if words[i + k - 1] ~= alias[k] then hit = false; break end
    end
    if hit then return i, i + n - 1 end
  end
end

local function namesCity(words, city)
  local risky = set(city.ambiguous or {})
  for _, alias in ipairs(city.aliases) do
    local a, b = find(words, tokens(alias))
    if a then
      if not risky[alias] then return true end
      -- "if" is a common word: only trust it right next to a summon word.
      if ChatParser.SUMMON[words[a - 1] or ""] or ChatParser.SUMMON[words[b + 1] or ""] then return true end
    end
  end
  return false
end

-- "20s", "1g", "1g50s", "1g 50s" -> copper. Bare numbers aren't prices.
local function offer(words)
  local run = {}
  for _, w in ipairs(words) do
    local isMoney = w:match("^[%dgsc]+$") and w:match("%d") and w:match("[gsc]$") and ns.ParseMoney(w)
    if isMoney then
      run[#run + 1] = w
    elseif #run > 0 then
      break
    end
  end
  if #run > 0 then return ns.ParseMoney(table.concat(run, " ")) end
end

-- A run of 3+ words from our own ad (between the {placeholders}), so a
-- copy of our ad posted by someone else isn't taken for a request.
function ChatParser.AdFingerprint(adText)
  if type(adText) ~= "string" then return nil end
  local best
  for seg in (adText .. "{"):gmatch("([^{}]*){") do
    local norm = ns.Locations.Normalize(seg):match("^%s*(.-)%s*$")
    local n = select(2, norm:gsub("%S+", ""))
    if n >= 3 and (not best or #norm > #best) then best = norm end
  end
  return best
end

-- Returns { offer = copper|nil, intent = bool } for a request,
-- or nil, reason ("selling", "no summon", "no city", "empty").
function ChatParser.Classify(text, city, adFingerprint)
  if type(text) ~= "string" or text == "" or not city then return nil, "empty" end
  local words = tokens(text)
  for _, w in ipairs(words) do
    if ChatParser.SELLING[w] then return nil, "selling" end
  end
  if adFingerprint and ns.Locations.Normalize(text):find(" " .. adFingerprint .. " ", 1, true) then
    return nil, "selling"
  end
  local summon = false
  for _, w in ipairs(words) do
    if ChatParser.SUMMON[w] then summon = true; break end
  end
  if not summon then return nil, "no summon" end
  if not namesCity(words, city) then return nil, "no city" end

  local price = offer(words)
  local intent = price ~= nil or text:find("?", 1, true) ~= nil
  for _, w in ipairs(words) do
    if ChatParser.INTENT[w] then intent = true end
  end
  return { offer = price, intent = intent }
end
