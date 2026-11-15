-- /sc demo: made-up data for trying the window alone. Nothing is sent.
PLAYER_CLASS = "MAGE"
ME_NAME = "Dana Mage"
Boot()
local UI = ns.UI
check("a mage has no tabs", not UI.HasTabs())
SlashCmdList.SUMMONCIRCLE("demo tabs")
check("demo tabs: tabs on any class", UI.HasTabs())
check("demo tabs: the tab bar shows", SummonCircleFrame.tabs[2]:IsShown())

ADDON_MSGS, SENT = {}, {}
SlashCmdList.SUMMONCIRCLE("demo circles")
eq("demo circles: three listed", #ns.Listings.Recruiting(), 3)
UI.ShowPage("find")
local page = UI.pages[1].frame
local shown = {}
for _, r in ipairs(page.rows) do if r:IsShown() then shown[#shown + 1] = r end end
eq("demo circles: three rows", #shown, 3)
check("demo circles: closest to full first", shown[1].name:GetText() ~= "Vex Shadow")
check("demo circles: the 1-summoner circle last", shown[3].name:GetText() == "Vex Shadow")
shown[1]:GetScript("OnClick")()
page.ask:GetScript("OnClick")()
eq("demo circles: Ask to join turns into Asked", page.ask:GetText(), "Asked")
eq("demo circles: no whisper sent", #SENT, 0)

-- Tabs: same size, one selected.
local t1, t2 = SummonCircleFrame.tabs[1], SummonCircleFrame.tabs[2]
check("tabs: Find a Circle selected", t2.selected and not t1.selected)
check("tabs: the selected one glows", t2.glow:IsShown() and not t1.glow:IsShown())
t1:GetScript("OnClick")()
check("tabs: back to My Circle", UI.page == "circle" and t1.selected and SummonCircleFrame.content:IsShown())

SlashCmdList.SUMMONCIRCLE("demo applicants")
local apps = ns.Recruit.Applicants()
eq("demo applicants: two", #apps, 2)
check("demo applicants: rows show", SummonCircleFrame.appRows[1]:IsShown() and SummonCircleFrame.appHeader:IsShown())
ns.Recruit.Invite(apps[1].name)
check("demo applicants: Invite marks them invited", apps[1].invited)
eq("demo applicants: no real invite", #SENT, 0)

SlashCmdList.SUMMONCIRCLE("demo clear")
eq("demo clear: circles gone", #ns.Listings.Recruiting(), 0)
eq("demo clear: applicants gone", #ns.Recruit.Applicants(), 0)
check("demo clear: tabs off again", not UI.HasTabs())
eq("nothing went over the network", #ADDON_MSGS, 0)

-- Queue and requests demo.
ME_NAME = "Dana Mage"
SENT, ADDON_MSGS = {}, {}
SlashCmdList.SUMMONCIRCLE("demo queue")
local n = 0
for _ in pairs(ns.S.queue) do n = n + 1 end
eq("demo queue: seven customers", n, 7)
RunTimers(2)
n = 0
for _ in pairs(ns.S.queue) do n = n + 1 end
eq("demo queue: housekeeping leaves them alone", n, 7)
ns.Queue.Kick("Bob Smith")
check("demo queue: Kick just removes them", ns.S.queue["Bob Smith"] == nil)
eq("demo queue: no whisper, no uninvite", #SENT, 0)

SlashCmdList.SUMMONCIRCLE("demo requests")
eq("demo requests: three", #ns.Leads.Sorted(), 3)
RunTimers(2)
eq("demo requests: kept while the shop is closed", #ns.Leads.Sorted(), 3)
ns.Leads.Whisper("Gorak Stone")
check("demo requests: Whisper removes it", ns.Leads.list["Gorak Stone"] == nil)
eq("demo requests: nothing sent", #SENT + #ADDON_MSGS, 0)
UI.ShowView("requests")
check("demo requests: rows show", SummonCircleFrame.content:IsShown())

SlashCmdList.SUMMONCIRCLE("demo clear")
n = 0
for _ in pairs(ns.S.queue) do n = n + 1 end
eq("demo clear: customers gone", n, 0)
eq("demo clear: requests gone", #ns.Leads.Sorted(), 0)
SlashCmdList.SUMMONCIRCLE("demo all")
check("demo all: everything at once", #ns.Leads.Sorted() == 3 and #ns.Listings.Recruiting() == 3)

-- Queue statuses: short, one line, "you" when it's about me.
local S = ns.UI.STATUS
local now = GetServerTime()
local me = ns.Me()
check("status: owes you", S.ARRIVED({ caster = me, arrivedAt = now - 117 }, now):find("owes you · 1:57") ~= nil)
check("status: owes someone else", S.ARRIVED({ caster = "Bram Lock", arrivedAt = now - 10 }, now):find("owes Bram Lock · 0:10") ~= nil)
check("status: unpaid", S.ARRIVED({ caster = "Bram Lock", arrivedAt = now - 999 }, now):find("unpaid · owes Bram Lock") ~= nil)
check("status: I'm summoning", S.SUMMONING({ caster = me, castAt = now - 5 }, now):find("you're summoning · 0:05") ~= nil)
check("status: someone summoning", S.SUMMONING({ caster = "Bram Lock", castAt = now - 97 }, now):find("Bram Lock summoning · 1:37") ~= nil)

-- Find a Summon with made-up circles (we're a mage standing in Undercity).
SlashCmdList.SUMMONCIRCLE("demo clear")
SlashCmdList.SUMMONCIRCLE("demo circles")
local open = ns.Listings.Open()
eq("find a summon: open circles, minus the one in our own city", #open, 3)
check("find a summon: shortest wait first", open[1].queue <= open[2].queue and open[2].queue <= open[3].queue)
UI.ShowPage("summon")
local sp = UI.pages[2].frame
sp.rows[1]:GetScript("OnClick")()
check("find a summon: picked", sp.get:IsEnabled())
SENT = {}
sp.get:GetScript("OnClick")()
eq("find a summon: a made-up circle gets no whisper", #SENT, 0)
eq("find a summon: but the button changes", sp.get:GetText(), "Requested")
-- Already in a group (not a circle's): leave it first.
GROUP = { { name = "Dana Mage", leader = true }, { name = "Zed Pal" } }
ns.Roster.Scan()
ns.Update()
check("find a summon: in a group, told to leave it first", sp.hint:GetText():find("Leave your group first") ~= nil)
check("find a summon: and the button is off", not sp.get:IsEnabled())
GROUP = {}
