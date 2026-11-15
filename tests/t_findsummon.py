"""Find a Summon (design doc 04): a customer outside the group finds open
circles and gets in line with one click."""
from harness import World, lua_list


def main(check):
    w = World()
    ash = w.add("Ash Lock", leader=True)
    bram = w.add("Bram Lock")
    dana = w.add("Dana Mage", join=False, cls="MAGE", zone="Orgrimmar")
    cole = w.add("Cole Lock", join=False)               # recruiting only, not open
    eve = w.add("Eve Lock", join=False, zone="Orgrimmar")  # open in Dana's own city
    w.advance(10)
    w.tick(3)
    pg = "SummonCircle.UI.pages[2].frame"
    opened = lambda p: lua_list(p.ns.Listings.Open())

    # --- A customer's window is Find a Summon ------------------------------------
    dana.ns.UI.Refresh()
    check("customer: no tab bar", not dana.ns.UI.HasTabs())
    check("customer: the window opens on Find a Summon", dana.ns.UI.page == "summon")
    check("customer: waiting note in the first minute",
          "Waiting up to a minute" in dana.eval(pg + ".note:GetText()"))
    check("warlocks: Find a Summon is their third tab", ash.eval("#SummonCircleFrame.tabs") == 3)

    # --- Circles open for business show up -------------------------------------------
    ash.ns.Session.SetSummoner("Bram Lock", True)
    ash.ns.Session.Start()
    ash.click()  # give Bram assist
    w.tick(2)
    cole.ns.Recruit.SetRecruiting(True)
    eve.ns.Session.Start()
    w.tick(3)
    o = opened(dana)
    check("open: Ash's circle is listed", len(o) == 1 and o[0].leader == "Ash Lock", [l.leader for l in o])
    check("closed: a circle that's only recruiting isn't", all(l.leader != "Cole Lock" for l in o))
    check("here: a circle in your own city isn't", all(l.leader != "Eve Lock" for l in o))
    dana.ns.UI.Refresh()
    row = pg + ".rows[1]"
    check("row: where", dana.eval(row + ".spot:GetText()") == "Undercity (UC)")
    check("row: whose and how many", dana.eval(row + ".circle:GetText()") == "Ash Lock's circle  ·  2 summoners",
          dana.eval(row + ".circle:GetText()"))
    check("row: price in coins", "SilverIcon" in dana.eval(row + ".price:GetText()"))
    check("row: wait", "no wait" in dana.eval(row + ".wait:GetText()"))
    check("count", dana.eval(pg + ".count:GetText()") == "1 open circle")

    # --- Get summoned ----------------------------------------------------------------
    check("button: off until a circle is picked", not dana.eval(pg + ".get:IsEnabled()"))
    check("button: hint", "Pick a circle" in dana.eval(pg + ".hint:GetText()"))
    dana.eval(row + ":GetScript('OnClick')()")
    check("pick: highlighted, button on", dana.eval(row + ".sel:IsShown()") and dana.eval(pg + ".get:IsEnabled()"))
    dana.eval(pg + ".get:GetScript('OnClick')()")
    sent = [m for m in dana.sent("WHISPER")]
    check("get: whispers inv to the leader", sent == [dict(kind="WHISPER", text="inv", target="Ash Lock")], sent)
    check("get: button says Requested and is off",
          dana.eval(pg + ".get:GetText()") == "Requested" and not dana.eval(pg + ".get:IsEnabled()"))
    check("get: hint says to accept the invite", "Accept the invite" in dana.eval(pg + ".hint:GetText()"))
    dana.eval(pg + ".get:GetScript('OnClick')()")
    check("get: can't be clicked twice", len(dana.sent("WHISPER")) == 1)

    # The circle's normal flow takes over.
    ash.whisper("inv", "Dana Mage")
    check("circle: invited her", any(m["target"] == "Dana Mage" for m in ash.sent("INVITE")))
    w.join("Dana Mage", cls="MAGE", zone="Orgrimmar")
    w.tick(3)
    dana.ns.UI.Refresh()
    check("queued: the page says where she stands",
          "You're in Ash Lock's queue in Undercity" in dana.eval(pg + ".note:GetText()"),
          dana.eval(pg + ".note:GetText()"))
    check("queued: still no tabs for a customer", not dana.ns.UI.HasTabs())
    w.leave("Dana Mage")
    w.tick(3)

    # --- Leader AFK: whisper another summoner who can invite ---------------------------
    ash.g.AFK = True
    w.advance(11)
    w.tick(3)
    o = opened(dana)
    check("afk: the listing's first contact is Bram", o and lua_list(o[0].contacts)[0] == "Bram Lock",
          o and lua_list(o[0].contacts))
    ash.g.AFK = False

    # --- The circle's own keyword ---------------------------------------------------------
    ash.slash("keywords summon,+")
    w.advance(11)
    w.tick(3)
    dana.ns.Summon.requested = dana.L.table()
    dana.ns.Summon.Request("Ash Lock")
    check("keyword: uses the circle's word", dana.sent("WHISPER")[-1]["text"] == "summon")

    return w
