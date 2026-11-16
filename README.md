![Summon Circle](art/social-preview.png)

# Summon Circle

A WoW Forever addon for warlocks who run a summoning service together. One shared queue, fair turns, payment tracking and a shared blacklist, so the whole circle can focus on clicking portals. Every summoner needs the addon; customers don't.

## Features

### For everyone
- **One shared queue:** customers whisper `inv`, `invite`, `summon` or `+` to any summoner. They're invited automatically, told their place in line, and every summoner sees the same queue.
- **Fair rotation:** summoners take turns in order. Anyone out of soul shards or AFK is skipped, and whoever summons out of turn simply moves the turn along.
- **A "what to do now" box:** one big button walks you through each customer: **Summon → Trade → Kick**. No guessing whose turn it is or what's next.
- **Summon requests from chat:** while you're open, the addon reads your advertising channels for people asking for a summon to your city ("WTB UC summon", "LF port to undercity 20s") and lists them under **Requests**, next to the queue. One click whispers them your price. Nothing is ever whispered automatically, and once anyone in the circle whispers or dismisses a request, that player stays hidden for 10 minutes for the whole circle, so they never get three identical whispers.
- **Portal alerts:** when another summoner opens a portal, you get an on-screen warning and a sound telling you to click it.
- **Payment tracking:** trades are detected automatically. Earnings are tracked per summoner, along with gold per hour.
- **Non-payment handling:** customers who don't pay within 3 minutes are flagged. You can kick them or kick and blacklist them, and anyone who leaves without paying can be blacklisted in one click.
- **Shared blacklist:** blacklisted players aren't invited when they whisper. Every add or removal reaches every Summon Circle user on your faction within seconds, grouped or not, and full lists merge between summoners whenever they group up, so anyone who was offline catches up. Each entry shows who added it.

### For customers
- **Find a Summon:** if you run the addon but aren't a warlock, `/sc` opens a list of every circle on your faction that's open for business: where it is, whose circle and how many summoners, its price, and how long the line is. Pick one and click **Get summoned**: it whispers the circle for you (to another summoner if the leader is AFK), and the circle's invite and "you're #3 in queue" reply take it from there. Warlocks get the same list as their third tab.

### For warlocks looking for a circle
- **Find a Circle:** a tab listing every circle on your faction that's looking for summoners: where it is, how many summoners it has (2/3), its price, its queue, and how many summons it has left (hover for each summoner's shards). One click on **Ask to join** whispers the leader and puts you on their list.

### For the group leader
- **Open for business / Close shop:** the addon does nothing until you open. It never interferes with questing groups or dungeons, and it closes itself when you log out or leave the group.
- **Pick your summoners:** choose which warlocks in the group are summoning. They get assist automatically.
- **Advertise in one click:** posts your ad to every chat channel you choose, with your city, price and queue length filled in.
- **Looking for summoners:** tick it and your circle shows up in other warlocks' Find a Circle tab. Applicants appear under your summoners with where they are and how many shards they have; one click invites them, and they become a summoner as soon as they join. Recruiting stops by itself at 3 summoners.
- **Shared price:** set it once and every summoner's replies and ads use it.

### Under the hood
- **Stays in sync even when the group changes:** if the leader leaves, another summoner takes over the queue without losing anything.
- **Private:** queue and blacklist data is only shared with the group's summoners, never with customers.
- **Raid only when needed:** the group becomes a raid only once a second summoner joins or the party is nearly full.

## Install
**WowUp:** Get Addons → Install from URL → paste `https://github.com/edgaming/SummonCircle`. Pick **WoW Forever** at the top first.

**Manually:** download the zip from the latest [release](https://github.com/edgaming/SummonCircle/releases) and unzip it into your Forever `Interface/AddOns/` folder.

## Quick start
Type `/sc` to open the window.

**Leader**
1. Invite the other summoners, click the gear next to **Summoners**, and tick them.
2. Click the gear next to **Advertise** to set your price, channels and message.
3. Click **Open for business**. The bar turns green.
4. Click **Advertise** whenever you want to post. Click **Close shop** when you're done.

**Summoners**
Read the purple box and press the big button under it.

## Commands
`/sc` (or `/summoncircle`) toggles the window. `/sc help` lists the rest: whisper triggers, the thanks message, a sound for new requests (`/sc sound on`), blacklist management (`/sc bl add First Last [reason]`, `/sc bl del First Last`, `/sc bl list`), earnings reset and lifetime stats. `/sc net` says whether the network is working. `/sc minimap` hides or shows the minimap button. The window also opens from the minimap button or the game's addon menu on the minimap.

## Known limitations
- Customers inside a dungeon or battleground aren't flagged yet. A summon to them just times out and they go back into the queue.

## Development
### Layout
The `.toc` loads the files in this order. Each layer only uses the ones above it.

| Folder | What's there |
|---|---|
| `Core/` | Namespace, settings, event dispatch and the internal event bus (`Core.lua`); pure helpers like money and names (`Util.lua`); the thin layer over WoW's API (`Game.lua`); cities and their nicknames (`Locations.lua`). |
| `Net/` | The wire format (`Protocol.lua`); sending and receiving addon messages (`Transport.lua`); the faction-wide network channel (`Channel.lua`); who's in the group and who runs the addon (`Roster.lua`). |
| `Domain/` | The circle itself: shared state and sync (`Sync.lua`), open/close and summoners (`Session.lua`), turn order (`Rotation.lua`), earnings (`Ledger.lua`), `Blacklist.lua`, customers (`Queue.lua`), `Advertise.lua`, reading chat for requests (`ChatParser.lua` decides what counts, `Leads.lua` keeps the list), and "what do I do now" (`Advisor.lua`). |
| `UI/` | The style guide in code (`Style.lua`: colours and the hover / selected / new treatments), widget helpers, the main window, one file per page and side panel. |
| `Commands.lua` | Slash commands. |

A few rules keep it modular:
- Modules are tables on the namespace (`ns.Queue`, `ns.Session`, ...) and are called with a dot: `ns.Session.Start()`.
- Features never call WoW's messaging API directly. They use `Transport.Send` and `Transport.Handle("TYPE", fn)`. Message types a client doesn't know are ignored, so new messages don't break older versions.
- Changes to the shared state are ops, registered with `Sync.RegisterOp` and applied with `Sync.Do`.
- UI code takes colours and hover/selected/new looks from `UI/Style.lua` (design doc 06), never its own numbers: purple = selected, gold = new, a faint band = hover, status colours only for status.
- Domain code never touches the UI. It calls `ns.Update()` and the window refreshes itself. Modules announce events (`GROUP_JOINED`, `PEER_SEEN`, `SUMMONERS_CHANGED`, ...) with `ns.Emit`, and others subscribe with `ns.Listen`.

### Tests
`pip install lupa`, then `python tests/run.py`. The tests also run on GitHub for every push.
- `tests/t_*.lua` load the addon in a fake WoW environment (`tests/wowmock.lua`) as one player. The unit tests (`t_util`, `t_protocol`, `t_transport`, `t_locations`) live here too, plus `t_chatparser`, which runs every line in `tests/chat_lines.txt`. When a chat line is misread in game, add it to that file.
- `tests/t_*.py` are multi-player scenarios. `tests/harness.py` runs a separate copy of the addon for each player in one group and routes addon messages between them the way the game does (group messages to everyone else, addon whispers to one player, realm suffix on sender names). `t_circle.py` runs a full circle from picking summoners to payment. `t_requests.py` covers summon requests from chat across the circle. `t_findsummon.py` covers customers finding open circles. `t_findcircle.py` covers circles recruiting over the network and warlocks asking to join. `t_netblacklist.py` covers blacklist entries spreading over the faction network. `t_resilience.py` covers privacy from customers with the addon, blacklist sharing, timeouts, customers who leave without paying, and the leader leaving mid-session.

### Releasing
- Change the number in `VERSION` (e.g. `0.7.0`) and push to `main`. GitHub Actions runs the tests, creates the tag, packages the addon with the BigWigs packager, and publishes a release. WowUp offers the update to anyone who installed from the repo URL.
- The version shown in game comes from the tag. The `@project-version@` placeholder in the `.toc` is filled in when the release is packaged.

### Art
`art/icon.svg` is the icon source. `Media/icon.tga` (64×64) is the in-game icon, set via `## IconTexture` in the `.toc`. `art/social-preview.png` is the 1280×640 banner used for the GitHub social preview, which WowUp shows as the addon's image.
