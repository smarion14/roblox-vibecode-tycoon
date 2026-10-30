# Act 2 (Move Out), Employees and Cutscenes: Design

Date: 2026-10-30
Status: Draft for approval
Builds on: `2026-10-30-vibecoder-startup-tycoon-design.md` (the game design). Act 1 is built and playable.

## 1. Intent

Act 1 ends with the player paying rent to their older brother. Act 2 moves the player out of the brother's living room and into their **own small office**, the first real step of the startup.

The game follows the progression shape of START AN EMO BAND FROM YOUR GARAGE TYCOON (Badass Experiences), down to how acts open and close. Three things carry over from that game:

1. **Real in-engine cutscenes** at act boundaries: camera shots, characters acting things out, a dialogue box, letterbox bars, a title card and a joke beat.
2. **Naming your venture.** The emo band game has you name your band and pick its poster. Here you name your startup when you move into the office.
3. **Members appear as your friends.** The emo band game shows band members as your Roblox friends' avatars. Here, employees are.

This document also fixes a problem: **hiring in Act 1 "kinda does nothing"** (the owner's words). Hires move to Act 2, where they appear as people at desks.

## 2. Goals, non-goals, anti-goals

**Goals**
- Three cutscenes in the reference game's style: the Act 1 opening, the Act 1 ending, and the Act 2 opening.
- The unit transforms from the brother's living room homelab into a small office when Act 2 begins.
- The player names their startup. The name shows on the office sign and can be changed later.
- Employees exist only from Act 2. Each one sits at a desk as an NPC wearing a friend's avatar, works visibly, and pre-builds a part for each job.
- Act 2 gameplay: new clients and project types, and an act goal of reaching a valuation target.

**Non-goals (this design)**
- The Act 2 ending cutscene and Act 3. They will come later.
- Training or levelling up employees.
- Spectating other players' cutscenes. Each player's cutscene is private to them.

**Anti-goals (failure even if it technically works)**
- Unskippable cutscenes, or cutscenes that replay every time you join.
- Showing a startup name to other players without Roblox text filtering. This is a Roblox rules requirement.
- Act 1 hires still purchasable but doing nothing.
- Regional or real-world names, brands or slang (project rule, `CLAUDE.md`).
- Glowing pads or passive income. Employees only pre-build parts when the player takes a job, as hires already do.

## 3. Constraints

- Everything in `CLAUDE.md` applies: Rojo, Luau `--!strict`, `game:GetService` at the top, the `task` library, generalized iteration, typed code, the naming rules, server authority, English text and a generic setting.
- The established architecture applies:
  - pure rule modules in `ReplicatedStorage/Shared` with Lune tests
  - server services in `ServerScriptService/Services`
  - client controllers in `StarterPlayerScripts/Controllers`
  - shared UI effects in `UI/Juice`, `UI/Sfx` and `UI/Music`
  - every remote goes through `RemoteManager`
  - all tunables live in `GameConfig`
- Saves are versioned through `SaveSchema`. New fields must load safely from existing Act 1 saves.

## 4. Cutscene style (shared by all three)

The style of the reference game, agreed by the owner:

- **In-engine 3D scenes,** played only for the player they belong to, inside that player's own unit. Other players never see them.
- **Camera:** a sequence of shots (wide establishing shot, over-the-shoulder, close-up), with hard cuts or short eased moves between them.
- **Actors:**
  - a copy of the **player's own avatar**
  - the **brother** (the existing sibling character)
  - simple props such as the laptop lid, the cash stack and the phone
  - simple animations: walk in, turn, sit, gesture, hand over
- **Dialogue box** at the bottom with the speaker's name. Text types out, and click, Space or tap advances it.
- **Letterbox bars** on screen while a cutscene plays.
- **Sound:** a music sting under each cutscene, plus a sound for the title card.
- **Title card** at the end of each cutscene: a big slam-in, as in the existing banners.
- **A Skip button** is always visible.
- **Control:** the player's character is frozen and the HUD is hidden during a cutscene. Both come back when it ends or is skipped.
- **Seen flags:** each cutscene plays once per save. The server records it as seen when the cutscene finishes or is skipped, and doesn't replay it on rejoin.

## 5. The three cutscenes

All dialogue is English, with a generic setting. The brother is the player's older brother (he/him), a senior software engineer.

### 5.1 Act 1 opening (replaces the current text-overlay intro)
1. **Night, wide:** the neon megablock, then the camera pushes in on the player's unit.
2. **Close:** the player's avatar on the couch, face lit by the laptop.
3. **Over the shoulder:** the brother walks in and reads the screen, then reaches over and **closes the laptop lid**.
4. Brother: *"You're STILL doing this garbage? Typing wishes at a robot all night won't get you anywhere!"*
5. Brother: *"One month. Make rent, or you and your little robot pal are sleeping on the curb."* He walks off.
6. **Close on the player's face.** Title card: **ACT 1: MAKE RENT**, with the goal "Rent: $1500" (read from `GameConfig.RENT_GOAL`).

This replaces `IntroController`'s overlay. The `SeenIntro` save flag keeps meaning "Act 1 opening seen".

### 5.2 Act 1 ending (when the player pays rent)
Triggered by the existing pay-rent interaction with the brother:
1. **Medium shot:** the player hands over a stack of cash. The brother counts it twice.
2. Brother: *"...Okay. You can stay."* Then: *"Don't make it weird."*
3. **At the door,** the brother turns back: *"A buddy of mine is subletting a tiny office downtown. First month's free. Take it. Get off my couch."* This quietly shows he's on the player's side. The full payoff comes in the final act.
4. Title card: **ACT 1 COMPLETE**.
5. The scene runs straight into the Act 2 opening (§5.3).

This replaces the existing "RentPaid" full-screen card.

### 5.3 Act 2 opening
1. **A fade to black.** Typed text: *"Two weeks later…"*.
2. While the screen is black, the server transforms the player's unit into the office (§6). The player never sees it swap.
3. **Fade in, outside:** the camera glides through the office's glass door. The player's avatar walks in and looks around: empty desks with "NOW HIRING" sticky notes.
4. **The phone buzzes** with a text from the brother: *"don't burn it down"*.
5. **Name your startup** (§7). The name lights up on the neon sign over the door.
6. Title card: **ACT 2: MOVE OUT**, with the goal "Reach valuation x{target}".

## 6. The office (Act 2 unit)

The same unit footprint on the megablock floor. Its contents depend on the owner's act:

- **Unowned units, and owners in Act 1,** show the Act 1 homelab, as built today.
- **Owners in Act 2** see the office.

The office contains:
- **The four stations, upgraded:**
  - Frontend: a proper desk setup
  - Server Rack: a bigger rack
  - Database Console: a server cabinet
  - AI Model Rig: in a glass cooling cabinet

  They keep the same tags, attributes and minigames.
- **A meeting room** where the deploy terminal is a wall screen. Same tag and battle.
- **Four employee desks,** one beside each station. Each shows a "NOW HIRING" sticky note until that role is hired.
- **The startup sign** over the door: neon, showing the startup name, lit at night like other building lights. Interacting with it renames the startup, like the poster in the reference game.
- **Decor:** a coffee machine, a logo wall, plants and the existing night lights.
- **The laptop shop** becomes a desk computer, and the job phone stays. Same tags.
- **The brother** isn't in the office. He appears only in cutscenes and texts.

When a unit's owner changes act, or a player joins already in Act 2, the server rebuilds that unit's contents for the owner. When the owner leaves, it reverts to the Act 1 layout.

## 7. Startup name

- **Input:** a text box during the Act 2 opening, and later from the sign. 3–24 characters.
- **Filtering:**
  - The server filters the name with Roblox `TextService` **before** storing it or showing it to anyone.
  - Other players see the broadcast-filtered version.
  - If filtering fails or blanks the name, the player is asked to try again.
  - Until a valid name is set, the sign shows a default, e.g. "UNTITLED STARTUP".
- **Storage:** saved as a new save field.

## 8. Employees (hires)

- **Act 1:** hires disappear from the laptop shop. Only gear is sold.
- **Act 2:** the office desk computer sells hires, one per station role. These are the existing four, `GameConfig.HIRES`.
- **Effect:** unchanged from today. When the player accepts a job, each hired employee pre-builds their station's part at C quality (`Economy.ApplyHires`). The player can still play the station to upgrade it (upgrade, don't add).
- **Appearance:**
  - Each hired employee sits at their desk as an NPC wearing **one of the player's Roblox friends' avatars**, each employee a different friend if possible.
  - Players with fewer friends than employees get default or randomised avatars for the rest.
  - The employee loops a "working at desk" animation, and a small name tag shows their role, e.g. "Backend Intern".
- **Carry-over:** players who bought hires in Act 1 before this change keep them. They show up as employees on moving in, with no refund needed.

## 9. Act 2 gameplay

From the game design §5, Act 2:
- **Clients:** startups and agencies (generic names). They pay more than Act 1 clients, with tier multipliers above 40.
- **Projects:** mobile apps and games, each with its own recipe (parts list). Recipes lean on different stations so different employees matter.
- **Deploy battle:** harder in Act 2. More bugs per wave, faster dives and a tougher boss, through Act 2 battle tuning.
- **Act goal:** reach a valuation target. There's no rent.
- **The brother keeps texting after deploys.** The tone stays grudging and gets quieter, as already designed.
- **Act end:** reaching the target records "Act 2 complete". The Act 2 ending cutscene and Act 3 are out of scope here, so the act-complete moment can be a simple card until then.

## 10. Save data (additions)

Existing saves must keep loading:
- `Act` already exists (1–3). The Act 1 → Act 2 transition sets it to 2.
- **Saves that already paid rent** (`RentPaid = true` and `Act == 1`, made before this change) move on: on join, the server plays the Act 1 ending, then the Act 2 opening, then sets `Act = 2`. New fields are additive, and `Sanitize` defaults them, so no version bump is needed. *(Designer's call; the game has only test saves so far.)*
- New: the startup name (raw input is never stored; only the filtered text).
- New story flags: Act 1 ending seen, Act 2 opening seen. The existing `SeenIntro` stays the Act 1 opening flag.
- Hires are already saved (`Hires`).

## 11. Animations *(decided)*

- **The builder authors** custom animations as `KeyframeSequence` assets in the repo, synced by Rojo to `ServerStorage/Animations`. They cover at least:
  - laptop close
  - hand over cash
  - count cash
  - talk or gesture
  - sit on couch
  - sit at desk and type (looped, for employees)
- **The owner publishes** each one from Studio (right-click the `KeyframeSequence`, then "Save/Publish to Roblox") under the account or group that owns the experience. Roblox only plays animations owned by the experience's owner.
- **The owner pastes** the resulting asset IDs into an animation table in `GameConfig`. The builder provides a labelled slot and a publish checklist for each animation.
- **Fallback:** any animation without an ID falls back to Roblox's built-in walk, sit and idle, so cutscenes and employees never break.

## 12. Left to the builder

- Shot framing, camera paths, cutscene timings and animation choices, within §4–5.
- Exact office layout and props, within §6, built in code like the Act 1 homelab.
- Act 2 client names, project recipes, tier multipliers, valuation target and battle tuning, all in `GameConfig`. The valuation target is checked against the player's valuation when Act 2 starts, so a player who ground Act 1 still has a real goal: it's the starting valuation plus a fixed step.
- How avatars are copied for cutscenes and employees (client-side copies are fine). Fallback looks when friends' avatars can't be loaded.
- The music sting choice. It must come from the licensed Creator Store catalogs already used (Pro Sound Effects, APM, DistroKid official, Roblox).

## 13. Calls made by the designer (not explicitly decided by the owner)

- Act 2 is one office space. The game design's "coworking hot desk, then small office" is folded into the single office the owner asked for, and the brother's line points to a small sublet office so the story matches.
- Saves that already paid rent are moved into Act 2 on join, with both cutscenes played (§10).
- The unit swap happens while the screen is black, and units revert to the Act 1 layout when their owner leaves.
- Employees keep today's effect (C-quality pre-builds) and have no training or levels yet.
- The startup sign can be used to rename later, mirroring the reference game's poster.
- The Act 2 end is a simple card until its cutscene is designed.
