"""Blacklist entries spread over the faction network (design doc 02)."""
from harness import World


def main(check):
    w = World()
    ash = w.add("Ash Lock", join=False)
    bram = w.add("Bram Lock", join=False)
    cole = w.add("Cole Lock", join=False)
    dana = w.add("Dana Mage", join=False, cls="MAGE")
    ally = w.add("Aly Bright", join=False, faction="Alliance", cls="PALADIN")
    horde = (ash, bram, cole, dana)

    # --- Joining ------------------------------------------------------------------
    ash.slash("net")
    check("/sc net before joining says so", "Network: on" not in ash.chat()[-1], ash.chat()[-1])
    w.advance(10)
    w.tick(3)
    for p in horde + (ally,):
        check(f"join: {p.name} is on the network", p.ns.Net.Available())
    check("join: Horde channel", ash.ns.Net.ChannelName() == "SummonCircleH")
    check("join: Alliance channel", ally.ns.Net.ChannelName() == "SummonCircleA")
    check("join: hidden from chat", ash.g.HIDDEN_CHANNELS["SummonCircleH"] is True)
    ash.slash("net")
    check("/sc net reports it's on", "Network: on" in ash.chat()[-1], ash.chat()[-1])

    # --- An entry reaches everyone on the faction, ungrouped --------------------------
    ash.ns.Blacklist.Set("Gus Grim", "didn't pay Ash Lock")
    w.tick(2)
    for p in (bram, cole, dana):
        e = p.ns.Blacklist.Get("Gus Grim")
        check(f"spread: {p.name} has the entry", e is not None)
        check(f"spread: {p.name} sees who added it", e is not None and e.by == "Ash Lock" and e.via == "net")
    check("spread: the other faction doesn't", ally.ns.Blacklist.Get("Gus Grim") is None)
    check("spread: my own entry stays mine", ash.ns.Blacklist.Get("Gus Grim").via is None)

    # It's acted on: a whisper from Gus to Bram isn't invited, and the reason shows the source.
    bram.ns.Session.Start()
    bram.whisper("inv", "Gus Grim")
    check("acted on: not invited", not bram.sent("INVITE"))
    check("acted on: the prompt names the source", "via the network" in bram.banner(), bram.banner())
    bram.ns.Session.Stop()

    # --- Removal spreads ------------------------------------------------------------------
    w.advance(5)
    cole.ns.Blacklist.Set("Gus Grim", None, True)
    w.tick(2)
    check("removal: gone everywhere", all(p.ns.Blacklist.Get("Gus Grim") is None for p in horde))

    # --- Older news loses ---------------------------------------------------------------------
    dana.ns.Transport.SendNet(dana.L.eval('{ t = "BL_ENTRY", name = "Gus Grim", at = 1, reason = "old" }'))
    w.tick(2)
    check("stale: an older entry doesn't undo the removal", ash.ns.Blacklist.Get("Gus Grim") is None)

    # --- Abuse limits -------------------------------------------------------------------------
    dana.ns.Transport.SendNet(dana.L.eval(
        '{ t = "BL_ENTRY", name = "Ivy Lane", at = GetServerTime() + 999999, reason = "forever" }'))
    w.tick(2)
    check("future-dated entries are refused", ash.ns.Blacklist.Get("Ivy Lane") is None)
    dana.ns.Transport.SendNet(dana.L.eval(
        '{ t = "BL_ENTRY", name = "Jon Pike", at = GetServerTime(), reason = "x", by = "Ash Lock" }'))
    w.tick(2)
    e = bram.ns.Blacklist.Get("Jon Pike")
    check("impersonation: the real sender is recorded", e is not None and e.by == "Dana Mage", e and e.by)
    for i in range(12):
        dana.ns.Blacklist.Set(f"Spam Name{i:02d}", "spam")
    w.tick(12)
    got = sum(1 for i in range(12) if bram.ns.Blacklist.Get(f"Spam Name{i:02d}") is not None)
    # Dana already used 2 of her 10 (the stale entry and the impersonation one).
    check("rate limit: at most 10 per sender per hour", got == 8, got)
    w.advance(3601)
    dana.ns.Blacklist.Set("Spam Late", "spam")
    w.tick(2)
    check("rate limit: resets after an hour", bram.ns.Blacklist.Get("Spam Late") is not None)

    # --- Mixed paths: the group copy and the network copy merge to the newest ----------------
    w.advance(10)
    bram.ns.Blacklist.Set("Kai Fern", "new")
    w.tick(2)
    old = ash.L.eval('{ ["Kai Fern"] = { by = "Cole Lock", at = 5, reason = "older" } }')
    ash.ns.Blacklist.Merge(old)
    check("mixed: the newer network entry wins", ash.ns.Blacklist.Get("Kai Fern").reason == "new")

    # --- Network unavailable: nothing breaks ------------------------------------------------
    eve = w.add("Eve Lock", join=False)
    eve.g.CHANNEL_JOIN_OK = False
    w.advance(10)
    w.tick(8)
    eve.slash("net")
    check("unavailable: explained", "couldn't join" in eve.chat()[-1], eve.chat()[-1])
    eve.ns.Blacklist.Set("Lux Hale", "x")
    w.tick(2)
    check("unavailable: nothing sent, nothing breaks", ash.ns.Blacklist.Get("Lux Hale") is None)
    return w
