"""One warlock, one customer, a plain party (no raid): the setup of the
first real-game test. Parties don't report zones the way raids do."""
from harness import World


def main(check):
    w = World()
    ash = w.add("Ash Lock", leader=True)
    w.tick(2)
    ash.ns.Session.Start()
    w.tick(1)

    ash.whisper("inv", "Broken Fang")
    w.join("Broken Fang", cls="WARRIOR", zone="Stranglethorn Vale")
    w.tick(3)
    check("party: still a party, not a raid", not w.raid)
    r = ash.ns.Roster.members["Broken Fang"]
    check("party: the customer's location is known", r is not None and r.zone == "Stranglethorn Vale", r and r.zone)
    check("banner: says where they are", ash.banner() == "Your turn: summon Broken Fang (Stranglethorn Vale).",
          ash.banner())

    ash.cast_summon()
    w.tick(1)
    check("summon: being summoned", ash.queue().get("Broken Fang") == "SUMMONING")
    w.move("Broken Fang", "Undercity")
    w.tick(2)
    check("arrival: detected in a party", ash.queue().get("Broken Fang") == "ARRIVED", ash.queue())
    check("arrival: told to trade", ash.action() == "Trade Broken Fang", ash.action())

    ash.receive_trade("Broken Fang", 5000)
    w.tick(1)
    check("paid", ash.queue().get("Broken Fang") == "PAID")
    ash.click()
    check("kick: thanked", any(m["target"] == "Broken Fang" and m["text"] == "Thanks" for m in ash.sent("WHISPER")))
    return w
