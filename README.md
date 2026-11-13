# Summon Circle (WoW Forever, interface 16001)

Helps a group of warlocks run a summoning circle: one shared queue, a rotation, payment tracking and a shared blacklist. Every summoner needs the addon.

## Install
**WowUp:** Get Addons → Install from URL → paste this repository's GitHub URL.

**Manually:** download the zip from the latest GitHub release and unzip it into your Forever `Interface/AddOns/` folder.

## How to use it
The addon is **closed** until the leader clicks **Open for business**. While it's off it never does anything on its own: no raid conversion, no auto-invites, no whisper replies. That keeps it from interfering when you group up to quest.

**Leader**
1. Invite the other summoners. Click the gear next to **Summoners** and tick them.
2. Click the gear next to **Advertise** to set the price, channels and message.
3. Click **Open for business** in the status bar at the top. It turns green. If the other summoners need assist, the box below asks you to give it with one click.
4. Click **Advertise** whenever you want to post. Click **Close shop** (same spot) when you're done.

The shop also closes by itself when you log out or leave the group. A `/reload` doesn't end it.

**Everyone**
Read the purple banner and press the big button under it: **Summon Bob → Trade Bob → Kick Bob**. When someone else's portal goes up, you get an on-screen warning and a sound.

Customers can whisper **inv**, **invite**, **summon** or **+** to any summoner while you're open.

The group only becomes a raid when it's needed: when there's more than one summoner (assist only exists in raids), or when the party is nearly full.

## Non-payment and the blacklist
- **Hasn't paid after 3 minutes:** the banner offers **Kick** or **Kick + blacklist**. You can still trade them from their row.
- **Left without paying:** the summoner who's owed gets **Blacklist** or **Let it go**.
- **A blacklisted person whispers:** they aren't invited. The banner shows why, who added them and when, with **Invite anyway** or **Ignore**.
- Blacklists sync whenever summoners group together. Entries don't expire. Remove one with `/sc bl del <name>`.

## Privacy
The queue, earnings and blacklist are only sent privately to the summoners the leader picked. Other group members, including customers who run the addon, only receive a harmless "I'm here" ping (shard count and AFK). The addon also ignores queue changes and blacklist entries from anyone who isn't a summoner.

## Commands (rarely needed)
`/sc` toggles the window. `/sc help` lists the rest: whisper triggers, thanks message, blacklist, earnings reset, lifetime stats.

## Untested (watch for Lua errors)
- Auto-invite, whisper replies and raid conversion happen without a click. If Forever requires one, those steps will need a button.
- Kick and Trade run from the big button's click. Promote runs from the picker checkbox.
- Shard counting uses item 6265, with the SoulShards power type as a fallback.
- Arrival detection: a customer counts as arrived when the raid roster shows them in your zone.
- Customers in dungeons or battlegrounds aren't flagged yet. A summon to them just times out.

## Development
- **Tests:** `pip install lupa`, then `python tests/run.py`. This loads the addon in a fake WoW environment (`tests/wowmock.lua`) and runs every `tests/t_*.lua` scenario. The tests also run on GitHub for every push.
- **Releasing:** change the number in `VERSION` (e.g. `0.6.1`) and push to `main`. GitHub Actions runs the tests, creates the tag, packages the addon with the BigWigs packager, and publishes a release. WowUp offers the update to anyone who installed from the repo URL.
- The version shown in game comes from the tag. The `@project-version@` placeholder in the `.toc` is filled in when the release is packaged.
