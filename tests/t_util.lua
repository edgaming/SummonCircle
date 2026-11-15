-- Pure helpers: money, names, clocks.
Boot()

eq("money: 30s", ns.Money(3000), "30s")
eq("money: 1g35s", ns.Money(13500), "1g35s")
eq("money: 1g 2c", ns.Money(10002), "1g2c")
eq("money: zero", ns.Money(0), "0c")
eq("money: nil", ns.Money(nil), "0c")
eq("money: drops fractions", ns.Money(3000.9), "30s")

eq("parse: bare number is silver", ns.ParseMoney("50"), 5000)
eq("parse: 30s", ns.ParseMoney("30s"), 3000)
eq("parse: 1g 50s", ns.ParseMoney("1g 50s"), 15000)
eq("parse: 1g50s", ns.ParseMoney("1g50s"), 15000)
eq("parse: upper case", ns.ParseMoney("2G"), 20000)
eq("parse: copper", ns.ParseMoney("75c"), 75)
eq("parse: garbage", ns.ParseMoney("lots"), nil)
eq("parse: empty", ns.ParseMoney(""), nil)
eq("parse: nil", ns.ParseMoney(nil), nil)

eq("full: strips realm", ns.Full("Ash Lock-CAMWOWUS2Realm8PvP"), "Ash Lock")
eq("full: plain name", ns.Full("Ash Lock"), "Ash Lock")
eq("full: empty", ns.Full(""), nil)
eq("short: nil", ns.Short(nil), "?")

eq("clock: 75s", ns.Clock(75), "1:15")
eq("clock: negative", ns.Clock(-5), "0:00")

eq("ago: minutes", ns.Ago(1000, 1000 + 600), "just now")
eq("ago: hours", ns.Ago(0, 3 * 3600 + 5), "3h ago")
eq("ago: yesterday", ns.Ago(0, 86400 + 10), "yesterday")
eq("ago: days", ns.Ago(0, 4 * 86400), "4 days ago")

eq("coins: silver", ns.Coins(3000), "30|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
eq("coins: gold and silver", ns.Coins(13500),
  "1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 35|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
eq("coins: zero", ns.Coins(0), "0|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
