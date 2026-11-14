"""Three warlocks, each running their own copy of the addon, work a circle
together: picking summoners, intake, rotation, casting, payment."""
from harness import World


def main(check):
    w = World()
    ash = w.add("Ash Lock", leader=True)
    bram = w.add("Bram Lock")
    cole = w.add("Cole Lock")
    w.tick(3)
    everyone = (ash, bram, cole)

    # --- Setup --------------------------------------------------------------
    check("setup: everyone sees each other's addon",
          all(p.ns.Roster.HasAddon(o.name) for p in everyone for o in everyone))
    check("setup: the leader holds the state", all(p.ns.Sync.AuthorityName() == "Ash Lock" for p in everyone))

    ash.ns.Session.SetSummoner("Bram Lock", True)
    ash.ns.Session.SetSummoner("Cole Lock", True)
    w.tick(3)
    want = ["Ash Lock", "Bram Lock", "Cole Lock"]
    for p in everyone:
        check(f"pick: {p.name} sees all three summoners", p.summoners() == want, p.summoners())
    check("pick: still a party while closed", not w.raid)

    ash.ns.Session.Start()
    w.tick(3)
    check("open: everyone's session is on", all(p.ns.Session.IsActive() for p in everyone))
    check("open: converted to raid", w.raid)
    check("open: leader is asked to give assist", (ash.action() or "").startswith("Give "), ash.banner())

    # --- No assist yet: the leader invites on Cole's behalf --------------------
    cole.whisper("inv", "Bob Smith")
    w.tick(3)
    check("no assist: Cole couldn't invite", not cole.sent("INVITE"))
    check("no assist: the leader invited instead",
          [m["target"] for m in ash.sent("INVITE")] == ["Bob Smith"], ash.sent("INVITE"))
    check("no assist: Bob got Cole's reply",
          any(m["target"] == "Bob Smith" and "#1 in queue" in m["text"] for m in cole.sent("WHISPER")))
    for p in everyone:
        check(f"intake: {p.name} sees Bob invited", p.queue() == {"Bob Smith": "INVITED"}, p.queue())

    ash.click()  # Give Bram assist
    w.tick(1)
    ash.click()  # Give Cole assist
    w.tick(2)
    check("assist: both summoners promoted", w.member("Bram Lock")["assist"] and w.member("Cole Lock")["assist"])

    # --- Intake through a summoner with assist -----------------------------
    bram.whisper("summon", "Cara Jones")
    w.tick(1)
    check("intake: Bram invites himself",
          [m["target"] for m in bram.sent("INVITE")] == ["Cara Jones"], bram.sent("INVITE"))
    check("intake: Cara is #2",
          any(m["target"] == "Cara Jones" and "#2 in queue" in m["text"] for m in bram.sent("WHISPER")))

    w.join("Bob Smith", cls="MAGE")
    w.join("Cara Jones", cls="PRIEST")
    w.tick(3)
    for p in everyone:
        check(f"join: {p.name} sees both waiting",
              p.queue() == {"Bob Smith": "GROUP", "Cara Jones": "GROUP"}, p.queue())

    # --- Rotation -------------------------------------------------------------
    ups = {p.name: p.ns.Rotation.NextUp() for p in everyone}
    check("rotation: everyone agrees who's next", len(set(ups.values())) == 1, ups)
    first = w.players[ups["Ash Lock"]]
    check("rotation: next up is told to summon", (first.action() or "").startswith("Summon "), first.banner())
    others = [p for p in everyone if p is not first]
    check("rotation: the others are told to wait",
          all("up next" in p.banner() for p in others), [p.banner() for p in others])

    target = first.cast_summon()
    w.tick(2)
    check("cast: summoned the oldest customer", target == "Bob Smith", target)
    for p in everyone:
        check(f"cast: {p.name} sees Bob being summoned", p.queue().get("Bob Smith") == "SUMMONING", p.queue())
    check("cast: the other summoners get a portal alert",
          all(any(c.startswith("[RW]") for c in p.chat()) for p in others))
    check("cast: the caster gets no alert", not any(c.startswith("[RW]") for c in first.chat()))
    nxt = {p.name: p.ns.Rotation.NextUp() for p in everyone}
    check("cast: the turn moved on", len(set(nxt.values())) == 1 and nxt["Ash Lock"] != first.name, nxt)

    # --- Arrival and payment --------------------------------------------------
    w.move("Bob Smith", "Undercity")
    w.tick(3)
    for p in everyone:
        check(f"arrive: {p.name} sees Bob arrived", p.queue().get("Bob Smith") == "ARRIVED", p.queue())
    check("arrive: the caster is told to trade", (first.action() or "") == "Trade Bob Smith", first.action())

    first.receive_trade("Bob Smith", 3000)
    w.tick(3)
    for p in everyone:
        check(f"paid: {p.name} sees Bob paid", p.queue().get("Bob Smith") == "PAID", p.queue())
        L = p.ns.S.ledger[first.name]
        check(f"paid: {p.name} credits {first.name}", L is not None and L.copper == 3000)
    check("paid: the caster is told to kick", (first.action() or "") == "Kick Bob Smith", first.action())
    check("paid: lifetime counted once, by the caster",
          first.ns.db.lifetime.copper == 3000 and all(p.ns.db.lifetime.copper == 0 for p in others))

    first.click()  # Kick Bob
    w.leave("Bob Smith")
    w.tick(3)
    check("kick: thanked Bob", any(m["target"] == "Bob Smith" and m["text"] == "Thanks" for m in first.sent("WHISPER")))
    for p in everyone:
        check(f"kick: {p.name} sees only Cara left", p.queue() == {"Cara Jones": "GROUP"}, p.queue())

    # --- Repeat whispers --------------------------------------------------------
    n = len(bram.sent("INVITE"))
    bram.whisper("inv", "Cara Jones")
    w.tick(1)
    check("repeat: someone already in the group isn't re-invited", len(bram.sent("INVITE")) == n)
    for p in everyone:
        check(f"repeat: {p.name} still has one Cara", p.queue() == {"Cara Jones": "GROUP"}, p.queue())

    return w
