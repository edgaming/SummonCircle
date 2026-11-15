"""The circle under stress: privacy from customers who run the addon,
blacklist sharing, timeouts, a customer skipping out, and the leader
leaving mid-session."""
from harness import World


def setup():
    w = World()
    ash = w.add("Ash Lock", leader=True)
    bram = w.add("Bram Lock")
    cole = w.add("Cole Lock")
    w.tick(2)
    ash.ns.Session.SetSummoner("Bram Lock", True)
    ash.ns.Session.SetSummoner("Cole Lock", True)
    ash.ns.Session.Start()
    w.tick(2)
    for _ in range(2):  # give both summoners assist
        ash.click()
        w.tick(1)
    return w, ash, bram, cole


def main(check):
    w, ash, bram, cole = setup()
    summoners = (ash, bram, cole)

    # --- A customer who also runs the addon learns nothing ----------------
    dana = w.add("Dana Mage", cls="MAGE")
    w.tick(3)
    bram.whisper("inv", "Finn Moss")
    w.tick(3)
    check("privacy: summoners see Finn queued", all("Finn Moss" in p.queue() for p in summoners))
    check("privacy: the customer's addon never gets the queue", dana.queue() == {}, dana.queue())
    check("privacy: the customer sees no summoners", dana.summoners() == [], dana.summoners())
    check("privacy: the customer isn't treated as a summoner",
          not any(p.ns.Session.IsSummoner("Dana Mage") for p in summoners))

    # Customers can't push blacklist lists or ops through the group.
    # (Network entries are accepted from anyone by design: see t_netblacklist.py.)
    dana.ns.Transport.Send(dana.L.eval('{ t = "BL", list = { ["Cole Lock"] = { by = "Dana Mage", at = 9e9, reason = "x" } } }'))
    dana.ns.Transport.Send(dana.L.eval('{ t = "OP", m = { op = "REMOVE", name = "Finn Moss", at = 1 } }'))
    w.tick(3)
    check("privacy: a customer's blacklist list is ignored in the group",
          not any(p.ns.Blacklist.Get("Cole Lock") for p in summoners))
    check("privacy: a customer's op is ignored", all("Finn Moss" in p.queue() for p in summoners))

    # --- Blacklist spreads between summoners ------------------------------
    bram.ns.Blacklist.Set("Gus Grim", "didn't pay Bram Lock")
    w.tick(2)
    check("blacklist: every summoner has the entry", all(p.ns.Blacklist.Get("Gus Grim") for p in summoners))
    ash.whisper("inv", "Gus Grim")
    w.tick(1)
    check("blacklist: not invited", not any(m["target"] == "Gus Grim" for m in ash.sent("INVITE")))
    check("blacklist: not queued", all("Gus Grim" not in p.queue() for p in summoners))
    check("blacklist: the summoner may invite anyway", ash.action() == "Invite anyway", ash.banner())
    w.advance(5)  # merges are newest-wins by server second
    cole.ns.Blacklist.Set("Gus Grim", None, True)
    w.tick(2)
    check("blacklist: removal spreads too", not any(p.ns.Blacklist.Get("Gus Grim") for p in summoners))

    # --- Invites that are never accepted expire ---------------------------
    w.advance(86)
    w.tick(2)
    check("invite timeout: Finn dropped everywhere", all("Finn Moss" not in p.queue() for p in summoners),
          [p.queue() for p in summoners])

    # --- A summon nobody accepts resets -----------------------------------
    cole.whisper("+", "Hana Reed")
    w.join("Hana Reed", cls="ROGUE")
    w.tick(3)
    caster = w.players[ash.ns.Rotation.NextUp()]
    caster.cast_summon()
    w.tick(1)
    w.advance(121)
    w.tick(2)
    check("summon timeout: Hana back in line", all(p.queue().get("Hana Reed") == "GROUP" for p in summoners),
          [p.queue() for p in summoners])
    check("summon timeout: counted as failed", ash.ns.S.ledger[caster.name].failed == 1)

    # --- Customer arrives and leaves without paying ------------------------
    caster = w.players[ash.ns.Rotation.NextUp()]
    caster.cast_summon()
    w.move("Hana Reed", "Undercity")
    w.tick(2)
    w.leave("Hana Reed")
    w.tick(3)
    check("skip out: Hana gone from every queue", all("Hana Reed" not in p.queue() for p in summoners))
    check("skip out: the caster is offered the blacklist", caster.action() == "Blacklist Hana Reed", caster.banner())
    others = [p for p in summoners if p is not caster]
    check("skip out: nobody else is asked", all((p.action() or "") != "Blacklist Hana Reed" for p in others))
    caster.click()
    w.tick(2)
    check("skip out: blacklisted for everyone",
          all((p.ns.Blacklist.Get("Hana Reed") or {}) and "left without paying" in p.ns.Blacklist.Get("Hana Reed").reason
              for p in summoners))

    # --- The leader leaves mid-session ------------------------------------
    cole.whisper("inv", "Ivy Lane")
    w.join("Ivy Lane", cls="DRUID")
    w.tick(3)
    epoch = bram.ns.S.epoch
    w.leave("Ash Lock")
    w.tick(4)
    check("handoff: Bram leads now", w.member("Bram Lock")["leader"])
    check("handoff: Bram holds the state", all(p.ns.Sync.AuthorityName() == "Bram Lock" for p in (bram, cole)))
    check("handoff: a new epoch", bram.ns.S.epoch > epoch, (epoch, bram.ns.S.epoch))
    check("handoff: the queue survived", all(p.queue().get("Ivy Lane") == "GROUP" for p in (bram, cole)),
          [p.queue() for p in (bram, cole)])
    check("handoff: Bram is first summoner", bram.summoners()[:1] == ["Bram Lock"], bram.summoners())
    check("handoff: Ash dropped from the summoners", "Ash Lock" not in cole.summoners(), cole.summoners())
    check("handoff: still open", bram.ns.Session.IsActive() and cole.ns.Session.IsActive())
    check("left: Ash's session is off", not ash.ns.Session.IsActive())
    check("left: Ash's queue is cleared", ash.queue() == {}, ash.queue())

    # --- A new summoner catches up ------------------------------------------
    eve = w.add("Eve Lock")
    w.tick(3)
    bram.ns.Session.SetSummoner("Eve Lock", True)
    w.tick(4)
    check("late joiner: Eve gets the queue", eve.queue().get("Ivy Lane") == "GROUP", eve.queue())
    check("late joiner: Eve gets the summoners",
          eve.summoners() == ["Bram Lock", "Cole Lock", "Eve Lock"], eve.summoners())
    check("late joiner: Eve gets the blacklist", eve.ns.Blacklist.Get("Hana Reed") is not None)
    check("late joiner: Eve is open", eve.ns.Session.IsActive())

    return w
