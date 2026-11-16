"""Find a Circle (design doc 03): a circle recruits over the network, a
warlock outside the group asks to join, the leader invites, the circle fills."""
from harness import World, lua_list


def main(check):
    w = World()
    ash = w.add("Ash Lock", leader=True)
    bram = w.add("Bram Lock")
    vex = w.add("Vex Shadow", join=False, zone="Orgrimmar")
    wyn = w.add("Wyn Dusk", join=False, zone="Durotar")
    dana = w.add("Dana Mage", join=False, cls="MAGE")
    w.advance(10)
    w.tick(3)
    ash.ns.Session.SetSummoner("Bram Lock", True)
    w.tick(2)
    L = lambda p: p.ns.Listings

    def rows(p):
        return lua_list(p.ns.Listings.Recruiting())

    def apps(p):
        return lua_list(p.ns.Recruit.Applicants())

    # --- Before anyone recruits ---------------------------------------------------
    vex.ns.UI.ShowPage("find")
    note = vex.g.SummonCircleFrame
    check("tabs: warlocks get them", vex.ns.UI.HasTabs())
    check("tabs: other classes don't", not dana.ns.UI.HasTabs())
    check("page: My Circle is hidden on the Find a Circle page",
          not vex.eval("SummonCircleFrame.content:IsShown()"))
    check("page: shows the waiting note in the first minute",
          "Waiting up to a minute" in vex.eval("SummonCircle.UI.pages[1].frame.note:GetText()"))
    check("closed circles aren't published", not L(ash).IsLive())

    # --- The leader starts recruiting ---------------------------------------------
    ash.ns.Recruit.SetRecruiting(True)
    w.tick(3)
    check("recruit: the leader publishes", L(ash).IsLive())
    check("recruit: only the leader publishes", not L(bram).IsLive())
    for p in (vex, wyn):
        r = rows(p)
        check(f"listing: {p.name} sees the circle", len(r) == 1 and r[0].leader == "Ash Lock")
    l = rows(vex)[0]
    check("listing: city and size", l.spot == "Undercity" and l.short == "UC" and l.summoners == 2 and l.wanted == 3)
    check("listing: each summoner's shards", len(list(l.shards.values())) == 2)
    check("listing: not open for customers yet", not l.open)
    check("listing: the circle doesn't see itself", rows(ash) == [] and rows(bram) == [])
    vex.ns.UI.Refresh()
    pg = "SummonCircle.UI.pages[1].frame"
    row = pg + ".rows[1]"
    check("row: who", vex.eval(row + ".name:GetText()") == "Ash Lock")
    check("row: where", vex.eval(row + ".spot:GetText()") == "Undercity")
    det = vex.eval(row + ".detail:GetText()")
    check("row: price as coins, and the queue", "SilverIcon" in det and "waiting" in det, det)
    check("row: two summoner slots filled, one open",
          vex.eval(row + ".slots[2]:GetAlpha()") == 1 and vex.eval(row + ".slots[3]:GetAlpha()") < 1)
    check("row: summons left", "summons left" in vex.eval(row + ".left:GetText()"))
    check("ask: nothing picked yet, so the button is off", not vex.eval(pg + ".ask:IsEnabled()"))
    check("ask: a hint says what to do", "Pick a circle" in vex.eval(pg + ".hint:GetText()"))
    vex.eval(row + ":GetScript('OnClick')()")
    check("pick: the row is highlighted", vex.eval(row + ".sel:IsShown()"))
    check("pick: Ask to join is on", vex.eval(pg + ".ask:IsEnabled()") and vex.eval(pg + ".ask:GetText()") == "Ask to join")
    check("leader: the box shows 2/3", "(2/3)" in ash.eval("SummonCircleFrame.recruit.hint:GetText()"))
    ash.ns.UI.ShowPage("find")
    own = "SummonCircle.UI.pages[1].frame.rows[1]"
    check("own circle: shown first in Find a Circle", ash.eval(own + ":IsShown()")
          and "Ash Lock" in ash.eval(own + ".name:GetText()") and "(your circle)" in ash.eval(own + ".name:GetText()"))
    check("own circle: greyed out", ash.eval(own + ":GetAlpha()") < 1)
    ash.eval(own + ":GetScript('OnClick')()")
    check("own circle: can't be picked", ash.eval("SummonCircle.UI.pages[1].selected") is None
          and not ash.eval("SummonCircle.UI.pages[1].frame.ask:IsEnabled()"))
    bram.ns.UI.ShowPage("find")
    check("own circle: the other summoners see it too",
          "(your circle)" in bram.eval("SummonCircle.UI.pages[1].frame.rows[1].name:GetText()"))
    ash.ns.UI.ShowPage("circle"); bram.ns.UI.ShowPage("circle")
    check("leader only: Bram has no box", not bram.eval("SummonCircleFrame.recruit:IsShown()"))

    # --- Asking to join -------------------------------------------------------------
    vex.eval(pg + ".ask:GetScript('OnClick')()")
    w.tick(2)
    sent = [m for m in vex.sent("WHISPER") if m["target"] == "Ash Lock"]
    check("ask: friendly whisper to the leader",
          sent and sent[0]["text"] == "Hi, I'm looking to join your summoning circle in Undercity. I'm in Orgrimmar with "
          + str(vex.ns.GetShards()) + " soul shards.", sent and sent[0]["text"])
    a = apps(ash)
    check("ask: the leader sees the applicant", len(a) == 1 and a[0].name == "Vex Shadow" and a[0].zone == "Orgrimmar")
    check("ask: with their shards", a and a[0].shards == vex.ns.GetShards())
    check("ask: the other summoner sees it too", len(apps(bram)) == 1)
    ash.ns.UI.Refresh(); bram.ns.UI.Refresh()
    check("ask: WANTS TO JOIN shows", ash.eval("SummonCircleFrame.appHeader:IsShown()"))
    rowtext = ash.eval("SummonCircleFrame.appRows[1].text:GetText()")
    check("ask: the row shows name, zone and shards", "Vex Shadow" in rowtext and "Orgrimmar" in rowtext and "shard" in rowtext, rowtext)
    check("ask: the leader gets Invite and ×", ash.eval("SummonCircleFrame.appRows[1].invite:IsShown()")
          and ash.eval("SummonCircleFrame.appRows[1].close:IsShown()"))
    check("ask: other summoners see the row without buttons", bram.eval("SummonCircleFrame.appRows[1]:IsShown()")
          and not bram.eval("SummonCircleFrame.appRows[1].invite:IsShown()"))
    check("ask: Vex's row says Asked", vex.ns.Recruit.RowState("Ash Lock") == "asked")
    vex.ns.UI.Refresh()
    check("ask: the button says Asked and is off", vex.eval(pg + ".ask:GetText()") == "Asked"
          and not vex.eval(pg + ".ask:IsEnabled()"))
    vex.ns.Recruit.Ask("Ash Lock")
    check("ask: can't ask again right away", len([m for m in vex.sent("WHISPER") if m["target"] == "Ash Lock"]) == 1)
    w.advance(2)
    wyn.ns.Recruit.Ask("Ash Lock")
    w.tick(2)
    check("ask: a second applicant", len(apps(ash)) == 2)
    check("ask: newest first", apps(ash)[0].name == "Wyn Dusk")

    # --- Invite, join, the circle fills ---------------------------------------------
    ash.ns.Recruit.Invite("Vex Shadow")
    w.tick(1)
    check("invite: sent", any(m["target"] == "Vex Shadow" for m in ash.sent("INVITE")))
    check("invite: row says Invited", ash.ns.S.applicants["Vex Shadow"].invited)
    w.join("Vex Shadow")
    w.tick(4)
    check("join: Vex is a summoner automatically", "Vex Shadow" in ash.summoners(), ash.summoners())
    check("join: and knows it", vex.ns.Session.IsSummoner("Vex Shadow"))
    check("full: recruiting turned off", not ash.ns.Recruit.IsRecruiting())
    check("full: listing withdrawn", not L(ash).IsLive() and rows(wyn) == [])
    check("full: Wyn was told", wyn.ns.Recruit.RowState("Ash Lock") == "closed")
    check("full: applicants cleared", apps(ash) == [])
    vex.ns.UI.ShowPage("find")
    check("in a circle: Find a Circle explains instead of listing",
          "summoning in a circle" in vex.eval("SummonCircle.UI.pages[1].frame.note:GetText()"))

    # --- Open circles still publish (for Find a Summon), but aren't recruiting ------------
    ash.ns.Session.Start()
    w.tick(3)
    check("open: published", L(ash).IsLive())
    check("open: not in Find a Circle", rows(wyn) == [])
    check("open: Wyn heard it", "Ash Lock" in wyn.ns.Listings.all and wyn.ns.Listings.all["Ash Lock"].open)

    # --- Heartbeat and expiry -----------------------------------------------------------
    cole = w.add("Cole Lock", join=False)
    w.advance(10)
    w.tick(3)
    cole.ns.Recruit.SetRecruiting(True)
    w.tick(2)
    check("solo leader: a circle of one can recruit", any(l.leader == "Cole Lock" for l in rows(wyn)))
    seen = wyn.ns.Listings.all["Cole Lock"].seen
    w.advance(61)
    w.tick(2)
    check("heartbeat: refreshed after a minute", wyn.ns.Listings.all["Cole Lock"].seen > seen)
    cole.g.JOINED = cole.L.table()  # Cole drops off the network without saying goodbye
    w.advance(181)
    w.tick(2)
    check("expiry: gone after 3 minutes of silence", "Cole Lock" not in wyn.ns.Listings.all)

    # --- Unticking withdraws it -----------------------------------------------------------
    ash.ns.Session.Stop()
    ash.ns.Recruit.SetRecruiting(True)
    w.tick(2)
    check("still full: recruiting won't stay on with 3 summoners", not ash.ns.Recruit.IsRecruiting())
    w.leave("Vex Shadow")
    w.tick(3)
    ash.ns.Recruit.SetRecruiting(True)
    w.tick(3)
    check("re-tick: listed again", any(l.leader == "Ash Lock" for l in rows(dana)))
    ash.ns.Recruit.SetRecruiting(False)
    w.tick(2)
    check("untick: withdrawn everywhere", "Ash Lock" not in dana.ns.Listings.all)

    return w
