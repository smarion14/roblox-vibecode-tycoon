# Act 3: Big Tech Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The final act. The startup becomes a big tech company on an enclosed two-floor campus, defends itself from incidents with key hires, builds reputation (a money multiplier) at conferences, fights a bullet-hell deploy battle, and ends the story at $40,000 earned, followed by free play.

**Architecture:** As in Acts 1–2, rules live in pure, Lune-tested modules in `ReplicatedStorage/Shared`, and server services apply them:
- **Pure modules:** `Reputation`, `Incidents`, the three incident minigames, `Keynote`, `BulletHell`, plus additions to `Story`, `SaveSchema` and `Cutscenes`.
- **New server services:** `IncidentService` and `ConferenceService`.
- **Extended services:** `BattleService` routes Act 3 to the bullet hell; `ProgressService` runs the Act 2→3→finale story.
- **Client:** new controllers for incidents, conferences and the bullet hell, plus the extended cutscene player.

**Tech Stack:** Roblox Luau `--!strict`, Rojo 7.7, Lune 0.11 (`lune run tests/run.luau`), luau-lsp.

**Spec:** `docs/superpowers/specs/2026-10-30-act3-big-tech-design.md`

## Global Constraints

- **Code style (`CLAUDE.md`):** `--!strict`; `game:GetService` at the top; `task` library only; no `pairs`/`ipairs`; typed; English copy in a generic setting; cyberpunk/vaporwave look; code-built art; sounds only from the existing licensed set or the Creator Store's licensed catalog.
- **Pure modules** in `Shared` have no requires and no Roblox APIs (`Random` included; `BulletHell` carries its own seeded PRNG).
- **Server authority:** every incident, minigame result, reputation change, conference grade, kill claim, ship move and payout is validated on the server. Cash only comes from deploys the player plays. Incidents never take cash, parts or hires (spec §2).
- **Client state:** read it through `UI/ClientState` (the single `StateSync` listener). Hold the character still during activities through the `Activity` player attribute (`ActivityLockController`).
- **Verification for every task:**
  - `lune run tests/run.luau` passes.
  - `rojo sourcemap -o sourcemap.json && luau-lsp analyze --sourcemap=sourcemap.json --definitions=types/globalTypes.d.luau src` is clean.
  - `rojo build -o game.rbxl` succeeds.
- **Cutscenes** use the established style: letterbox, camera rig, `Focus`/`Fx` close-ups on the brother, shakes and zooms, about 8 studs/s walks.
- **Spec numbers:**
  - **Reputation:** 0–100, starts at 50, multiplier x0.8–x1.5 linear.
  - **Incidents:** one every 3–4 min (6–8 min in free play), 90 s to respond. Breach: station locked 2 min, rep −5. Vulnerability: extra elite wave, rep −5. Naysayer: −1 rep per 5 s for 60 s. A grade of A or S gives rep +3.
  - **Key hires:** Security Engineer $3,000 (a breach clears itself after 30 s), QA Manager $3,000 (half an elite wave; triage shorter), PR Lead $3,500 (half drain; 3 posts instead of 5).
  - **Conference:** 10-minute cooldown; S +20, A +12, B +6, C +0.
  - **Bullet hell:** 3 lives, graze, focus, 60–90 s battles. Losing all lives fails the deploy. Shield absorbs one hit per wave; Rollback adds an extra life; Homing makes the ship's shots seek.
  - **Goal:** $40,000 counted as Act 3 payouts after the reputation multiplier.
- **Campus (spec §5 plus the owner update of 2026-10-31):** enclosed, 2 floors, a ceiling on each floor, the existing front wall, door and windows on the ground floor, windows upstairs, and the startup name over the entrance. The ground floor keeps the Act 2 work zone and the decorate zone at the same positions.

## Review Focus

1. **Leaving mid-transition.** A player who leaves during the Act 2 ending or the Act 3 opening resumes the right scene. They are never stuck in Act 2 with the goal reached, or in Act 3 without the campus. *Pinned: Task 1 `NextBeat` tests.*
2. **Incidents pile on a busy player.** An incident must never start during a battle, minigame, conference or cutscene; it waits. Two incidents must never run at once. *Pinned: Task 4 `incidents wait while busy`, `one incident at a time`.*
3. **A station lock outliving the incident.** A locked station must unlock after exactly 2 minutes, even if the player leaves and rejoins (locks aren't saved), and employees must skip it while locked. *Pinned: Task 4 `breach lock expires`.*
4. **Reputation out of range.** Repeated drains and boosts must clamp to 0–100, and the multiplier must never go below x0.8 or above x1.5. *Pinned: Task 2 `reputation clamps`.*
5. **Bullet-hell dodging by teleport or desync.** 2D ship moves are clamped to max speed, and hits are judged against the ship's position at the bullet's time, with a latency tolerance. *Pinned: Task 9 `ship moves are clamped`, `a dodge is judged at the bullet's time`.*

---

### Task 1: Story beats and save fields for Act 3

**Files:**
- Modify: `src/ReplicatedStorage/Shared/Story.luau`, `src/ReplicatedStorage/Shared/SaveSchema.luau`
- Test: `tests/Story.spec.luau`, `tests/SaveSchema.spec.luau`

**Interfaces:**
- Produces:
  - `CutsceneId = "Act1Intro" | "Act1End" | "Act2Intro" | "Act2End" | "Act3Intro" | "Finale"`
  - `Story.NextBeat` additions:
    - Act 2: `Act2Intro` until `Flags.Act2IntroSeen`; then `Act2End` once `Flags.Act2Complete` is set and `Flags.Act2EndSeen` is not.
    - Act 3: `Act3Intro` until `Flags.Act3IntroSeen`; then `Finale` once `Flags.GameComplete` is set and `Flags.FinaleSeen` is not.
  - `Story.Act3Start(startReputation: number): { Act: number, ActDeploys: number, Reputation: number, Act3Earned: number }` → `{ Act = 3, ActDeploys = 0, Reputation = startReputation, Act3Earned = 0 }`
  - `MilestoneDef` gains `Act: number` and an optional `Flag: string?`. New kinds:
    - `"Flag"`: reached when `state.Flags[def.Flag]` is set.
    - `"Earned"`: reached when `state.Act3Earned / state.Act3Goal >= At`.
  - `MilestoneState` gains `Act3Earned: number` and `Act3Goal: number`.
  - `NewMilestones` only considers defs whose `Act == state.Act`. The existing Act 2 defs in `GameConfig.ACT2.Milestones` get `Act = 2`.
  - `PlayerSave` gains:
    - `Reputation: number` (default 50, clamped 0–100)
    - `Act3Earned: number` (default 0, finite, ≥ 0)
    - `ConferenceReadyAt: number` (default 0, finite)

- [ ] **Step 1: Write the failing tests:**
  - `act 2 ending follows the goal`: `NextBeat(state(2, true, true, { Act2IntroSeen = true, Act2Complete = true }))` returns `"Act2End"`; with `Act2EndSeen` added, `nil`.
  - `act 3 opening then finale`: Act 3 with no flags returns `"Act3Intro"`; with `Act3IntroSeen` and `GameComplete`, `"Finale"`; with `FinaleSeen` added, `nil`.
  - `old saves past the act 2 card get the new ending`: Act 2 with `Act2IntroSeen` and `Act2Complete` (no `Act2EndSeen`) returns `"Act2End"`.
  - `act 3 start`: `Act3Start(50)` deep-equals `{ Act = 3, ActDeploys = 0, Reputation = 50, Act3Earned = 0 }`.
  - `milestones only fire in their act`: an Act 2 `ActDeploys` def doesn't fire in Act 3 at `ActDeploys = 9`. An Act 3 `Flag` def fires once its flag is set; an `Earned` def at 0.5 fires at `Act3Earned = 20000, Act3Goal = 40000`.
  - SaveSchema `act 3 fields default and clamp`: a missing `Reputation` becomes 50; 150 becomes 100; −5 becomes 0; NaN becomes 50. A negative `Act3Earned` becomes 0.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement. Add `Act = 2` to each Act 2 milestone in GameConfig.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: act 3 story beats, milestone acts and save fields`.

### Task 2: Reputation, Act 3 clients and payouts

**Files:**
- Create: `src/ReplicatedStorage/Shared/Reputation.luau`
- Modify: `src/ReplicatedStorage/Shared/GameConfig.luau`, `src/ServerScriptService/Services/AssemblyService.luau`
- Test: `tests/Reputation.spec.luau`, `tests/Economy.spec.luau`

**Interfaces:**
- Produces:
  - `GameConfig.ACT3 = { Goal = 40000, StartReputation = 50, MinMultiplier = 0.8, MaxMultiplier = 1.5, Milestones = { … } }`. Milestones, all `Act = 3`:
    - `FirstIncident`: `Flag = "IncidentHandled"`, "FIRST INCIDENT HANDLED", "The hackers will be back. You'll be ready."
    - `FirstConference`: `Flag = "ConferenceGiven"`, "FIRST KEYNOTE", "The crowd went wild. Reputation up."
    - `FirstKeyHire`: Kind `"Hires"`, `At = 1`, counting key hires only, "KEY HIRE", "A specialist joins the team."
    - `Halfway`: Kind `"Earned"`, `At = 0.5`, "HALFWAY THERE", "$20,000 down. Keep shipping."
  - `Reputation.Multiplier(rep: number, minM: number, maxM: number): number`: linear, clamped.
  - `Reputation.Apply(rep: number, delta: number): number`: clamped to 0–100.
  - **New recipes and clients:**
    - Recipes: `Platform = { FrontendUnits = 2, BackendEndpoints = 3, DatabaseTables = 2, PromptTokens = 1 }` and `Dashboard = { FrontendUnits = 3, BackendEndpoints = 2, DatabaseTables = 1, PromptTokens = 1 }`.
    - `GlobalPayments`, "Global Payments Platform", Platform, x110, unlock 0, Act 3.
    - `SmartCity`, "Smart City Dashboard", Dashboard, x130, unlock 2, Act 3.
    - `StreamingRelaunch`, "Streaming Service Relaunch", Platform, x160, unlock 4, Act 3.
    - Each client gets a `Boss` field: `"Hacker"` for GlobalPayments, `"Naysayer"` for SmartCity, `"Swarm"` for StreamingRelaunch. Task 9 uses it.
  - `AssemblyService.SettleDeploy`: in Act 3, payout = `floor(basePayout × Reputation.Multiplier(save.Reputation, …))`, then `save.Act3Earned += payout`. Acts 1–2 are unchanged.

- [ ] **Step 1: Write the failing tests:**
  - `reputation multiplier`: 0 gives 0.8, 100 gives 1.5, 50 gives 1.15, and −10 and 130 clamp to 0.8 and 1.5.
  - `reputation clamps`: `Apply(98, 20)` gives 100; `Apply(3, -10)` gives 0.
  - Economy `act 3 clients unlock by act deploys`: `AvailableClients(CLIENTS, 3, 0)` contains only GlobalPayments; at 4 deploys, all three Act 3 clients and none from earlier acts.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement, including the Act 3 branch in `SettleDeploy`.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: reputation multiplier, act 3 clients and act 3 earnings`.

### Task 3: Act 3 cutscene scripts (pure)

**Files:**
- Modify: `src/ReplicatedStorage/Shared/Cutscenes.luau`, `src/ReplicatedStorage/Shared/StoryText.luau`
- Test: `tests/Cutscenes.spec.luau`

**Interfaces:**
- Produces:
  - `Cutscenes.CAMPUS_MARKERS = { CamLobbyWide, CamLobbyName, CamAlarm, CamFinale, PlayerEntrance, PlayerLobby, BrotherEntrance, BrotherLobby }`.
  - `Act2End` uses `OFFICE_MARKERS` plus a new office marker `CamPullBack`, added to `OFFICE_MARKERS`.
  - New step kinds:
    - `Prop` actions `NewsTicker`, which shows a scrolling headline on the deploy screen, and `Alarm`, a red sweep plus a siren.
    - `Credits { Lines: { string } }`, a rolling credits card.
  - `StoryText` gains:
    - `ACT2_END_TICKER = "BREAKING: {name} closes record funding round"`
    - `ACT3_INTRO_TEXT = "One year later…"`
    - `BROTHER_TEXT_ACT3 = "saw you on the news. don't let it go to your head."`
    - `FINALE` with the 3 brother lines from spec §4, verbatim.
    - Titles `Act2Done = "ACT 2 COMPLETE"` and `Act3 = "ACT 3: BIG TECH"`.
  - Copy fields: `Act3Goal` (number), `StartupName` (string), `PlayerName` (string).
  - Scripts:
    - **Act2End:** phone-buzz spam, the NewsTicker prop, a shot to the deploy screen, a pull-back from `CamDesks` to `CamPullBack`, then Title `Act2Done`, then Fade Black.
    - **Act3Intro:** Fade Black, CenterText `ACT3_INTRO_TEXT`, Actor Player at `PlayerEntrance`, Fade Clear, the walk to `PlayerLobby` (about 8 studs/s), `CamLobbyName`, PhoneText with the brother's line, Prop `Alarm` with Shot `CamAlarm` and a shake, then Title `Act3` with the sub `"Earn $40,000"`.
    - **Finale:** the brother walks `BrotherEntrance` → `BrotherLobby`, then the 3 FINALE lines with `Focus = "Brother"` and `Fx` set to Push, Shout, Push. Then Title "THE END", then Credits with `"Vibecoder Startup Tycoon"`, `"Founded by {PlayerName}"`, `"{StartupName}"` and `"Thanks for playing"`, then Fade Clear.
- `Cutscenes.Validate` accepts a trailing Credits/Fade after the Title.

- [ ] **Step 1: Write the failing tests:**
  - `act 3 scenes validate against their layouts`: Act2End against `OFFICE_MARKERS`; Act3Intro and Finale against `CAMPUS_MARKERS`.
  - `finale lines are exact and focused`: all three FINALE texts are present and every brother `Line` has `Focus = "Brother"`.
  - `credits name the player and startup`: copy `{ PlayerName = "Ada", StartupName = "Night Shift Labs" }` produces Credits lines containing `"Founded by Ada"` and `"Night Shift Labs"`.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: act 2 ending, act 3 opening and finale scripts`.

### Task 4: Incident rules (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/Incidents.luau`
- Modify: `src/ReplicatedStorage/Shared/GameConfig.luau`
- Test: `tests/Incidents.spec.luau`

**Interfaces:**
- Produces:
  - `GameConfig.INCIDENTS = { MinGap = 180, MaxGap = 240, FreePlayMinGap = 360, FreePlayMaxGap = 480, RespondSeconds = 90, LockSeconds = 120, IgnorePenalty = 5, GoodBonus = 3, DrainEvery = 5, DrainSeconds = 60, AutoClearSeconds = 30 }`
  - `GameConfig.KEY_HIRES`:
    - `SecurityEngineer = { Name = "Security Engineer", Price = 3000, Counters = "Breach" }`
    - `QAManager = { Name = "QA Manager", Price = 3000, Counters = "Vulnerability" }`
    - `PRLead = { Name = "PR Lead", Price = 3500, Counters = "Naysayer" }`
  - `export type Kind = "Breach" | "Vulnerability" | "Naysayer"`
  - `export type Incident = { Kind: Kind, StartedAt: number, Deadline: number, LockedStation: string? }`
  - `export type State = { Active: Incident?, NextAt: number, Locks: { [string]: number }, DrainUntil: number, EliteWaves: number }`. `Locks` maps a station to its unlock time. `EliteWaves` counts pending half-waves: 2 is one full wave.
  - `Incidents.New(now, rng: () -> number, freePlay: boolean): State`
  - `Incidents.Tick(s: State, now, busy: boolean, rng, freePlay, keyHires: { [string]: boolean }): { Event }`. Events:
    - `{ Type = "Start", Incident }`, only when not busy, nothing is active and `now >= NextAt`. The kind is uniform by `rng`; a Breach picks the station `LockedStation` by `rng` from `GameConfig.COMPONENTS` order, passed in as a parameter.
    - `{ Type = "AutoCleared" }`: the Security Engineer clears a breach at `StartedAt + AutoClearSeconds`, with no penalty.
    - `{ Type = "Ignored", Kind, RepDelta }`: at the deadline, apply the consequence.
      - Breach: lock the station until `now + LockSeconds`, rep −5.
      - Vulnerability: add 2 to `EliteWaves` (1 with the QA Manager), rep −5.
      - Naysayer: `DrainUntil = now + DrainSeconds`, no immediate delta.
    - `{ Type = "Drain", RepDelta = -1 }`: every `DrainEvery` s while `now < DrainUntil`, or every `2 × DrainEvery` with the PR Lead.

    After an incident ends, `NextAt = now + gap`.
  - `Incidents.Resolve(s, now, grade: string): number`: clears the active incident and returns the rep delta, `GoodBonus` for "S" or "A", else 0. A Naysayer resolved early stops the drain.
  - `Incidents.IsLocked(s, station, now): boolean`
  - `Incidents.TakeEliteWave(s): boolean`: consumes the pending waves for the next battle and returns whether there are any. The battle reads `EliteWaves` before calling it; 1 means a half wave.

- [ ] **Step 1: Write the failing tests:**
  - `first incident waits for the gap`: with `New(0, …)`, nothing starts before `NextAt`, which falls in 180–240.
  - `incidents wait while busy`: `Tick` with `busy = true` past `NextAt` emits no Start; the same tick with `busy = false` emits a Start.
  - `one incident at a time`: while one is active, a later tick past `NextAt` emits no second Start.
  - `ignored breach locks a station then expires`: at the deadline, `IsLocked(station, deadline + 1)` is true and `IsLocked(station, deadline + 121)` is false. RepDelta is −5.
  - `security engineer auto-clears breaches`: with `SecurityEngineer`, AutoCleared fires at `StartedAt + 30` and no Ignored follows.
  - `naysayer drain is halved by the PR lead`: an ignored Naysayer emits 12 Drain events over 60 s without the PR Lead and 6 with it.
  - `vulnerability adds an elite wave, halved by QA`: EliteWaves goes 0 → 2, or 0 → 1 with `QAManager`.
  - `good handling earns reputation`: `Resolve(…, "A")` returns 3; `"C"` returns 0.
  - `free play spaces incidents out`: gaps fall in 360–480 when `freePlay` is set.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: incident scheduling, consequences and key-hire counters`.

### Task 5: Incident minigames (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/Firewall.luau`, `Triage.luau`, `ClapBack.luau`
- Modify: `src/ReplicatedStorage/Shared/StoryText.luau` (clap-back posts and replies)
- Test: `tests/IncidentGames.spec.luau`

**Interfaces:**
- Produces, each module with `New(rng, options) → round data the client renders`, `Judge(round, inputs) → { Correct: number, Total: number }` and `Grade(correct, total) → "S"|"A"|"B"|"C"`. Grade thresholds match the existing station games: S ≥ 0.95, A ≥ 0.8, B ≥ 0.6, else C. Check `Economy.PerformanceGrade` for reuse.
  - **Firewall:**
    - 20 packets about 1 s apart, each `{ Id, Red: boolean, Lane: 1..3, ArriveAt }`.
    - Input is the list of tapped ids. A tapped red packet counts correct, an untapped green counts correct, and anything else is wrong.
    - The server judges taps against `ArriveAt`: a tap after `ArriveAt + 0.3` counts as missed.
  - **Triage:**
    - Normally 10 reports, 6 with the QA Manager (`options.Short`).
    - Each is `{ Id, Text, Answer: "Critical"|"Minor"|"NotABug" }`. Texts come from a 15-entry bank in `StoryText.TRIAGE_REPORTS` with fixed answers.
    - Input is a `{ [id]: answer }` map.
  - **ClapBack:**
    - Normally 5 posts, 3 with the PR Lead (`options.Short`). Each post has 3 replies, and exactly 1 is the "best".
    - The bank `StoryText.CLAPBACK_POSTS` has 10 entries `{ Post, Replies = {a, b, c}, Best = index }`. The copy is campy, generic and English.
    - Input is a `{ [postIndex]: replyIndex }` map. `New` shuffles reply order and keeps `Best` consistent.

- [ ] **Step 1: Write the failing tests:**
  - `firewall perfect play grades S`.
  - `firewall late tap is missed`.
  - `triage short round for QA`, with 6 reports.
  - `clap back shuffle keeps the best reply`: after `New`, the reply at the new `Best` index equals the bank's best text.
  - `clap back short for PR`, with 3 posts.
  - `grades follow thresholds`: 19/20 gives S, 16/20 A, 12/20 B, 5/20 C.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: firewall, triage and clap-back incident minigames`.

### Task 6: The campus (two floors)

**Files:**
- Create: `src/ServerScriptService/World/CampusLayout.luau`
- Modify:
  - `src/ServerScriptService/World/OfficeLayout.luau`: export its builder pieces.
  - `src/ServerScriptService/World/WorldBuilder.luau`: `BuildContents` routes acts ≥ 3 to the campus and toggles the shell ceiling.
  - `src/ServerScriptService/Services/PlotService.luau`: the elevator.

**Interfaces:**
- Consumes: the shell (from the enclosed-plot change already on main) has `Ceiling`-tagged parts at y = 16 and the front wall, door and windows on the ground floor; `Props` helpers; `Cutscenes.CAMPUS_MARKERS` from Task 3.
- Produces:
  - `OfficeLayout.BuildWorkFloor(contents, origin, half)`: stations, desks, poster sign and decor-zone outline, the same as Act 2's. The reception desk and plants are decor (`GameConfig.DECOR_DEFAULTS`), and the campus ground floor keeps the full-floor `DECOR_ZONE` and its `Blocked` cells. `OfficeLayout.Build` = `BuildWorkFloor` + meeting room + office markers. Act 2 is unchanged.
  - `WorldBuilder.BuildContents(unit, act)`: for act ≥ 3, sets the shell's `Ceiling`-tagged parts to Transparency 1 and CanCollide false, and restores them for acts 1–2. The campus provides its own upper floor slab and roof.
  - **`CampusLayout.Build(contents, origin, half)`:**
    - **Ground floor:**
      - `BuildWorkFloor`.
      - A **conference stage** in the back-right corner, in the old meeting-room footprint: a podium part tagged `ConferenceStage` with prompt "Give keynote", about 12 simple block audience figures, and stage spotlights registered as `NightLight`. The `DeployTerminal` wall screen sits on the stage room wall, in the same spot as Act 2's.
      - A lobby along the front: a giant name panel whose label is named `SignText`, so `SetSignText` fills it.
    - **Upper floor:**
      - Floor slab at y = 16 with a stairwell opening in the front-left.
      - Stairs from the ground floor.
      - Elevator pads tagged `Elevator` on both floors, with attribute `TargetY`.
      - Upper walls from y 16 to 32 with windows on the side and front walls, using the same opening style as the shell. Roof at y = 32 tagged `Ceiling`, with ceiling lights.
      - Three rooms:
        - **Security desk:** tag `IncidentDesk`, `Kind = "Breach"`.
        - **QA lab:** tag `IncidentDesk`, `Kind = "Vulnerability"`.
        - **Press room:** tag `IncidentDesk`, `Kind = "Naysayer"`.

        Each has a prompt "Respond", a red alarm light part tagged `IncidentLight` with the same `Kind` (off by default), and a key-hire `EmployeeDesk` with `Role` set to the KEY_HIRES id.
    - Every `CAMPUS_MARKERS` marker: `PlayerEntrance` in the corridor outside the door, facing in. The lobby markers face the name panel.
  - `PlotService`: an `Elevator` prompt pivots the owner's character to the other floor's pad. Server-side and own-unit only.

- [ ] **Step 1:** Split OfficeLayout's work floor out and verify Act 2 is unchanged: `tests/Cutscenes.spec.luau` still passes, and the office markers and names are untouched.
- [ ] **Step 2:** Implement `CampusLayout` and the `BuildContents` routing, then add the elevator prompt.
- [ ] **Step 3:** Verify (tests, analyze, build). The Cutscenes test validates `CAMPUS_MARKERS` against the names the layout builds; `grep` checks that each marker name appears in `CampusLayout.luau`.
- [ ] **Step 4:** Commit `feat: two-floor campus with stage, upstairs incident rooms and elevator`.

### Task 7: IncidentService and key hires (server)

**Files:**
- Create: `src/ServerScriptService/Services/IncidentService.luau`
- Modify:
  - `ShopService.luau`: KEY_HIRES are listed and sold only when `save.Act >= 3`; buying one triggers the milestone check.
  - `EmployeeService.luau`: also seats KEY_HIRES on campus `EmployeeDesk`s whose `Role` is a key-hire id; Workforce only uses component roles.
  - `MinigameService.luau` and `BurstService.luau`: refuse a locked station with the notice "Station locked by a breach — {s}s left".
  - `RemoteNames.luau`: adds `IncidentState`, `IncidentStart`, `IncidentAction` and `IncidentResult`.
  - `tests/Data.spec.luau`: remote count +4.

**Interfaces:**
- Consumes: Task 4 `Incidents`, Task 5 games, Task 2 `Reputation`, campus tags from Task 6.
- Produces:
  - **Incident loop:** a per-player `Incidents.State` for Act 3 players, ticking every 0.5 s. `busy` = Activity ≠ Idle, or a cutscene in progress. A cutscene counts as in progress while `Story.NextBeat` ≠ nil.
  - `IncidentState(payload)` to the client: `{ Kind, Deadline, LockedStation, Room }`, or `nil` when cleared. The server turns that room's `IncidentLight` on or off with an attribute `Active`; the client spins it.
  - The `IncidentDesk` prompt with a matching active incident starts that minigame:
    - Activity is set to `"Burst"` and `IncidentStart(kind, roundData)` goes to the client.
    - The client replies with `IncidentAction(inputs)`, once and validated.
    - The server calls `Judge`/`Grade`, then `Resolve`, applies reputation, and sends `IncidentResult(grade, repDelta, newRep)`.
    - It sets `StoryFlags.IncidentHandled` and runs the milestone check.
    - Activity returns to Idle.
  - `IncidentService.IsLocked(player, station): boolean` and `IncidentService.TakeEliteWave(player): number`, which returns 0, 1 or 2 half-waves for Task 10.
  - Ignored consequences and Drain events apply through `Reputation.Apply` and `StartupDataModule.Update`.

- [ ] **Step 1:** Implement the service, the shop and employee changes, and the station-lock refusals.
- [ ] **Step 2:** Verify (tests, analyze, build). Expected: clean, with the remote count updated.
- [ ] **Step 3:** Commit `feat: incident service, key hires and station locks`.

### Task 8: Incident and HUD client

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/Controllers/IncidentController.luau`
- Modify: `src/StarterPlayer/StarterPlayerScripts/Controllers/HudController.luau`

**Interfaces:**
- Consumes: the Task 7 remotes, `IncidentLight` `Active` attributes, and `ClientState` (Act, Reputation, Act3Earned, StoryFlags).
- Produces:
  - **Incident alert:** a red HUD banner with the kind's name, a countdown to `Deadline`, and an arrow pointing toward the room's `IncidentDesk`. It flips upward when the room is upstairs. It comes with an alarm sound: pick a licensed siren or alarm from the Creator Store, or reuse `BugGotThrough` at a low pitch if none is suitable. Record the choice in the report.
  - Spinning red `IncidentLight` parts in the player's own unit.
  - **The three minigame UIs, in Theme style with juice:**
    - **Firewall:** three lanes, with packets sliding toward a core. Tap or click red packets.
    - **Triage:** report cards with three buttons.
    - **Clap back:** a post with three reply buttons.

    Each sends one `IncidentAction` at the end and shows the `IncidentResult` grade with `Sfx` grade sounds and the rep change.
  - **HUD, Act 3:**
    - The goal row reads "GOAL ${Act3Earned} / $40,000", or "LIFETIME EARNINGS ${…}" once `GameComplete` is set.
    - A reputation row reads "REP {rep} · x{mult:%.2f}" next to valuation.
  - Works with mouse, touch and gamepad: buttons are selectable; Firewall lanes map to D-pad left, up and right.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Verify (tests, analyze, build). Expected: clean.
- [ ] **Step 3:** Commit `feat: incident alerts, incident minigame screens and act 3 HUD`.

### Task 9: Bullet hell core: PRNG, ship, bullets, hits, lives (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/BulletHell.luau`
- Modify: `src/ReplicatedStorage/Shared/GameConfig.luau`
- Test: `tests/BulletHell.spec.luau`

**Interfaces:**
- Produces:
  - **`GameConfig.BULLET_HELL`:**
    - `ShipSpeed = 1.6`, `ShipSlack = 0.12`, `ShipMinY = 0.35`, `ShipMaxY = 0.95`
    - `HitRadius = 0.012`, `GrazeRadius = 0.05`
    - `Lives = 3`, `InvulnSeconds = 1.5`, `LatencyGrace = 0.25`
    - `Duration = 80`, `WaveCount = 2`, `WaveSeconds = 20`, `BossSeconds = 40`
    - `BulletSpeed = 0.32`, `EliteWaveSeconds = 10`
  - `BulletHell.Rng(seed: number): () -> number`: a deterministic PRNG (for example xorshift32), with values in [0, 1). The same seed gives the same sequence on server and client.
  - `export type Bullet = { Id, FiredAt, X, Y, VX, VY, Curve: number }`. `Curve` is the angular velocity for spirals; position is analytic via `BulletHell.BulletPosition(b, t)`.
  - `BulletHell.New(start: number, seed: number, options: { Boss: "Hacker"|"Naysayer"|"Swarm", EliteHalfWaves: number, Loadout: { Shield: boolean, ExtraLife: boolean, Homing: boolean, FireInterval: number }, Wingmen: { string } }): Battle`:
    - Generates enemies and the bullet schedule from `Rng(seed)`. The same seed always gives the same `Bullets` list.
    - An elite wave of `EliteWaveSeconds × (EliteHalfWaves / 2)` is inserted before the boss.
  - `BulletHell.MoveShip(b, x, y, now)`: the Task 6 Act 2 approach in 2D. It clamps against every kept sample in a 2 s window plus one older anchor, with slack applied once per window. y is clamped to [ShipMinY, ShipMaxY]. It ignores NaN and out-of-order input and bounds the sample count.
  - `BulletHell.ShipAt(b, t): (number, number)`
  - `BulletHell.Tick(b, now)`. For each live bullet, it checks substeps of 1/30 s between the last tick and `now − LatencyGrace`, against `ShipAt` at each substep.
    - **Hit:** distance ≤ HitRadius while not invulnerable. If the shield is available this wave, it's consumed; otherwise lives −1 and `InvulnUntil = t + InvulnSeconds`.
    - **Graze:** distance ≤ GrazeRadius, counted once per bullet. It adds to `Grazes` and `Combo`.
    - Lives reaching 0 fails the battle. `ExtraLife` (Rollback) adds 1 to the starting lives.
  - `b.Status`: `"Running"`, `"Shipped"` (time up or boss down, with lives > 0) or `"Failed"`.

- [ ] **Step 1: Write the failing tests:**
  - `same seed, same bullets`: two `New` calls with seed 42 give equal bullet lists; seed 43 differs.
  - `ship moves are clamped`: a 10-message burst at the same time moves at most ShipSlack; y stays inside [0.35, 0.95].
  - `a dodge is judged at the bullet's time`: hold the ship on a bullet's path at its crossing time, then move away 0.1 s later. It's still a hit. Holding away at the crossing time is not a hit, even if the ship later passes the point.
  - `graze counts once`: a bullet passing at 0.03 gives `Grazes = 1` after several ticks.
  - `invulnerability after a hit`: a second bullet within 1.5 s doesn't cost a life.
  - `shield absorbs one hit per wave`: with `Shield = true`, the first hit costs no life and a second hit in the same wave does.
  - `losing all lives fails`: 3 hits (spaced past invulnerability) give `Failed`; with `ExtraLife`, it takes 4.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: bullet hell core with seeded bullets, 2d ship and lives`.

### Task 10: Bullet hell enemies, bosses, kills and score (pure)

**Files:**
- Modify: `src/ReplicatedStorage/Shared/BulletHell.luau`, `GameConfig.luau`
- Test: `tests/BulletHell.spec.luau`

**Interfaces:**
- Produces:
  - **Enemies:** deterministic paths, ids 1..n. Popcorn enemies fire aimed or straight bullets.
  - **Bosses**, with patterns generated into the bullet schedule:
    - **Hacker:** a rotating spiral of green streams, using `Curve`.
    - **Naysayer:** slow walls of bubbles with a gap at a random x.
    - **Swarm:** a big boss that splits into 3 smaller bosses at half HP. Children are pre-generated, dormant until the split, and spawned when it happens; the server sends them like Act 2 shards.
  - `BulletHell.Kill(b, enemyId, now, weapon)`: the same claim model and per-weapon budgets as Act 2's `BattleState.Kill`. The weapons Ship, Spread, Beam and Missile need their hire. The target must be live and on screen.
  - `BulletHell.Score(b): number` in [0, 2] = `clamp(0.6·accuracy + 0.4·min(grazes/40, 1) + 0.5·min(maxCombo/30, 1) + 0.5·livesLeft/maxLives, 0, 2)`, where accuracy = killed / total enemies.
  - `BulletHell.Result(b)` gives `{ Status, Score, Grazes, MaxCombo, LivesLeft }`.

- [ ] **Step 1: Write the failing tests:**
  - `boss pattern by client`: the Hacker produces bullets with nonzero `Curve`. The Naysayer produces wall rows where every row has a gap at least 0.12 wide.
  - `swarm splits at half health`: after enough kills on the boss, 3 child bosses become live.
  - `claims need the weapon and a live enemy`: an unhired weapon or an off-screen enemy is rejected.
  - `score formula`: a fixed fixture gives the expected number (compute it in the test).
  - `elite wave lengthens the fight`: `EliteHalfWaves = 2` adds `EliteWaveSeconds` of enemies before the boss's spawn time.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: bullet hell enemies, threat bosses, kills and scoring`.

### Task 11: Bullet hell on the server and screen

**Files:**
- Modify: `src/ServerScriptService/Services/BattleService.luau`, `src/ReplicatedStorage/Shared/RemoteNames.luau` (`BattleShip` accepts an optional `y`; no new remote)
- Create: `src/StarterPlayer/StarterPlayerScripts/Controllers/BulletHellController.luau`

**Interfaces:**
- Consumes: Tasks 9–10; `IncidentService.TakeEliteWave` from Task 7; the client's `Boss` field from Task 2; hires; the loadout from part grades, via the existing `BattleState.LoadoutFrom` mapping to Shield, ExtraLife, Homing and FireInterval.
- Produces:
  - **Act 3 route in `BattleService`:** `BattleStarted` sends `{ Mode = "BulletHell", Seed, Boss, Loadout, Wingmen, ServerStart }`. There's no bullet list, because the client regenerates it from the seed.
    - `BattleShip(x, y)` and `BattleSquash(id, weapon)` are validated, with the server clock as time.
    - `BattleUpdate` carries lives, grazes, combo, `InvulnUntil`, boss HP, spawned split children and status.
    - On the end, the payout is `Economy.Payout(units, valuation, BulletHell.Score(b), tier)`, then the reputation multiplier in `SettleDeploy` (Task 2). A Failed battle pays nothing and keeps the job.
    - Acts 1–2 are untouched.
  - **`BulletHellController` (client):** renders the field from `BulletHell.New(seed)` and `BulletPosition`.
    - **Bullets:** pooled frames, about 400 at most. Colors by boss: green streams, pink bubbles, red swarm shots. Bullets hide when the battle ends.
    - **Movement:** the ship moves in 2D with WASD, arrows, stick or touch drag, offset above the finger. Focus (Shift, ButtonL2 or an on-screen button) slows movement to 40% and shows the hitbox dot.
    - **Weapons:** wingmen fire as in Act 2.
    - **HUD:** a graze meter with a spark per graze, lives as hearts, and a boss HP bar.
    - **Juice:** screen shake and 0.08 s hit-stop on a hit, a boss music switch (`Music.Play("Boss")`), boss-down banner.
    - **Network:** sends `BattleShip(x, y)` at 10 Hz and kill claims as in Act 2.
    - **Cleanup:** everything is torn down on end.

- [ ] **Step 1:** Implement the server route and the client controller. Act 1 and 2 battles still go to `BattleController`.
- [ ] **Step 2:** Verify (tests, analyze, build). Expected: clean.
- [ ] **Step 3:** Commit `feat: act 3 bullet hell deploy battle on server and screen`.

### Task 12: Conferences

**Files:**
- Create: `src/ReplicatedStorage/Shared/Keynote.luau`, `src/ServerScriptService/Services/ConferenceService.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/ConferenceController.luau`
- Modify: `RemoteNames.luau` (`ConferenceStart`, `ConferenceAction`, `ConferenceResult`) and `tests/Data.spec.luau`
- Test: `tests/Keynote.spec.luau`

**Interfaces:**
- Produces:
  - **`Keynote.New(rng)`:**
    - 8 slogans drawn from `StoryText.KEYNOTE_SLOGANS`, about 12 short campy lines such as "SHIP FAST", "AI-NATIVE" and "WE'RE HIRING".
    - Each slogan gets a beat window `{ Text, OpenAt, CloseAt }` on a steady tempo: 2.5 s per slogan and a 1.6 s window.
  - **`Keynote.Judge(round, submissions: { [index]: { Text: string, At: number } })`:** a slogan is correct when the text matches, case-insensitive, and the time falls inside its window. The grade uses the shared thresholds.
  - **`ConferenceService`:**
    - The `ConferenceStage` prompt works when the player is Idle, in Act 3 and past `ConferenceReadyAt`. Otherwise the notice reads "Next conference in {m}:{ss}".
    - It sets Activity to Burst and sends `ConferenceStart(round)`.
    - On `ConferenceAction(submissions)`, it judges the round and applies reputation: S +20, A +12, B +6, C +0. It sets `ConferenceReadyAt = os.time() + 600` and `StoryFlags.ConferenceGiven`, runs the milestone check, and sends `ConferenceResult(grade, repDelta, newRep, multiplier)`.
  - **`ConferenceController`:**
    - A stage view: the camera faces the audience from behind the podium.
    - A slogan prompt with a beat ring that closes on the window and a typing box.
    - A crowd hype meter that rises with correct slogans and falls on misses. Audience figures bounce and stage lights pulse with hype.
    - A results card with the grade and the new multiplier.

- [ ] **Step 1: Write the failing tests:**
  - `keynote windows are steady`: windows are 2.5 s apart and 1.6 s wide.
  - `typing on time counts`: matching text inside the window is correct, any case.
  - `late or wrong text misses`.
  - `grade and reputation`: 8/8 gives S (+20) and 5/8 gives B (+6), via a pure `Keynote.RepFor(grade)`.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement the pure module, then the service and controller.
- [ ] **Step 4:** Run tests and verify (analyze, build). Expected: PASS and clean.
- [ ] **Step 5:** Commit `feat: conference keynotes boost reputation`.

### Task 13: Act 2 → Act 3 → finale story flow

**Files:**
- Modify:
  - `ProgressService.luau`
  - `StoryController.luau`: drops the `Act2Complete` card and adds the Finale replay.
  - `CutsceneController.luau`: the new `Prop` actions and the `Credits` step.
  - `PlotService.luau`: `RebuildUnit(player, 3)` and campus sign text.
  - `StartupNameService.luau`: the startup sign adds "Replay ending" once `GameComplete` is set.

**Interfaces:**
- Consumes: everything above.
- Produces:
  - **Act 2 goal:** on reaching it, set `Act2Complete` (existing) and send `Act2End`, which replaces the card. When `Act2End` is done:
    - set `Act2EndSeen`;
    - apply `Story.Act3Start(GameConfig.ACT3.StartReputation)`;
    - `RebuildUnit(player, 3)`;
    - send `Act3Intro`, with copy `Act3Goal = 40000` and `StartupName`.
  - **Act3Intro done:** set `Act3IntroSeen` and start the incident loop. The first incident comes 3–4 min later.
  - **Act 3 goal:** on a deploy with `Act3Earned >= Goal` and no `GameComplete`, set `GameComplete` and send `Finale`, with copy `PlayerName` = `player.DisplayName` and `StartupName`. When it's done, set `FinaleSeen` and switch incidents to the free-play rate.
  - **Replay ending:** the startup sign prompt, after `GameComplete`, offers "Replay ending". The client gets the `Finale` beat flagged `Replay = true`. Its `CutsceneDone` is ignored by `AcceptDone`, so no state changes.
  - **Cutscene props:**
    - `NewsTicker` scrolls the headline across the unit's `DeployTerminal` screen and restores it afterwards.
    - `Alarm` sweeps every `IncidentLight` in the unit red and plays the alarm sound.
    - `Credits` rolls the lines over black, letterboxed, and skips with the scene.
  - **Act 3 milestones** run after each Act 3 deploy, incident handled, conference and key hire.
  - **Old saves:** an Act 2 save with `Act2Complete` and no `Act2EndSeen` gets `Act2End` on join (Task 1 rule).

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Verify (tests, analyze, build). The `Story` tests from Task 1 cover the order.
- [ ] **Step 3:** Commit `feat: act 2 ending, act 3 opening, finale and free play`.

### Task 14: Verification and merge

- [ ] **Step 1:** Run all checks (tests, analyze, build). Grep `src` for `wait(`, `spawn(`, `delay(`, `pairs(` and service dot-indexing. Expected: clean.
- [ ] **Step 2:** Write the owner's playtest checklist into the final message:
  1. Act 2 goal, then the Act 2 ending, then the campus.
  2. The Act 3 opening with the alarm.
  3. The stairs, the elevator and the upstairs rooms.
  4. An incident of each kind, both handled and ignored, including a station lock.
  5. Each key hire's effect.
  6. A conference, then the cooldown.
  7. A bullet-hell deploy on PC, phone and gamepad, with focus, graze and boss.
  8. $40,000, then the finale and credits, then free play, then "Replay ending".
- [ ] **Step 3:** Merge into `main` and push.
