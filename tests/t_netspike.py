"""The /sc net spike between players who aren't grouped."""
from harness import World


def main(check):
    w = World()
    ash = w.add("Ash Lock", join=False)
    bram = w.add("Bram Lock", join=False)
    ally = w.add("Aly Bright", join=False, faction="Alliance", cls="PALADIN")
    cole = w.add("Cole Lock", join=False)  # runs the addon but never types /sc net
    w.tick(1)
    R = lambda p: p.ns.NetSpike.Results()

    # --- Nothing happens until someone asks --------------------------------------
    check("idle: nobody is in the test channel", all(p.ns.NetSpike.Index() is None for p in (ash, bram, ally, cole)))

    for p in (ash, bram, ally):
        p.slash("net")
    w.tick(2)
    for p in (ash, bram, ally):
        check(f"join: {p.name} joined", R(p).joined)
        check(f"join: {p.name} hid it from chat", R(p).hidden and p.g.HIDDEN_CHANNELS["SummonCircleTest"])
    check("join: someone who didn't type /sc net isn't in it", cole.ns.NetSpike.Index() is None)

    # --- Ping across the channel, answers by addon whisper ------------------------------
    ash.slash("net ping")
    w.tick(2)
    check("ping: Bram heard it", "Ash Lock" in R(bram).pings)
    check("ping: the Alliance player heard it (channel shared)", "Ash Lock" in R(ally).pings)
    check("ping: the other faction is called out",
          any("Other faction" in c for c in ally.chat()), ally.chat()[-3:])
    check("ping: Cole heard nothing", R(cole).pings is None or "Ash Lock" not in R(cole).pings)
    check("pong: Bram answered", "Bram Lock" in R(ash).pongs)
    check("pong: Alliance can't whisper back across factions", "Aly Bright" not in R(ash).pongs)
    check("pong: route recorded", R(ash).pongs["Bram Lock"].route == "CHANNEL")

    # --- The channel isn't shared ---------------------------------------------------
    w.channels_shared = False
    bram.slash("net ping")
    w.tick(2)
    check("separate channels: Alliance doesn't hear Horde", "Bram Lock" not in R(ally).pings)
    w.channels_shared = True

    # --- Direct whisper, no group -------------------------------------------------------
    bram.slash("net whisper Ash Lock")
    w.tick(2)
    check("whisper: Ash got Bram's direct ping", R(ash).pings["Bram Lock"] is not None)
    check("whisper: and answered", R(bram).pongs["Ash Lock"].route == "WHISPER")

    # --- Burst and long messages ----------------------------------------------------------
    ash.slash("net burst 20")
    w.tick(7)
    check("burst: all 20 accepted by the (fake) game", R(ash).burstSent.ok == 20)
    check("burst: Bram received all 20", R(bram).bursts["Ash Lock"].got == 20)
    check("burst: Bram was told the count", any("received 20 of 20" in c for c in bram.chat()))
    ash.slash("net big")
    w.tick(2)
    check("big: arrived intact in several parts", R(bram).big["Ash Lock"] > 1000)

    # --- The circle's own traffic is untouched --------------------------------------------
    check("isolation: no group messages from spike traffic", bram.ns.Roster.peers["Ash Lock"] is None)

    ash.slash("net report")
    check("report: printed", any("Answers to my pings" in c for c in ash.chat()))

    # --- Leaving, and a failed join ---------------------------------------------------------
    ash.slash("net leave")
    check("leave: out of the channel", ash.ns.NetSpike.Index() is None)
    cole.g.CHANNEL_JOIN_OK = False
    cole.slash("net")
    w.tick(2)
    check("failed join: explained", any("Couldn't join" in c for c in cole.chat()))
    return w
