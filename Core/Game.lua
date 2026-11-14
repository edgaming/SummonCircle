-- Summon Circle: the thin layer over WoW's API. Anything that depends on
-- which client we're on (Forever runs the Midnight client) lives here.
local ADDON, ns = ...

ns.SHARD_ITEM = 6265   -- Soul Shard item
ns.SUMMON_SPELL = 698  -- Ritual of Summoning

-- Prefer namespaced APIs where Midnight moved them; fall back to globals.
ns.API = {
  SendChat   = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage,
  Invite     = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit,
  Uninvite   = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit,
  ConvertToRaid = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid,
  ItemCount  = (C_Item and C_Item.GetItemCount) or GetItemCount,
  SpellName  = function(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
  end,
}

-- Midnight "secret values": anything we can't inspect, we ignore.
function ns.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

-- Leader/assist checks that also cover dungeon-finder ("instance") groups.
local INSTANCE = LE_PARTY_CATEGORY_INSTANCE
function ns.IsGroupLeader(unit)
  if UnitIsGroupLeader(unit) then return true end
  return INSTANCE ~= nil and UnitIsGroupLeader(unit, INSTANCE) == true
end
function ns.IsGroupAssistant(unit)
  if UnitIsGroupAssistant(unit) then return true end
  return INSTANCE ~= nil and UnitIsGroupAssistant(unit, INSTANCE) == true
end

-- One way to turn any unit into a name key, used for me AND everyone in
-- the group, so two-word names ("Ash Lock") always match up.
function ns.UnitKey(unit)
  local n = GetUnitName(unit, true)
  if not n or ns.IsSecret(n) or n == "" or n == UNKNOWNOBJECT then return nil end
  return ns.Full(n)
end

function ns.Me()
  if not ns.me then ns.me = ns.UnitKey("player") end
  return ns.me or ns.Full(UnitName("player"))
end

function ns.SummonName()
  return ns.API.SpellName(ns.SUMMON_SPELL) or "Ritual of Summoning"
end

function ns.IsSummonSpell(id)
  if not id or ns.IsSecret(id) then return false end
  if id == ns.SUMMON_SPELL then return true end
  return ns.API.SpellName(id) == ns.SummonName()
end

function ns.GetShards()
  local n = ns.API.ItemCount(ns.SHARD_ITEM) or 0
  if n == 0 and Enum.PowerType and Enum.PowerType.SoulShards then
    local ok, p = pcall(UnitPower, "player", Enum.PowerType.SoulShards)
    if ok and type(p) == "number" and not ns.IsSecret(p) and p > 0 then n = p end
  end
  return n
end

function ns.Whisper(text, name)
  ns.API.SendChat(text, "WHISPER", nil, name)
end
