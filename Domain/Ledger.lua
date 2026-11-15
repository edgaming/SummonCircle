-- Summon Circle: earnings. Payments are detected from completed trades:
-- whoever receives the gold gets the credit.
local ADDON, ns = ...
local Ledger = ns:Module("Ledger")
local Sync = ns.Sync

function Ledger.Get(name)
  local L = ns.S.ledger
  L[name] = L[name] or { copper = 0, summons = 0, shards = 0, failed = 0 }
  return L[name]
end

-- Session earnings in rotation order: { { name, copper } ... }, total, copper per hour.
function Ledger.Summary(names, now)
  local S = ns.S
  local rows, total = {}, 0
  for _, n in ipairs(names) do
    local L = S.ledger[n]
    if L and L.copper > 0 then
      total = total + L.copper
      rows[#rows + 1] = { name = n, copper = L.copper }
    end
  end
  local hours = math.max(((now or 0) - (S.sessionStart or now or 0)) / 3600, 1 / 60)
  return rows, total, total / hours
end

Sync.RegisterOp("PAID", function(m)
  local e = ns.S.queue[m.target]
  if e then e.status, e.paid = "PAID", m.amount end
  local L = Ledger.Get(m.caster)
  L.copper = L.copper + m.amount
  L.summons = L.summons + 1
end)

Sync.RegisterOp("RESET", function(m)
  ns.S.ledger = {}
  ns.S.sessionStart = m.at
end)

---------------------------------------------------------------------------
-- Payment detection
---------------------------------------------------------------------------
local trade = {}

ns.On("TRADE_SHOW", function()
  trade.partner = ns.UnitKey("NPC")
  trade.money = 0
end)
ns.On("TRADE_MONEY_CHANGED", function() trade.money = GetTargetTradeMoney() or 0 end)
ns.On("TRADE_ACCEPT_UPDATE", function() trade.money = GetTargetTradeMoney() or trade.money end)

ns.On("UI_INFO_MESSAGE", function(_, message)
  if message ~= ERR_TRADE_COMPLETE or not trade.partner then return end
  local name, amount = trade.partner, trade.money or 0
  trade.partner = nil
  if not ns.S.queue[name] or amount <= 0 then return end
  Sync.Do("PAID", { caster = ns.Me(), target = name, amount = amount })
  ns.db.lifetime.copper = ns.db.lifetime.copper + amount
  ns.db.lifetime.summons = ns.db.lifetime.summons + 1
  if amount < ns.S.price then
    ns.Print(("%s underpaid: %s of %s."):format(ns.Short(name), ns.Coins(amount), ns.Coins(ns.S.price)))
  end
end)
