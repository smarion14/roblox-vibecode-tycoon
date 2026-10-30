# Act 2 (Move Out), Employees and Cutscenes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real in-engine cutscenes for the Act 1 opening, the Act 1 ending and the Act 2 opening; the Act 1 → Act 2 move into an office the player names; employees who appear as friends' avatars only in Act 2; and Act 2 clients, projects and its valuation goal.

**Architecture:**
- **Pure rules (Lune-tested) in `ReplicatedStorage/Shared`:**
  - `Story`: which cutscene comes next, act transition values, the act goal, startup-name pre-checks.
  - `Cutscenes`: cutscene scripts as plain data.
  - Economy and BattleState gain act-aware client unlocks and battle tuning.
- **Server:**
  - Unit contents become per-owner and per-act. The world builder is split into a shell plus Homelab and Office layouts. PlotService rebuilds a unit's contents and binds prompts dynamically.
  - ProgressService drives the story from `Story`.
  - New `EmployeeService` and a startup-name filter.
- **Client:** a `CutsceneController` plays cutscene data in the player's own unit, with letterbox bars, a dialogue box, title cards and Skip. Animations are generated `KeyframeSequence` files the owner publishes, with built-in fallbacks.

**Tech Stack:**
- Roblox and Luau `--!strict`, Rojo 7.7.1.
- Lune 0.11 for tests and the animation file generator (`@lune/roblox`).
- luau-lsp.
- Roblox `TextService` filtering and `Players` friends and avatar APIs.

**Spec:** `docs/superpowers/specs/2026-10-30-act2-office-and-cutscenes-design.md` (builds on `docs/superpowers/specs/2026-10-30-vibecoder-startup-tycoon-design.md`)

## Global Constraints

**Code style (from `CLAUDE.md`)**
- Every `.luau` file starts with `--!strict`.
- `game:GetService` goes at the top. Never dot-index services.
- Use the `task` library only. Never use `wait`, `spawn` or `delay`.
- Iterate with generalized iteration. Never use `pairs` or `ipairs`.
- Type every function and state table.
- Naming: `PascalCase` for modules and exports, `camelCase` for locals, `LOUD_SNAKE_CASE` for constants.

**Pure modules** in `ReplicatedStorage/Shared`
- They contain no `require` and no Roblox APIs. Config, clock and RNG come in as parameters. Tests live in `tests/*.spec.luau`.

**Server authority**
- The server decides every act change, flag, name and purchase.
- `CutsceneDone` is accepted only when it names the cutscene the server expects next.

**Text and setting**
- All text is English, in a generic setting. The brother is "your brother" (he/him).
- Brother lines are exact copy from the spec §5.2–5.3, with the §5.2 line as revised: *"A buddy of mine is subletting a tiny office downtown. First month's free. Take it. Get off my couch."*

**Startup name**
- 3–24 characters.
- Filtered with `TextService:FilterStringAsync` → `GetNonChatStringForBroadcastAsync` before it's stored or shown.
- If filtering fails or blanks the name, the player retries. The default sign text is "UNTITLED STARTUP".

**Cutscenes**
- Every cutscene is skippable, has letterbox bars, and plays only for its own player in their own unit. Each plays once per save.

**Units**
- Unowned units, and units whose owner is in Act 1, show the Homelab layout. Owners in Act 2 see the Office layout.
- Contents are rebuilt on assign, on act change and on leave (reverting to Homelab). Station, deploy, laptop, phone and sibling tags keep working after a rebuild.

**Employees**
- Act 2 only. Hires are hidden and rejected in Act 1, and existing hires carry over.
- Effect is unchanged: C-quality pre-builds via `Economy.ApplyHires`.
- Each employee looks like a friend's avatar, using a different friend per role when possible, with a fallback look otherwise.

**Animations**
- Every ID lives in `GameConfig.ANIMATIONS`, where `0` means "not published yet". Any `0` falls back to built-in walk, sit or idle.

**Audio**
- Only licensed Creator Store catalogs: Pro Sound Effects, APM, DistroKid official, Roblox.

## Review Focus

1. **Leaving mid-cutscene.** A player who leaves during the Act 1 ending or Act 2 opening rejoins and resumes the right cutscene. They're never stuck in Act 1 with rent paid, and never in Act 2 without the office. *Pinned: Task 1 `Story.NextBeat` tests.*
2. **Out-of-order or replayed CutsceneDone.** A client sending `CutsceneDone("Act2Intro")` while still in Act 1 must not advance the act. *Pinned: Task 1 `Story.AcceptDone` tests.*
3. **Bad names.** Empty, too long, all spaces or emoji-only names, and names that filtering blanks, must never reach the sign. *Pinned: Task 1 `Story.PrecheckName` tests and the Task 7 playtest.*
4. **A Roblox player with no friends,** or friends whose avatars fail to load, still gets employees with a look. *Pinned: Task 9 playtest.*
5. **Prompts after a rebuild.** Prompts on rebuilt contents must work, and prompts must not double-fire after several rebuilds. *Pinned: Task 4 playtest (rebuild three times, each prompt fires once).*

---

### Task 0: Branch and ServerStorage mapping

**Files:**
- Modify: `default.project.json`
- Create: `src/ServerStorage/Animations/.gitkeep`

- [ ] **Step 1:** Run `git checkout -b act2`. Add `"ServerStorage": { "$path": "src/ServerStorage" }` to the tree in `default.project.json`.
- [ ] **Step 2:** Verify that `rojo build -o game.rbxl` prints `Built project` and `lune run tests/run.luau` passes all tests.
- [ ] **Step 3:** Commit with `chore: map ServerStorage for animation assets`.

### Task 1: Story progression rules and save fields (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/Story.luau`
- Modify: `src/ReplicatedStorage/Shared/SaveSchema.luau`
- Test: `tests/Story.spec.luau`, `tests/SaveSchema.spec.luau`

**Interfaces:**
- Produces:
  - `export type CutsceneId = "Act1Intro" | "Act1End" | "Act2Intro"`
  - `export type StoryState = { Act: number, SeenIntro: boolean, RentPaid: boolean, Flags: { [string]: boolean } }`
  - `Story.NextBeat(state: StoryState): CutsceneId?`
    - `"Act1Intro"` when `Act == 1`, `not SeenIntro` and `not RentPaid`.
    - `"Act1End"` when `Act == 1` and `RentPaid`.
    - `"Act2Intro"` when `Act == 2` and `not Flags.Act2IntroSeen`.
    - Otherwise `nil`.
  - `Story.AcceptDone(state: StoryState, id: string): boolean`: true only when `id == Story.NextBeat(state)`.
  - `Story.Act2Start(valuation: number, step: number): { Act: number, ActDeploys: number, ActGoal: number }`: returns `{ Act = 2, ActDeploys = 0, ActGoal = valuation + step }`.
  - `Story.ActGoalReached(act: number, valuation: number, goal: number): boolean`: true when `act >= 2` and `valuation >= goal`.
  - `Story.PrecheckName(raw: string): (string?, string?)`. It trims and collapses spaces, then returns `(clean, nil)` or `(nil, reason)`. Reasons: `"Too short"` under 3 characters, `"Too long"` over 24, and `"Letters or numbers only"` when the name has no `%w` character.
- `SaveSchema.PlayerSave` gains:
  - `StartupName: string?`: only strings of 1–24 characters are kept.
  - `ActDeploys: number`: a whole number ≥ 0, default 0.
  - `ActGoal: number`: finite and ≥ 0, default 0.

  `Default` and `Sanitize` handle all three.

- [ ] **Step 1: Write the failing tests** in `tests/Story.spec.luau`:
  - `next beat for a fresh save`: Act 1, intro unseen, rent unpaid → `"Act1Intro"`.
  - `act 1 done but not moved (also an old save)`: Act 1, rent paid → `"Act1End"`, whether or not `SeenIntro` is set.
  - `act 2 without its opening seen (left mid-cutscene)`: Act 2 with an empty flags table → `"Act2Intro"`.
  - `nothing pending`: Act 2 with `Flags.Act2IntroSeen = true` → `nil`.
  - `accept done only in order`: with Act 1 and rent paid, `AcceptDone(state, "Act2Intro")` is false and `AcceptDone(state, "Act1End")` is true.
  - `act 2 start`: `Act2Start(1.6, 1.5)` → `ActGoal == 3.1`, `Act == 2`, `ActDeploys == 0`.
  - `goal reached`: `ActGoalReached(1, 9, 3)` is false, `ActGoalReached(2, 3.1, 3.1)` is true, `ActGoalReached(2, 3.0, 3.1)` is false.
  - `precheck names`:
    - `"  my   app "` → `"my app"`
    - `"ab"` → `nil, "Too short"`
    - a 25-character name → `"Too long"`
    - `"   "` → `"Too short"`
    - `"🚀🚀🚀"` → `"Letters or numbers only"`
- [ ] **Step 2: Add the failing SaveSchema tests** to `tests/SaveSchema.spec.luau`:
  - `act 2 fields default`: the default save has `StartupName == nil`, `ActDeploys == 0` and `ActGoal == 0`.
  - `act 2 fields sanitized`: `StartupName = 42` → `nil`; a 40-character name → `nil`; `ActDeploys = -3` → `0`; `ActGoal = 0/0` → `0`; `ActGoal = 3.1` is kept.
- [ ] **Step 3:** Run `lune run tests/run.luau`. Expected: the new tests FAIL.
- [ ] **Step 4:** Implement `Story.luau` and the SaveSchema fields.
- [ ] **Step 5:** Run the tests. Expected: all PASS.
- [ ] **Step 6:** Commit with `feat: story progression rules and act 2 save fields`.

### Task 2: Act 2 economy and battle tuning (pure and config)

**Files:**
- Modify: `src/ReplicatedStorage/Shared/GameConfig.luau`, `Economy.luau`, `BattleState.luau`, `RemoteNames.luau`, `StoryText.luau`
- Modify: `src/ServerScriptService/Services/AssemblyService.luau` (the `AvailableClients` call sites, plus `ActDeploys += 1` on ship)
- Modify: `src/ServerScriptService/Services/BattleService.luau` (build the battle with `BattleState.RulesForAct(GameConfig.BATTLE_RULES, GameConfig.ACT_BATTLE[save.Act])`)
- Test: `tests/Economy.spec.luau`, `tests/BattleState.spec.luau`, `tests/Data.spec.luau`

**Interfaces:**
- `ClientDef` gains `Act: number` in both `GameConfig` and `Economy`.
  - Existing clients get `Act = 1`.
  - New Act 2 clients get `Act = 2`, with `UnlockAtDeploys` counted on `ActDeploys`:
    - `{ Id = "PocketFit", Name = "PocketFit Fitness App", Project = "MobileApp", TierMultiplier = 55, UnlockAtDeploys = 0 }`
    - `{ Id = "PixelForge", Name = "PixelForge Indie Studio", Project = "Game", TierMultiplier = 70, UnlockAtDeploys = 2 }`
    - `{ Id = "BrewCrew", Name = "BrewCrew Coffee Rewards", Project = "MobileApp", TierMultiplier = 85, UnlockAtDeploys = 4 }`
- `GameConfig.RECIPES` gains:
  - `MobileApp = { FrontendUnits = 2, BackendEndpoints = 2, DatabaseTables = 1, PromptTokens = 1 }`
  - `Game = { FrontendUnits = 1, BackendEndpoints = 1, DatabaseTables = 1, PromptTokens = 3 }`
- `GameConfig.ACT2 = { ValuationStep = 1.5 }`.
- `GameConfig.ACT_BATTLE = { [2] = { ExtraBugsPerWave = 2, DiveTimeScale = 0.85, BossHp = 20 } }`.
- `Economy.AvailableClients(clients: { ClientDef }, act: number, actDeploys: number): { ClientDef }`. This **changes the signature**, so update both AssemblyService call sites to pass `save.Act, save.ActDeploys`.
- `BattleState.RulesForAct(base: BattleRules, overrides: { ExtraBugsPerWave: number, DiveTimeScale: number, BossHp: number }?): BattleRules`. It returns a copy with every wave's `Count` raised by `ExtraBugsPerWave`, every `DiveTime` multiplied by `DiveTimeScale`, `BossMinionDiveTime` also scaled, and `BossHp` replaced. With `nil` overrides it returns an unchanged copy.
- `RemoteNames` gains `CutsceneDone`, `SetStartupName` and `NameResult`, for 20 in total.
- `StoryText` gains:
  - `ACT1_END: { { Speaker: string, Text: string } }`
  - `ACT2_INTRO_TEXT = "Two weeks later…"`
  - `BROTHER_TEXT_ACT2 = "don't burn it down"`
  - `ACT_TITLES = { Act1 = "ACT 1: MAKE RENT", Act1Done = "ACT 1 COMPLETE", Act2 = "ACT 2: MOVE OUT" }`
- AssemblyService `SettleDeploy` also does `save.ActDeploys += 1`.

- [ ] **Step 1: Write the failing tests:**
  - Economy, `clients by act`: with `GameConfig.CLIENTS`, `#AvailableClients(clients, 1, 0) == 1`, `#AvailableClients(clients, 1, 4) == 3`, `#AvailableClients(clients, 2, 0) == 1` (PocketFit only) and `#AvailableClients(clients, 2, 4) == 3`. Update the old `clients unlock` test to the new signature.
  - BattleState, `act tuning`: `RulesForAct(RULES, GameConfig.ACT_BATTLE[2])` has `Waves[1].Count == RULES.Waves[1].Count + 2`, `Waves[1].DiveTime == RULES.Waves[1].DiveTime * 0.85` and `BossHp == 20`, and `RULES` is unchanged. `RulesForAct(RULES, nil).BossHp == RULES.BossHp`.
  - Data:
    - `remote names` expects 20.
    - `every client project has a recipe` covers the new projects.
    - `act 1 ending uses the exact brother lines`: `StoryText.ACT1_END` contains `{ Speaker = "Brother", Text = "...Okay. You can stay." }`, `"Don't make it weird."` and `"A buddy of mine is subletting a tiny office downtown. First month's free. Take it. Get off my couch."`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement the config, Economy, BattleState, RemoteNames, StoryText and AssemblyService changes.
- [ ] **Step 4:** Run the tests. Expected: PASS. `rojo build` succeeds, and `luau-lsp analyze` (the usual command) is clean.
- [ ] **Step 5:** Commit with `feat: act 2 clients, recipes, act battle tuning`.

### Task 3: Cutscene scripts as data (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/Cutscenes.luau`
- Test: `tests/Cutscenes.spec.luau`

**Interfaces:**
- Produces:
  - `export type Step` is a tagged table with field `Kind`, one of:
    - `"Fade"`: `{ To: "Black" | "Clear", Seconds: number }`
    - `"CenterText"`: `{ Text: string, Seconds: number }`
    - `"Shot"`: `{ From: string, To: string?, Seconds: number }`. Marker names (Task 5) are camera positions.
    - `"Actor"`: `{ Actor: "Player" | "Brother", Marker: string, Walk: boolean?, Seconds: number? }`
    - `"Animate"`: `{ Actor: "Player" | "Brother", Animation: string, Wait: boolean? }`. `Animation` is a key into `GameConfig.ANIMATIONS`.
    - `"Prop"`: `{ Prop: "LaptopLid" | "CashStack" | "PhoneBuzz", Action: string }`
    - `"Line"`: `{ Speaker: string, Text: string }`, waiting for click or Space.
    - `"PhoneText"`: `{ From: string, Text: string }`
    - `"NameStartup"`: `{}`, which waits for a server-accepted name.
    - `"Title"`: `{ Text: string, Sub: string? }`
  - `Cutscenes.Get(id: string, copy: { [string]: any }): { Step }`. `copy` passes text values in, such as `RentGoal`, `ActGoal`, `Act1End` and titles, so the module stays pure.
  - `Cutscenes.Validate(steps: { Step }, markers: { [string]: boolean }): (boolean, string?)`. It checks that every `Shot`/`Actor` marker exists, every `Seconds > 0`, and that the last step is a `Title`.
  - `Cutscenes.HOMELAB_MARKERS` and `Cutscenes.OFFICE_MARKERS`: the sets of marker names each layout must provide (Task 5).
- Script content follows spec §5 beat for beat:
  - **`Act1Intro`:** wide shot, push in, couch close-up, brother walks in, laptop lid closes, two lines, close-up, then `Title(ACT 1: MAKE RENT, "Rent: $" .. RentGoal)`.
  - **`Act1End`:** handover and count, two lines, the door line, then `Title(ACT 1 COMPLETE)`, ending on `Fade To Black`. The last two steps are `Title` then `Fade`, so Validate allows a trailing `Fade` after a `Title`.
  - **`Act2Intro`:** starts black, then `CenterText "Two weeks later…"`, fade in, dolly through the office door, the player walks in, `PhoneText Brother "don't burn it down"`, `NameStartup`, then `Title(ACT 2: MOVE OUT, "Reach valuation x" .. ActGoal)`.

- [ ] **Step 1: Write the failing tests:**
  - `each cutscene validates against its layout`: Act1Intro and Act1End against `HOMELAB_MARKERS`, Act2Intro against `OFFICE_MARKERS`.
  - `exact brother lines appear`: Act1Intro contains both §5.1 lines and Act1End contains the three §5.2 lines.
  - `act 2 intro asks for a name before its title`: the index of `NameStartup` is less than the index of the final `Title`.
  - `validate rejects a missing marker`: a `Shot` from `"Nowhere"` fails with a message naming it.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `Cutscenes.luau`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit with `feat: cutscene scripts as validated data`.

### Task 4: Per-owner unit contents and dynamic prompt binding

**Files:**
- Create: `src/ServerScriptService/World/Props.luau` (moved helpers: `part`, `screenLabel`, `interactable`, `nightLight`, `glow`, `cylinder`, `led`, `monitor`, `desk`, `chair`, `plant`, `buildSibling`, plus the color constants)
- Create: `src/ServerScriptService/World/HomelabLayout.luau` (the current Act 1 contents, moved unchanged)
- Modify: `src/ServerScriptService/World/WorldBuilder.luau` (shell only: floor, walls, trims, sign, lamps and lighting, plus `BuildContents`)
- Modify: `src/ServerScriptService/Services/PlotService.luau`

**Interfaces:**
- **`WorldBuilder.BuildFloor(): { Model }`.** Each unit model gets the attribute `OriginCFrame` (a `CFrame`) and a child folder `Contents`. The shell (floor, walls, trims and `UnitSign`) stays outside `Contents`. `UnitSign` gets a `SurfaceGui` text label.
- **`WorldBuilder.BuildContents(unit: Model, act: number)`.** It destroys `unit.Contents` children, then builds `HomelabLayout.Build(contents, origin, half)` (act 1) or `OfficeLayout.Build(...)` (act ≥ 2, Task 5). It must create every marker named in `Cutscenes.HOMELAB_MARKERS` or `Cutscenes.OFFICE_MARKERS` as an invisible, non-colliding part named `Marker_<Name>`, tagged `CutsceneMarker`, with the attribute `Marker = <Name>`.
- **`WorldBuilder.SetSignText(unit: Model, text: string)`.**
- **`PlotService.OnPromptTriggered(tag, handler)`.** It now binds every current and future tagged prompt using `CollectionService:GetInstanceAddedSignal(tag)`. Each prompt is connected once per instance; destroyed instances drop their connection automatically.
- **`PlotService.RebuildUnit(player: Player, act: number)`.**
- **`PlotService.GetUnitModel(player: Player): Model?`.**
- **On assign,** contents are built for the owner's saved act, using `StartupDataModule.OnPlayerLoaded`. The sign text is the saved `StartupName`, or `"UNTITLED STARTUP"` in Act 2, or `""` in Act 1. **On leave,** the unit goes back to `BuildContents(unit, 1)` and `SetSignText(unit, "")`.
- **`player:SetAttribute("Unit", index)`** is set on assign and cleared on leave. The client uses it to find its own unit.

- [ ] **Step 1:** Move the helpers and Homelab builders out with no behaviour change. Then add the shell and `Contents` split, the markers in the Homelab layout and the dynamic binding.
- [ ] **Step 2:** Verify that `rojo build` succeeds, `luau-lsp analyze` is clean and all Lune tests pass.
- [ ] **Step 3: Playtest:**
  - The Act 1 homelab looks the same as before, and every station, the deploy terminal, laptop, phone and sibling still work.
  - From the server command bar, call `PlotService.RebuildUnit(player, 1)` three times. Each prompt still fires **exactly once** per trigger (Review Focus 5).
- [ ] **Step 4:** Commit with `refactor: per-owner unit contents and dynamic prompt binding`.

### Task 5: Office layout (Act 2)

**Files:**
- Create: `src/ServerScriptService/World/OfficeLayout.luau`

**Interfaces:**
- **`OfficeLayout.Build(contents: Folder, origin: CFrame, half: number)`.** It provides:
  - the four stations (same `Station` tag, `Component` attribute and `StationSeat` link on Frontend), as upgraded builds per spec §6
  - `DeployTerminal` as a meeting-room wall screen
  - `ShopComputer` as a desk computer
  - `JobPhone`
  - four `EmployeeDesk` parts, tagged `EmployeeDesk`, with attribute `Role = <component>`, each with a chair `Seat` child named `EmployeeSeat` and a "NOW HIRING" sticky-note `SurfaceGui` named `HiringNote`
  - a `StartupSign` prompt part (tag `StartupSign`, action "Rename") inside the office by the door
  - a coffee machine, a logo wall, plants and night lights
  - every `Cutscenes.OFFICE_MARKERS` marker
  - `UnitSpawn`
- No `Sibling` in the office.

- [ ] **Step 1:** Implement it, reusing `Props` helpers.
- [ ] **Step 2:** Verify that build and analyze are clean and Lune passes.
- [ ] **Step 3: Playtest** with `PlotService.RebuildUnit(player, 2)` from the command bar:
  - The office appears.
  - Every station, the deploy terminal, shop and phone work.
  - There's no floating or clipping geometry from the spawn point.
- [ ] **Step 4:** Commit with `feat: act 2 office layout`.

### Task 6: Cutscene player (client) and story wiring (server)

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/Controllers/CutsceneController.luau`
- Create: `src/StarterPlayer/StarterPlayerScripts/UI/Actors.luau`. It handles actor copies and animation with fallback, so Task 9 can reuse it.
- Modify: `src/ServerScriptService/Services/ProgressService.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/StoryController.luau`, `IntroController.luau` (delete it), `GameConfig.luau` (`ANIMATIONS`)
- Modify: `src/ServerScriptService/World/WorldBuilder.luau` (at boot, create `ReplicatedStorage.Shared.BrotherTemplate`, a brother rig from a blank `HumanoidDescription`)
- Modify: `src/StarterPlayer/StarterPlayerScripts/UI/Music.luau` (add a `Cutscene` track: a licensed APM or DistroKid official track found through the Creator Store, played under every cutscene and stopped on finish or skip)

**Interfaces:**
- **`GameConfig.ANIMATIONS`** = `{ LaptopClose = 0, HandOverCash = 0, CountCash = 0, Talk = 0, SitCouch = 0, DeskType = 0 }`. `0` means not published yet.
- **`Actors.Spawn(kind: "Player" | "Brother", at: CFrame): Model`**:
  - Player: a client-local copy of the player's character, made by setting `Archivable = true` temporarily and cloning.
  - Brother: a clone of the unit's `SiblingModel`. In Act 2 there's no sibling, so build one from a blank `HumanoidDescription` through a server-provided template in `ReplicatedStorage/Shared` (`BrotherTemplate`, created by WorldBuilder at boot).
  - Both copies are anchored except the root.
- **`Actors.Play(model: Model, animation: string): AnimationTrack?`.** It uses `GameConfig.ANIMATIONS[animation]` when it isn't 0. Otherwise it falls back to built-in IDs from a table in `Actors` (Roblox default walk, sit and idle), or `nil` when there's no fallback.
- **`Actors.WalkTo(model: Model, to: CFrame, seconds: number)`.**
- **CutsceneController** listens for `StoryBeat("Cutscene", { Id, Copy })`. It plays `Cutscenes.Get(Id, Copy)` against the markers in its own unit (from the `Unit` attribute and `CutsceneMarker` tags):
  - **During playback:** letterbox bars (two black frames tweening in), the camera set to `Scriptable`, the player's controls disabled (`PlayerModule:GetControls():Disable()`), and the HUD hidden.
  - **Dialogue box:** shows the speaker's name and types the text out. Click, Space or tap advances it.
  - **Title cards:** use `Juice.Banner` with `Sfx.Play("Banner")`.
  - **Skip button:** jumps to the end.
  - **On finish or skip:** everything is restored, and it fires `CutsceneDone(Id)`. If the script ends on `Fade To Black`, the screen stays black until the next cutscene's first `Fade` clears it, or for 3 seconds at most.
- **ProgressService:**
  - **On load:** `Story.NextBeat(save)` decides what plays, then it sends `Cutscene` with the copy values: `RentGoal`, `ActGoal`, the `StoryText` lines and the titles.
  - **`CutsceneDone(id)`** is accepted only if `Story.AcceptDone`.
    - `Act1Intro` → `SeenIntro = true`.
    - `Act1End` → `Flags.Act1EndSeen = true`; apply `Story.Act2Start(save.Valuation, GameConfig.ACT2.ValuationStep)`; then `PlotService.RebuildUnit(player, 2)`; then send `Act2Intro`.
    - `Act2Intro` → `Flags.Act2IntroSeen = true`.
  - **Paying rent** keeps its checks, sets `RentPaid` and sends `Act1End`. It no longer sends `"RentPaid"`.
  - **After each deploy in Act 2:** if `Story.ActGoalReached(...)` and the `Act2Complete` flag isn't set yet, set it and beat `"Act2Complete"` (a simple card, through StoryController's existing card path).
  - **The old `IntroSeen` remote handler is removed.** The remote name stays in `RemoteNames`, so the count stays at 20.
- **StoryController** drops its `"Intro"` and `"RentPaid"` handling and adds `"Act2Complete"` → `showCard({ "You hit your valuation goal." }, "Act 2 complete. To be continued.")`.

- [ ] **Step 1:** Implement `Actors` and CutsceneController, wire ProgressService and StoryController, and delete IntroController.
- [ ] **Step 2:** Verify that build and analyze are clean and Lune passes.
- [ ] **Step 3: Playtest** with a fresh save, using a new DataStore key or the Data Stores Manager:
  - The Act 1 opening plays. Skip works and it doesn't replay on rejoin.
  - Paying rent plays the Act 1 ending, goes black, the office appears unseen, and the Act 2 opening plays.
  - **Review Focus 1:** leave during the Act 1 ending and rejoin. It resumes the Act 1 ending.
  - Force an old save (rent paid, Act 1). The Act 1 ending plays on join.
  - **Review Focus 2:** from the client command bar, `FireServer` `CutsceneDone("Act2Intro")` while in Act 1. Nothing changes.
- [ ] **Step 4:** Commit with `feat: in-engine cutscenes and act 1 to act 2 story flow`.

### Task 7: Startup name

**Files:**
- Create: `src/ServerScriptService/Services/StartupNameService.luau`
- Modify: `CutsceneController.luau` (the `NameStartup` step), and add a small rename dialog in `src/StarterPlayer/StarterPlayerScripts/UI/NameDialog.luau`

**Interfaces:**
- **`SetStartupName(raw: string)`:**
  1. Type and length checked (`#raw <= GameConfig.MAX_REMOTE_STRING`), then `Story.PrecheckName`.
  2. In a `pcall`: `TextService:FilterStringAsync(clean, player.UserId)` → `:GetNonChatStringForBroadcastAsync()`.
  3. Rejected if the filtered text is empty or all `#`.
  4. On success: `Update(save.StartupName = filtered)`, `WorldBuilder.SetSignText(unit, filtered)`, then reply `NameResult(true, filtered)`. Otherwise reply `NameResult(false, reason)`.
  5. Rate limit: 2 per 3 seconds.
- **The `StartupSign` prompt** → `OpenUI("Rename")` → `NameDialog`.
- **`NameDialog.Prompt(defaultText: string): ()`** shows a themed text box and Confirm button. It fires `SetStartupName` and waits for `NameResult`. On `false` it shakes and shows the reason, then lets the player retry. On `true` it closes with a pop and `Sfx.Play("PromptClean")`. The cutscene's `NameStartup` step uses it and continues only after a `true` result. Skip leaves the name unset, so the sign shows "UNTITLED STARTUP".

- [ ] **Step 1:** Implement it.
- [ ] **Step 2:** Verify that build and analyze are clean and Lune passes.
- [ ] **Step 3: Playtest (Review Focus 3):**
  - `"ab"`, `"   "` and `"🚀🚀🚀"` are rejected with their reasons.
  - A valid name shows on the sign.
  - The rename prompt works later.
  - A second player sees the filtered name. Studio filters differently from live servers, so record what Studio shows.
- [ ] **Step 4:** Commit with `feat: name your startup (filtered) with rename sign`.

### Task 8: Animation assets and publish checklist

**Files:**
- Create: `tools/animations/build.luau`. This is a Lune script using `@lune/roblox` to write one `<Name>.rbxm` per animation into `src/ServerStorage/Animations/`.
- Create: `docs/animations-publish-checklist.md`
- Test: `tests/AnimationData.spec.luau`, which tests the keyframe data tables that `build.luau` reads from `tools/animations/data.luau`.

**Interfaces:**
- **`tools/animations/data.luau`** returns `{ [name]: { Looped: boolean, Keyframes: { { Time: number, Poses: { [jointPartName]: { Rotation: Vector3 } } } } } }`. It covers `LaptopClose`, `HandOverCash`, `CountCash`, `Talk`, `SitCouch` and `DeskType` (looped), using R15 part names (`UpperTorso`, `RightUpperArm`, `RightLowerArm`, `LeftUpperArm`, `LeftLowerArm`, `Head`, `RightUpperLeg`, `LeftUpperLeg`, …). Rotations are in degrees.
- **`build.luau`** builds a `KeyframeSequence` (with `Loop` set), then `Keyframe` children with a `Pose` hierarchy rooted at `HumanoidRootPart` → `LowerTorso` → …, and saves each with `roblox.serializeModel`.

- [ ] **Step 1: Write the failing tests:**
  - `every animation has increasing keyframe times starting at 0`
  - `every pose names an R15 part` (checked against a fixed R15 part list in the test)
  - `the set matches GameConfig.ANIMATIONS keys`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `data.luau` and `build.luau`, then run `lune run tools/animations/build.luau`. Expected: six `.rbxm` files in `src/ServerStorage/Animations/`.
- [ ] **Step 4:** Run the tests. Expected: PASS. `rojo build` succeeds, and the six `KeyframeSequence`s appear under `ServerStorage.Animations` in the built place.
- [ ] **Step 5:** Write the checklist:
  1. Open Studio connected through Rojo.
  2. In Explorer, go to ServerStorage → Animations.
  3. Right-click each `KeyframeSequence` → **Save to Roblox** (or **Publish to Roblox**), as the experience owner or its group.
  4. Copy the asset ID.
  5. Paste it into `GameConfig.ANIMATIONS.<Name>`.
  6. Replay the cutscenes to check.
- [ ] **Step 6:** Commit with `feat: generated cutscene/employee animations and publish checklist`.

### Task 9: Employees (Act 2) and hire gating

**Files:**
- Create: `src/ServerScriptService/Services/EmployeeService.luau`
- Modify: `src/ServerScriptService/Services/ShopService.luau`

**Interfaces:**
- **`ShopService.catalogFor`** includes hires only when `save.Act >= 2`. `onPurchase` rejects hire ids when `save.Act < 2` with the notice "Hire people once you have an office."
- **`EmployeeService.Refresh(player: Player)`.** For the owner's unit, if `save.Act >= 2`, for each `EmployeeDesk` (by its `Role` attribute):
  - **Not hired:** `HiringNote` is visible and any NPC is removed.
  - **Hired:** `HiringNote` is hidden. One NPC named `Employee_<Role>` is spawned (once) and seated on `EmployeeSeat`, with a `BillboardGui` showing `GameConfig.HIRES[Role].Name`.
  - **Look:** a friend's avatar comes from `Players:GetFriendsAsync(player.UserId)` (the first pages, inside a `pcall`), then `Players:GetHumanoidDescriptionFromUserId(friendId)` (inside a `pcall`). Each role gets a different friend in order. With no friend available, use a `HumanoidDescription` with random body colors.
  - **Model:** built with `Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)`.
  - **Animation:** the server plays `GameConfig.ANIMATIONS.DeskType` on the NPC's `Animator` when it's not 0. Otherwise they stay seated, which is the built-in sit.
- **Refresh is called** after `PlotService.RebuildUnit` builds the office (Task 4/6) and after a hire purchase (ShopService). NPCs go away with the contents when the unit reverts.

- [ ] **Step 1:** Implement it.
- [ ] **Step 2:** Verify that build and analyze are clean and Lune passes.
- [ ] **Step 3: Playtest:**
  - In Act 1 the shop shows no hires, and firing `Purchase("FrontendUnits")` from the command bar is rejected.
  - In Act 2, hiring fills that desk with an avatar typing, and the note disappears.
  - **Review Focus 4:** test with an account that has no friends. Employees still appear, with random colors.
  - An Act 1 save that already owns a hire shows that employee on moving in.
- [ ] **Step 4:** Commit with `feat: employees appear in the act 2 office as friends' avatars`.

### Task 10: Act 2 HUD goal

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/Controllers/HudController.luau`

**Interfaces:**
- In Act 1 the rent row is unchanged.
- In Act 2 (`view.Act >= 2`), the same row reads `GOAL  valuation x{Valuation:%.2f} / x{ActGoal:%.2f}`, and the bar fills by `(Valuation - start) / (ActGoal - start)`. Here `start = ActGoal - GameConfig.ACT2.ValuationStep`, and the result is clamped between 0 and 1.

- [ ] **Step 1:** Implement it.
- [ ] **Step 2:** Verify that build and analyze are clean.
- [ ] **Step 3: Playtest:** in Act 2 the goal row moves after each deploy, and reaching it shows the Act 2 complete card once.
- [ ] **Step 4:** Commit with `feat: act 2 valuation goal in the HUD`.

### Task 11: Verification pass

- [ ] **Step 1:** Run `lune run tests/run.luau`, `luau-lsp analyze` and `rojo build`. Expected: all clean.
- [ ] **Step 2:** Grep `src` for `wait(`, `spawn(`, `delay(`, `pairs(` and service dot-indexing. Expected: none.
- [ ] **Step 3:** Fresh-save playthrough: Act 1 opening → rent → Act 1 ending → office → Act 2 opening with naming → hire one employee → reach the Act 2 goal.
- [ ] **Step 4:** Commit and merge into `main`, then push.
