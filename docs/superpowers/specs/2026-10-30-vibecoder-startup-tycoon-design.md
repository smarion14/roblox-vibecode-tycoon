# Vibecoder Startup Tycoon — Game Design

Date: 2026-10-30
Status: Draft for approval

## 1. Intent

A Roblox tycoon about a young "vibecoder" who builds software by prompting AI, trying to prove they can make a living at it.

The reference is START AN EMO BAND FROM YOUR GARAGE TYCOON (Badass Experiences). The parts worth taking are its **record-then-perform loop** and its **story payoff**. Those are what make it feel immersive instead of like a generic tycoon. This game keeps both and fixes what that game gets wrong.

### What the reference does

- You record four parts (guitar, bass, drums, lyrics) at four physical stations. All four make one song, and songs can stack.
- You perform the songs in a rhythm minigame. Venue upgrades raise the pay, the crowd size and the song difficulty.
- Band members (shown as friends' avatars) can be bought to automate each station.
- Story: Dad kicks you out over your emo phase. At the end he reconciles and admits a band was his dream too.

### What this game fixes

| Reference weakness | This game |
|---|---|
| Rhythm-game accuracy has no effect on pay | Typing performance drives product quality and payout |
| A glowing circle in the driveway starts the show | A physical deploy terminal at your desk |
| Automation removes the player from the loop | Hires pre-fill at low quality; the player's own typing is the only path to top quality |
| The pressing-keys minigame is unrelated to songwriting | Typing prompts *is* vibecoding, so the minigame is the fantasy itself |

## 2. Goals, non-goals, anti-goals

**Goals**
- The core loop of building at stations and shipping in a deploy battle feels skillful, punchy and readable within the first two minutes.
- The story frames the grind and pays off with a sincere ending.
- It plays well on keyboard and on touch.
- A full run to the ending takes about 2–3 hours.

**First build: the Act 1 vertical slice** *(decided)*
- In scope:
  - The opening scene.
  - The couch-stage unit with the 4 stations.
  - Typing bursts with quality grades.
  - Act 1 clients and the landing-page project type.
  - The deploy battle (keyboard and touch).
  - Server-side scoring, payout and valuation.
  - Gear and hires purchasable with cash.
  - DataStore saving.
  - Act 1 ends when rent is paid.
- Built in later milestones, in this order: Acts 2–3 and the ending; multiplayer spectating; leaderboards; monetization.
- The full design below is the target. The slice must not block it. For example, the save schema already holds the act and progression fields.

**Non-goals (v1)**
- Replay or prestige after the ending. This will be decided later.
- Co-op startups. Each player runs their own.
- Localization. All text is English.

**Anti-goals (failure even if it technically works)**
- Glowing button pads, passive collection bins, or income that accrues without the player.
- 2x cash passes, skip buttons, energy timers, loot boxes or paid random items.
- Any regional or country-specific setting, names, slang or brands. The setting is generic.
- Any value computed on the client and trusted by the server.

## 3. Constraints

- Everything in `CLAUDE.md` applies: Rojo, Luau `--!strict`, `game:GetService` at the top, the `task` library only, generalized iteration, typed functions, and the naming conventions.
- Server-authoritative. The server owns all wallet, component, quality, score and progression state.
- Aesthetic: a gritty cyberpunk/vaporwave office, clicky keyboard sounds, glowing retro terminals and moody lighting.

## 4. Core loop

1. **Take a job.** The player accepts a client job at their desk. The job names the client, the project type and the payout tier.
2. **Build at stations.** The player walks to the four workstations and plays a short typing burst at each to produce components.
3. **Ship at the deploy terminal.** The player walks to the deploy terminal and plays the deploy battle.
4. **Reception and payout.** The battle result sets the product's reception, which sets the cash and valuation gained.

### 4.1 Workstations (record)

There are four physical stations in the player's unit, one per component:

| Station | Component (existing code name) |
|---|---|
| Frontend terminal | `FrontendUnits` |
| Server rack | `BackendEndpoints` |
| Database console | `DatabaseTables` |
| AI model rig | `PromptTokens` |

- Interacting with a station starts a **typing burst**: about 3 short prompts in about 10 seconds, with a draining timer bar.
- Speed and accuracy give the produced component a **quality grade** (C, B, A or S).
- Each produced component unit stores its own grade (save as a count per component per grade). Quality changes payout only indirectly: it sets the deploy battle's starting difficulty, and that sets the score. *(My call.)*
- Each project type has a **recipe**: how many of each component it needs. For example, a landing page is frontend-heavy, an API is backend-heavy, a game leans on prompt tokens, and an AI agent leans on the AI rig and the backend.
- **Upgrade, don't add** *(decided 2026-10-30, replaces stacking)*: once a part meets the recipe, another run at that station replaces your worst copy if the new grade is better and otherwise changes nothing. The station prompt reads "Improve (C)" so players know before they start. This removes the "grind your best station" payout exploit and keeps retry-to-improve. Better parts still pay off through an easier deploy battle.

### 4.2 Deploy battle (perform)

Layout (agreed mockup: `.superpowers/brainstorm/*/content/deploy-battle-v2.html`):

- **Left panel: the client on a live call.** It shows their face, live reaction lines and a **mood bar**.
- **Centre: the main prompt.** This is a longer prompt to type, and completing prompts fills **ship progress**.
- **Bugs.** Short words (`null`, `cors`, `race`, `typo`, ...) crawl toward the prompt. Typing a bug's word squashes it.
- **Combo counter.** Streaks of clean input build the combo. When a bug reaches the prompt, it drops the client's mood and resets the combo.
- **Starting difficulty** depends on component quality. Low-quality components mean more bugs from the start and a less patient client.
- **End:**
  - **Success:** ship progress reaches 100%. Final mood and the combo/accuracy stats set the reception.
  - **Failure:** mood reaches 0. Nothing is paid, and the components are kept so the player can retry. *(My call.)*
- **Reception** maps to `performanceScore` in 0–2.0. Payout: `total components × Valuation × performanceScore × clientTierMultiplier`. The job's payout tier is that multiplier, and it rises with each client tier. *(My call; this extends the Phase 1 formula.)* Good receptions also raise **Valuation**.

### 4.3 Input modes

- **Keyboard:** type the prompts.
- **Touch:** each prompt breaks into word chips scattered on screen, and the player taps them in order. The timer, combo and bugs are the same.
- **Gamepad:** uses the touch chip mode with a selection cursor. *(My call; this wasn't discussed.)*
- Leaderboards keep keyboard and touch scores separate.

## 5. Progression

The player's plot is a **unit in a neon megablock**, next to the other players' units. It physically transforms as the player progresses.

| | Act 1: Make Rent | Act 2: Move Out | Act 3: Launch |
|---|---|---|---|
| Space | The sibling's couch and a folding table | A coworking hot desk, then a small office | A loft floor with a skyline view |
| Clients | Local small businesses (pet groomer, food truck) | Startups and agencies | Corporate clients, then a demo day in front of investors |
| Projects | Landing pages | Mobile apps and games | AI agents and platforms |
| Battle | Few bugs, a patient client | More bugs, longer prompts | Swarms of bugs, a picky client, a boss-style demo day |
| Story beat | The rent deadline | First investor; the sibling's texts get quieter | The launch and the reveal ending |

**How the player moves up** *(my call; the owner deferred to the designer)*:
- **Act gates are milestones, not purchases.** Act 1 ends when the player has paid rent (a fixed cash goal). Act 2 ends at a valuation target. Act 3 ends at demo day.
- **The unit transforms automatically** at each milestone, as a story beat. There is no tycoon-style buying of walls or rooms.
- **Cash buys only gear and hires,** from a shop on the in-unit desk computer (a physical interaction, not a pad).
- **Rent is story, not a clock.** "One month" is flavour. There is no in-game countdown and no fail state for missing rent. *(Decided.)*

**Hires** *(my call)*:
- A hire produces its C-grade unit at the moment a job is accepted. There's no timer, no offline accrual, and nothing happens without a player action.
- When the player runs the burst at that station, their result replaces the hire's unit if it's better.

Systems that grow across the acts:

- **Gear modifies the minigame and never generates passive income.** For example, a mechanical keyboard gives a longer timer, a second monitor previews the next prompt, and a better AI model forgives one typo per burst.
- **Hires** pre-fill a station's component at C quality. The player can still run the burst themselves to raise the quality. Hires speed up the early game without replacing the player.
- **Valuation** rises with good receptions and multiplies all later payouts.

## 6. Story

- **The doubter: the player's older sibling, a senior software engineer.** They learned to code the hard way and think vibecoding is cheating.
- **Opening scene:** it's 3 AM, the player is on the sibling's couch shipping their first AI-built app, and the sibling closes the laptop:
  > "That's not coding. That's autocomplete in a hoodie. You've got one month to make rent or you're out."
- **During the run:** the sibling texts after deploys. The tone moves from mocking ("lol it crashed for me") to grudging ("...how much did that pay?").
- **Ending:** the sibling shows up at the launch and admits they were laid off months ago, replaced by the same kind of AI tool the player uses. They were too proud to say so, and the rent demand was because they couldn't pay it themselves. They ask if the player is hiring.
- The theme is craft versus AI, told through family pride. As in the reference, the doubter turns out to share the player's fear and dream.
- All names and text are English and the setting is generic. Client names in the mockups ("Dale", "Pet Grooming App") are placeholders.

## 7. Multiplayer

- Each player runs their own startup side by side, about 6 players per server *(my call)*, each with their own megablock unit.
- Players can walk into friends' units and watch their deploy battles.
- Hype gifts (see §8) let spectators affect the *feel* of a friend's battle, never its outcome.

## 8. Monetization

Robux buys expression and content, never power or progress.

1. **Ship finishers:** go-live animations and effects that the whole floor sees.
2. **Keyboard switch packs:** switch sounds and keycap looks, audible to anyone nearby.
3. **Desk companions:** pets and props that react to play (a cat crosses the keyboard on a combo break; a duck squeaks at x25).
4. **Prompt themes:** reskinned prompt text at the same difficulty (pirate, Shakespearean, corporate jargon).
5. **Bonus client stories:** paid side-quest clients with their own short arcs. They reward story and cosmetics only, with no extra cash or valuation beyond a normal job's pay. *(My call.)*
6. **Hype gifts:** a few Robux sends a cosmetic effect (a coffee, an airhorn) into a friend's live battle.
7. **General cosmetics:** desk and room themes, terminal colour schemes and outfits.
8. **Group-join bonus:** a small cash bonus (+5%), as the reference does. It's free, so it isn't paid power. It does not apply to leaderboard scores.

**Leaderboards** (later milestone) *(my call)*:
- **Global valuation** (OrderedDataStore). It doesn't depend on input mode.
- **Best deploy battle score, split by input mode.** The server can't prove the input mode, so this board is cosmetic-only status, and that risk is accepted.
9. **Private servers:** Roblox's built-in feature.

Excluded: 2x cash, skips, energy timers, loot boxes and paid random items.

## 9. Server authority and anti-cheat

- **The server issues every prompt and bug schedule** (seeded per battle and burst) and records when it was issued.
- **The client sends raw input results:** typed text per prompt and squash attempts per bug.
- **The server validates:**
  - The text matches the issued prompt.
  - Timing is humanly possible (a maximum characters-per-second cap).
  - A squashed bug existed and was in range at that time.
- **The server computes** quality grades, mood, combo, reception, `performanceScore`, cash and valuation. The client only animates what the server confirms.
- All remotes go through `RemoteManager` with rate limits.

## 10. Persistence

Progress is saved across sessions with DataStore: cash, valuation, act and story progress, unlocked gear, hires, owned cosmetics, and current components. *(My call: a 2–3 hour run needs saving.)* The current in-memory `StartupDataModule` will need this.

## 11. Fit with existing code (Phase 1)

| Existing | Status |
|---|---|
| `RemoteManager.luau` (remotes, rate limit) | Keep; all new remotes go through it |
| `StartupDataModule.luau` (Cash, Valuation, 4 component counts) | Keep the shape; add quality grades, progression state and persistence |
| `AssemblyService.luau` (`HasAllComponents`, `DeployProduct`) | `HasAllComponents` becomes a recipe check per project type; `performanceScore` must come from the server-side battle evaluation |
| Payout `total × Valuation × score`, score capped at 2.0 | Keep the cap; add `× clientTierMultiplier` (§4.2) |

Nothing currently `require`s these modules. A server bootstrap `Script` is needed.

## 12. World and assets

- The designer builds the 3D world and all code *(decided)*.
- First pass: blockout geometry built from code or Rojo model files, using Roblox built-in parts, materials, lighting and free/built-in sounds. Everything must be playable without uploaded art.
- Final art can replace the blockout later. Code must find world objects by name or tag, not depend on their exact geometry.

## 13. Left to the builder

- All numbers and balance: timers, prompt lengths, bug speeds, payouts, prices, recipe sizes and act thresholds.
- Prompt, bug-word and client dialogue writing, within §6 and the English/generic rule.
- Art, sound, lighting, the exact UI layout beyond §4.2, and the unit transformation visuals.
- The internal module breakdown, within `CLAUDE.md`'s directory map.

## 14. Calls made by the designer (not explicitly decided by the owner)

- Act gates are milestones and the unit transforms automatically; cash buys only gear and hires.
- Hires fill a C-grade unit when a job is accepted, never on a timer.
- Battle failure pays nothing and keeps the components.
- Quality is stored per unit and affects payout only through battle difficulty.
- The client tier is an extra payout multiplier.
- Bonus client stories pay story and cosmetics, not cash.
- Leaderboards: global valuation, plus best battle score per input mode (cosmetic status).
- Gamepad uses the touch chip mode.
- About 6 players per server.
- DataStore persistence.
- ~~Extra components beyond the recipe add value (stacking).~~ Replaced by upgrade-don't-add (see §4.1).
- The group bonus does not affect leaderboards.
