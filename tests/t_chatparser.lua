-- Every line in tests/chat_lines.txt against ChatParser.Classify.
Boot()
local P, Loc = ns.ChatParser, ns.Locations

local n = 0
for line in io.lines(ADDON_DIR .. "/tests/chat_lines.txt") do
  local city, verdict, text = line:match("^%s*(%w+)%s*|%s*([^|]-)%s*|%s*(.-)%s*$")
  if city and not line:match("^%s*#") then
    n = n + 1
    local want, wantOffer = verdict:match("^(%a+)%s*(%d*)$")
    local got, reason = P.Classify(text, Loc.Get(city))
    local label = ("%s: %q"):format(city, text)
    if want == "yes" then
      check(label .. " is a request", got ~= nil)
      if got and wantOffer ~= "" then eq(label .. " offers", got.offer, tonumber(wantOffer)) end
    else
      check(label .. " is not a request (" .. tostring(reason) .. ")", got == nil)
    end
  end
end
check("fixture file has lines", n > 30)

-- Our own ad isn't a request, even with the WTS edited out.
local fp = P.AdFingerprint("Summons to {city} - {price} - whisper 'inv' for instant invite{queue}")
eq("fingerprint: longest run of 3+ words", fp, "whisper inv for instant invite")
check("own ad wording skipped", P.Classify("Summons to UC - 30s - whisper 'inv' for instant invite", Loc.Get("undercity"), fp) == nil)
check("buyer still matches with a fingerprint", P.Classify("WTB summon to UC", Loc.Get("undercity"), fp) ~= nil)
eq("fingerprint: short segments ignored", P.AdFingerprint("Summons {city} {price}"), nil)

-- Intent is noted, not required.
check("intent: wtb", P.Classify("wtb uc summon", Loc.Get("undercity")).intent)
check("intent: plain statement", not P.Classify("summon uc", Loc.Get("undercity")).intent)
check("no city: nothing", P.Classify("WTB summon to UC", nil) == nil)
check("not a string: nothing", P.Classify(nil, Loc.Get("undercity")) == nil)
