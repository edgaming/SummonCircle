"""Test harness: fake WoW runtimes, alone or several players in one group.

    L = new_runtime("Ash Lock")     # one player, addon not loaded yet (Lua tests call Boot())

    w = World()                     # several players, each running their own copy
    ash = w.add("Ash Lock", leader=True)
    bram = w.add("Bram Lock")
    w.join("Bob Smith", cls="MAGE") # a customer without the addon
    w.tick(5)                       # run timers and deliver addon messages
    ash.ns.Session.Start()
"""
import os
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
REALM = "-CAMWOWUS2Realm8PvP"  # the game appends this to names; the addon must strip it


def toc_files():
    """The addon's files, in load order, exactly as the game reads them."""
    out = []
    for line in open(os.path.join(ADDON, "SummonCircle.toc")):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line.replace("\\", "/"))
    return out


def new_runtime(me="Ash Lock"):
    L = lua51.LuaRuntime()
    L.execute(open(os.path.join(HERE, "wowmock.lua")).read())
    g = L.globals()
    g.ME_NAME = me
    g.ADDON_DIR = ADDON
    files = L.table()
    for i, f in enumerate(toc_files(), 1):
        files[i] = f
    g.ADDON_FILES = files
    L.execute('''
ns = {}
function LoadAddon(dir)
  for _, f in ipairs(ADDON_FILES) do
    local fh = io.open(dir .. "/" .. f); local src = fh:read("*a"); fh:close()
    local chunk, err = loadstring(src, f)
    if not chunk then error(err) end
    local ok, e = pcall(chunk, "SummonCircle", ns)
    if not ok then table.insert(ERRORS, "load " .. f .. ": " .. tostring(e)) end
  end
end
''')
    return L


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Player:
    """One player running the addon in their own Lua runtime."""

    def __init__(self, world, name, cls, faction="Horde"):
        self.world, self.name, self.cls, self.faction = world, name, cls, faction
        self.L = new_runtime(name)
        self.g = self.L.globals()
        self.g.PLAYER_CLASS = cls
        self.g.PLAYER_FACTION = faction
        self.sent_cursor = 0
        self.msg_cursor = 0

    @property
    def ns(self):
        return self.g.ns

    def eval(self, expr):
        return self.L.eval(expr)

    def fire(self, event, *args):
        self.g.FireEvent(event, *args)

    def whisper(self, text, sender):
        """A whisper reaches this player, with the realm suffix the game adds."""
        self.fire("CHAT_MSG_WHISPER", text, sender + REALM)
        self.world.sync()

    def channel(self, text, sender, index=2):
        """A line in a chat channel (2 = Trade, 1 = General) reaches this player."""
        names = {1: "General - Undercity", 2: "Trade - City"}
        self.fire("CHAT_MSG_CHANNEL", text, sender + REALM, "", f"{index}. {names[index]}",
                  "", "", 0, index, names[index])

    def leads(self):
        """{ name: lead } of this player's open requests (not whispered by someone else)."""
        return {k: v for k, v in self.ns.Leads.list.items() if v.claimedBy is None}

    def slash(self, line):
        """Type a /sc command."""
        self.g.SlashCmdList.SUMMONCIRCLE(line)
        self.world.sync()

    def chat(self):
        return list(self.g.CHAT.values())

    def sent(self, kind=None):
        """Chat whispers / invites / channel posts this player sent."""
        out = [dict(kind=m.kind, text=m.text, target=m.target) for m in self.g.SENT.values()]
        return [m for m in out if kind is None or m["kind"] == kind]

    def errors(self):
        return list(self.g.ERRORS.values())

    def queue(self):
        """{ name: status } of this player's copy of the queue."""
        return {k: v.status for k, v in self.ns.S.queue.items()}

    def summoners(self):
        return lua_list(self.ns.S.summoners)

    def banner(self):
        return self.ns.Advisor.NextAction().text

    def action(self):
        a = self.ns.Advisor.NextAction()
        return a.label

    def click(self):
        """Press the big button (non-summon actions)."""
        a = self.ns.Advisor.NextAction()
        assert a.fn is not None, "nothing to click: " + str(a.text)
        a.fn()
        self.world.sync()

    def cast_summon(self):
        """Press the big button for a summon, as the game would run it."""
        target = self.eval("rawget(SummonCircleActionButton, 'target')")
        assert target, "button isn't a summon: " + str(self.banner())
        self.ns.Queue.pendingTarget = target
        self.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 698)
        self.world.sync()
        return target

    def receive_trade(self, partner, copper):
        """Someone trades this player gold."""
        self.g.TRADE_PARTNER = partner
        self.g.TRADE_MONEY = copper
        self.fire("TRADE_SHOW")
        self.fire("TRADE_MONEY_CHANGED")
        self.fire("UI_INFO_MESSAGE", 0, self.g.ERR_TRADE_COMPLETE)
        self.g.TRADE_PARTNER = None
        self.world.sync()


class World:
    """One group of players. Holds the true group roster and routes addon
    messages between players: group messages to everyone else in the group,
    addon whispers to the one target."""

    def __init__(self):
        self.members = []   # [{ name, leader, assist, class, zone }]
        self.raid = False
        self.players = {}   # name -> Player (only people running the addon)
        self.channels_shared = True  # do custom chat channels reach the other faction?

    # --- roster -----------------------------------------------------------
    def member(self, name):
        for m in self.members:
            if m["name"] == name:
                return m

    def in_group(self, name):
        return self.member(name) is not None and len(self.members) > 1

    def add(self, name, cls="WARLOCK", leader=False, zone="Undercity", join=True, faction="Horde"):
        """A player running the addon logs in (and joins the group, unless join=False)."""
        p = Player(self, name, cls, faction)
        self.players[name] = p
        if join:
            self.members.append(dict(name=name, leader=leader, assist=False, cls=cls, zone=zone))
        p.zone = zone
        self.push()
        p.g.Boot()
        p.fire("PLAYER_ENTERING_WORLD", True, False)
        self.roster_changed()
        return p

    def join(self, name, cls="WARLOCK", zone="The Barrens"):
        """Someone (with or without the addon) joins the group."""
        if self.member(name):
            return
        p = self.players.get(name)
        self.members.append(dict(name=name, leader=False, assist=False, cls=cls,
                                 zone=p.zone if p else zone))
        self.roster_changed()

    def leave(self, name):
        m = self.member(name)
        if not m:
            return
        self.members.remove(m)
        if m["leader"] and self.members:
            self.members[0]["leader"] = True
        if len(self.members) <= 1:
            self.raid = False
        self.roster_changed(also=[name])

    def move(self, name, zone):
        m = self.member(name)
        if m:
            m["zone"] = zone
        if name in self.players:
            self.players[name].zone = zone
        self.push()

    def roster_changed(self, also=()):
        self.push()
        for name, p in self.players.items():
            if self.member(name) or name in also:
                p.fire("GROUP_ROSTER_UPDATE")
        self.sync()

    # --- keep every runtime's view of the group in step ---------------------
    def push(self):
        grouped = len(self.members) > 1
        for name, p in self.players.items():
            t = p.L.table()
            if grouped and self.member(name):
                for i, m in enumerate(self.members, 1):
                    t[i] = p.L.table_from(dict(name=m["name"], leader=m["leader"], assist=m["assist"],
                                               **{"class": m["cls"]}, zone=m["zone"]))
            p.g.GROUP = t
            p.g.RAID = self.raid and grouped
            p.g.ZONE = p.zone

    def pull(self):
        """Pick up what players did to the group: assist, raid conversion."""
        for name, p in self.players.items():
            if not self.member(name):
                continue
            if p.g.RAID:
                self.raid = True
            for e in p.g.GROUP.values():
                m = self.member(e.name)
                if m and e.assist and not m["assist"]:
                    m["assist"] = True

    # --- message routing ----------------------------------------------------
    def deliver(self):
        """Route every new addon message the way the game does:
        PARTY/RAID to everyone else in the group, WHISPER to one player of the
        same faction (grouped or not), CHANNEL to everyone in that chat channel."""
        moved = False
        for name, p in list(self.players.items()):
            msgs = list(p.g.ADDON_MSGS.values())
            new, p.msg_cursor = msgs[p.msg_cursor:], len(msgs)
            for m in new:
                prefix = m.prefix or "SUMMONCIRCLE"
                extra = ()
                if m.chatType == "WHISPER":
                    q = self.players.get(m.target)
                    to = [m.target] if q and q.faction == p.faction else []
                elif m.chatType == "CHANNEL":
                    chan = p.g.JOINED[m.target]
                    to = [n for n, q in self.players.items()
                          if n != name and chan in list(q.g.JOINED.values())
                          and (self.channels_shared or q.faction == p.faction)]
                    extra = ("", 0, m.target, chan)
                else:
                    if not self.in_group(name):
                        continue
                    to = [n for n in self.players if n != name and self.in_group(n)]
                for n in to:
                    self.players[n].fire("CHAT_MSG_ADDON", prefix, m.text, m.chatType, name + REALM, *extra)
                    moved = True
        return moved

    def sync(self):
        """Settle immediate effects: pick up group changes, deliver queued frames."""
        self.pull()
        self.push()
        self.deliver()

    def tick(self, n=1):
        """n rounds of everyone's timers (1-second housekeeping, sends, heartbeats)."""
        for _ in range(n):
            for p in list(self.players.values()):
                p.g.RunTimers(1)
            self.sync()

    def advance(self, seconds):
        for p in self.players.values():
            p.g.Advance(seconds)

    def errors(self):
        return {n: p.errors() for n, p in self.players.items() if p.errors()}
