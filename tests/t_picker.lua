local function check(label, cond) print((cond and "PASS " or "FAIL ") .. label) end
local function has(list, name) for _, n in ipairs(list) do if n == name then return true end end return false end

GROUP = {
  { name = "Ash Lock", leader = true },
  { name = "Bram Lock" },                       -- warlock friend: pickable
  { name = "Holy Priest", class = "PRIEST" },   -- not a warlock
  { name = "Frost Mage", class = "MAGE" },      -- not a warlock
  { name = "Bob Smith" },                       -- warlock, but a customer in the queue
}
LoadAddon(ADDON_DIR)
FireEvent("ADDON_LOADED", "SummonCircle"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD", true, false)
FireEvent("GROUP_ROSTER_UPDATE")
ns.S.queue["Bob Smith"] = { name = "Bob Smith", added = 1, status = "GROUP" }

for _, mode in ipairs({ "party", "raid" }) do
  RAID = (mode == "raid")
  FireEvent("GROUP_ROSTER_UPDATE")
  local c = ns:SummonerCandidates()
  check(mode .. ": I'm listed first", c[1] == "Ash Lock")
  check(mode .. ": warlock friend listed", has(c, "Bram Lock"))
  check(mode .. ": priest hidden", not has(c, "Holy Priest"))
  check(mode .. ": mage hidden", not has(c, "Frost Mage"))
  check(mode .. ": warlock customer hidden", not has(c, "Bob Smith"))
  check(mode .. ": exactly 2 people", #c == 2)
end
