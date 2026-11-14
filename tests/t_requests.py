"""Summon requests read from trade chat, across a three-warlock circle."""
from harness import World

LINE = "WTB UC summon 20s"


def main(check):
    w = World()
    ash = w.add("Ash Lock", leader=True)
    bram = w.add("Bram Lock")
    cole = w.add("Cole Lock")
    dana = w.add("Dana Mage", cls="MAGE")  # a customer who runs the addon
    w.tick(2)
    circle = (ash, bram, cole)

    def say(text, sender, index=2, to=None):
        for p in (to or circle + (dana,)):
            p.channel(text, sender, index)
        w.sync()

    # --- Closed: nothing is read ------------------------------------------------
    say(LINE, "Gorak Stone")
    check("closed: no requests", all(p.leads() == {} for p in circle))

    ash.ns.Session.SetSummoner("Bram Lock", True)
    ash.ns.Session.SetSummoner("Cole Lock", True)
    ash.ns.Session.Start()
    w.tick(2)

    # --- A request appears for every summoner ------------------------------
    say(LINE, "Gorak Stone")
    for p in circle:
        lead = p.leads().get("Gorak Stone")
        check(f"open: {p.name} sees Gorak's request", lead is not None)
        check(f"open: {p.name} sees the 20s offer", lead is not None and lead.offer == 2000)
    check("open: the customer's addon shows nothing", dana.leads() == {})
    check("open: the view doesn't switch by itself", all(p.ns.UI.view == "queue" for p in circle))
    tab = ash.g.SummonCircleFrame.reqTab.GetText(ash.g.SummonCircleFrame.reqTab)
    check("open: the Requests label lights up", "REQUESTS (1)" in tab and "ffd100" in tab, tab)
    check("open: the banner is untouched", ash.banner() == ash.ns.Advisor.NextAction().text and "request" not in ash.banner().lower())

    say("WTB UC summon 20s pls??", "Gorak Stone")
    check("repeat: still one request", len(ash.leads()) == 1)
    check("repeat: refreshed with the new text", ash.leads()["Gorak Stone"].text == "WTB UC summon 20s pls??")

    # --- What isn't a request -------------------------------------------------
    say(LINE, "Lia Moon", index=1)
    check("general chat isn't read (Trade is ticked)", "Lia Moon" not in ash.leads())
    say("WTS summons to UC 30s", "Rival Lock")
    say("WTB summon to Org", "Mog Tusk")
    check("selling and other cities are ignored", set(ash.leads()) == {"Gorak Stone"}, list(ash.leads()))
    w.join("Hana Reed", cls="ROGUE")
    w.tick(1)
    say(LINE, "Hana Reed")
    check("someone already in the group is ignored", "Hana Reed" not in ash.leads())
    say(LINE, "Ash Lock", to=(ash,))
    check("my own lines are ignored", "Ash Lock" not in ash.leads())
    ash.ns.Blacklist.Set("Gus Grim", "test")
    w.tick(1)
    say(LINE, "Gus Grim")
    check("blacklisted players are ignored", all("Gus Grim" not in p.leads() for p in circle))

    # --- Viewing the list -------------------------------------------------------
    ash.ns.UI.ShowView("requests")
    f = ash.g.SummonCircleFrame
    check("view: label no longer highlighted", "ffd100" not in f.reqTab.GetText(f.reqTab))
    ash.ns.UI.ShowView("queue")
    check("view: still not highlighted after looking", "ffd100" not in f.reqTab.GetText(f.reqTab))
    w.advance(2)
    say(LINE, "Ivy Lane")
    check("view: a newer request lights it up again", "ffd100" in f.reqTab.GetText(f.reqTab))

    # --- Whisper: one whisper for the whole circle ------------------------------
    bram.ns.Leads.Whisper("Gorak Stone")
    w.tick(2)
    sent = [m for m in bram.sent("WHISPER") if m["target"] == "Gorak Stone"]
    check("whisper: sent once", len(sent) == 1)
    check("whisper: the message", sent and sent[0]["text"] == "Selling UC summons - 30s. Whisper 'inv' if you want a summon.",
          sent and sent[0]["text"])
    check("whisper: gone from Bram's list", "Gorak Stone" not in bram.ns.Leads.list)
    for p in (ash, cole):
        l = p.ns.Leads.list["Gorak Stone"] if "Gorak Stone" in p.ns.Leads.list else None
        check(f"whisper: {p.name} sees Bram took it", l is not None and l.claimedBy == "Bram Lock")
        check(f"whisper: {p.name} can't whisper it too", "Gorak Stone" not in p.leads())
    n = len(ash.sent("WHISPER"))
    ash.ns.Leads.Whisper("Gorak Stone")
    check("whisper: a claimed request can't be whispered again", len(ash.sent("WHISPER")) == n)
    say(LINE, "Gorak Stone")
    check("quiet: Gorak's next request is hidden everywhere", all("Gorak Stone" not in p.leads() for p in circle))
    w.advance(31)
    w.tick(1)
    check("whisper: the 'Bram whispered' row clears", all("Gorak Stone" not in p.ns.Leads.list for p in circle))

    # --- Dismiss -------------------------------------------------------------------
    cole.ns.Leads.Dismiss("Ivy Lane")
    w.tick(2)
    check("dismiss: gone for everyone", all("Ivy Lane" not in p.ns.Leads.list for p in circle))
    check("dismiss: nobody whispered", not any(m["target"] == "Ivy Lane" for p in circle for m in p.sent("WHISPER")))
    say(LINE, "Ivy Lane")
    check("dismiss: quiet for 10 minutes", all("Ivy Lane" not in p.leads() for p in circle))
    w.advance(600)
    w.tick(1)
    say(LINE, "Ivy Lane")
    check("quiet ends after 10 minutes", all("Ivy Lane" in p.leads() for p in circle))

    # --- A customer can't silence requests -------------------------------------------
    dana.ns.Transport.Send(dana.L.eval('{ t = "LEAD_CLAIMED", from = "Ivy Lane", by = "Dana Mage", quietUntil = 9e9, how = "dismiss" }'))
    w.tick(2)
    check("privacy: a customer's claim is ignored", all("Ivy Lane" in p.leads() for p in circle))

    # --- Joining the queue clears the request ---------------------------------------
    bram.whisper("inv", "Ivy Lane")
    w.tick(2)
    check("queued: the request goes away", all("Ivy Lane" not in p.ns.Leads.list for p in circle))

    # --- Expiry ---------------------------------------------------------------------
    say(LINE, "Jon Pike")
    w.advance(179)
    w.tick(1)
    check("expiry: still there before 3 minutes", "Jon Pike" in ash.leads())
    w.advance(2)
    w.tick(1)
    check("expiry: gone after 3 minutes", all("Jon Pike" not in p.ns.Leads.list for p in circle))

    # --- Per-player settings -----------------------------------------------------------
    ash.ns.db.readRequests = False
    say(LINE, "Kai Fern")
    check("off: Ash doesn't read chat", "Kai Fern" not in ash.leads())
    check("off: the others still do", all("Kai Fern" in p.leads() for p in (bram, cole)))
    ash.ns.db.readRequests = True
    w.move("Cole Lock", "Durotar")
    say(LINE, "Lux Hale")
    check("outside a capital: nothing", "Lux Hale" not in cole.leads())
    w.move("Cole Lock", "Undercity")
    ash.L.eval("(function() local n = 0; local real = PlaySound; PlaySound = function() n = n + 1 end; _G.SOUNDS = function() return n end end)()")
    ash.ns.db.requestSound = True
    say(LINE, "Mia Rook")
    say(LINE, "Mia Rook")
    check("sound: once per new request", ash.eval("SOUNDS()") == 1)

    # --- Closing the shop clears everything ----------------------------------------------
    check("before closing: requests are listed", len(list(bram.ns.Leads.list.keys())) > 0)
    ash.ns.Session.Stop()
    w.tick(2)
    check("closed: requests cleared", all(len(list(p.ns.Leads.list.keys())) == 0 for p in circle))
    return w
