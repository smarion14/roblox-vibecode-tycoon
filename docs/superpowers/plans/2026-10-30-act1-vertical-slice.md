# Vibecoder Startup Tycoon: Act 1 Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable Act 1. The player sees the opening scene, takes jobs, builds components at 4 stations with typing bursts, ships in a deploy battle, buys gear and hires, saves progress, and finishes Act 1 by paying rent.

**Architecture:**
- **Pure layer.** Game rules (typing judgement, battle simulation, economy, save sanitising) live in pure Luau modules under `ReplicatedStorage/Shared`. These modules have no Roblox APIs and no requires, and are unit-tested with Lune.
- **Server layer.** Thin services in `ServerScriptService/Services` own all state. They react to physical `ProximityPrompt` interactions and to rate-limited remotes from `RemoteManager`.
- **Client layer.** Controllers in `StarterPlayerScripts/Controllers` only render what the server sends and forward raw input.
- **World.** A code-built blockout, so the game runs with no uploaded art.

**Tech Stack:**
- Roblox and Luau `--!strict`, synced with Rojo 7.7.1 (aftman).
- Lune for unit tests of the pure modules.
- `luau-lsp analyze` for type checks.
- DataStoreService for persistence.

**Spec:** `docs/superpowers/specs/2026-10-30-vibecoder-startup-tycoon-design.md`

## Global Constraints

**Code style (from `CLAUDE.md`)**
- Every `.luau` file starts with `--!strict`.
- `game:GetService("X")` calls go at the top of each file. Never index services with dots.
- Use the `task` library only. Never use `wait`, `spawn` or `delay`.
- Iterate with generalized iteration `for k, v in t do`. Never use `pairs` or `ipairs`.
- Type every function's parameters and return values, and every state table.
- Naming: `PascalCase` for modules, services and exported functions; `camelCase` for locals; `LOUD_SNAKE_CASE` for constants.

**Pure modules** (`src/ReplicatedStorage/Shared/*.luau` except `GameConfig`, `PromptBank`, `RemoteNames`, which are plain data)
- They contain no `require`, `game`, `script`, `Random`, `task`, `os.time` or `os.clock`.
- Config, clocks, RNG and other modules' functions come in as parameters.
- Lune tests require them by file path.

**Security and server authority**
- The server is authoritative. The client never sends timestamps, scores, grades, cash or prices.
- The server times everything with `os.clock()`. Battle visuals use `workspace:GetServerTimeNow()` only to animate.
- Every `OnServerEvent` handler validates argument types first. Any string longer than `GameConfig.MAX_REMOTE_STRING` (200) is dropped.
- All remotes go through `RemoteManager` (existing file).

**Gameplay rules**
- Physical interactions use a `ProximityPrompt` on a world model, handled with server-side `Triggered`. No pads, and no income without player input.
- All player-facing text is English, in a generic setting with no regional names, slang or brands.
- All tunable numbers live in `GameConfig`. Code reads them from there and never hard-codes them.

**Scope**
- Act 1 only (spec §2 "First build").
- Not in this plan: Acts 2–3, unit transformation, spectating, hype gifts, leaderboards, monetization.

## Review Focus

1. **Save errors on join.** A DataStore error on join must never let the player play on default data, which would later overwrite their real save. They should be kicked with a "please rejoin" message. A brand-new player (no record) gets defaults. *Pinned in Task 4 (`ResolveLoad` tests) and Task 6 (playtest).*
2. **Leaving mid-battle or mid-burst.** A player who leaves or resets during a battle or burst loses nothing: components and the job stay, and the activity lock clears so they can play after rejoining. *Pinned in Task 9 and Task 10 playtest steps.*
3. **Lag around bugs.** A squash or prompt that arrives up to `LatencyGrace` after a bug reaches the prompt still counts. Just past the grace window, it doesn't. *Pinned in Task 5 tests.*
4. **Messy typing.** Capitals from phone auto-capitalisation, doubled spaces, trailing spaces, emoji or very long pasted text must neither crash the server nor score as perfect. *Pinned in Task 2 tests.*
5. **Bug words inside prompts.** If a battle prompt contains a bug word, typing the prompt would squash a bug and eat the player's input. *Pinned in Task 1 test: no prompt contains a bug word as a whole word.*

---

### Task 0: Tooling, repo, project layout, test harness

**Files:**
- Create: `.gitignore`, `tests/run.luau`, `types/` (downloaded definitions)
- Modify: `aftman.toml`, `default.project.json`

**Interfaces:**
- Produces:
  - Test convention: each `tests/<Name>.spec.luau` returns `{ [string]: () -> () }`, a table of named test functions that fail by calling `error`/`assert`.
  - `lune run tests/run.luau` runs every spec, prints `PASS <file>::<name>` or `FAIL <file>::<name>: <err>`, prints a summary line `<p> passed, <f> failed`, and exits with code 1 if anything failed.

- [ ] **Step 1:** Run `git init`. Create `.gitignore` containing `.superpowers/`, `sourcemap.json`, `*.rbxl.lock`, `game.rbxl` and `types/`.
- [ ] **Step 2:** Run `aftman add lune-org/lune` and `aftman add JohnnyMorganz/luau-lsp`, then `aftman install`. Expected: `lune --version` and `luau-lsp --version` both print versions.
- [ ] **Step 3:** Download `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau` to `types/globalTypes.d.luau`. If that path 404s, use the newest `globalTypes*.d.luau` in that folder.
- [ ] **Step 4:** Change `default.project.json` to map whole folders. Keep `Workspace` and `Lighting` as they are.
  - `ReplicatedStorage` → `"$path": "src/ReplicatedStorage"`
  - `ServerScriptService` → `"$path": "src/ServerScriptService"`
  - `StarterPlayer.StarterPlayerScripts` → `"$path": "src/StarterPlayer/StarterPlayerScripts"`
- [ ] **Step 5:** Write `tests/run.luau`. It uses `@lune/fs` `readDir("tests")` to find `*.spec.luau`, `require`s each, runs every entry under `pcall`, and uses `@lune/process` `exit(1)` on any failure.
- [ ] **Step 6:** Verify.
  - `lune run tests/run.luau` prints `0 passed, 0 failed`.
  - `rojo build -o game.rbxl` prints `Built project`.
  - `rojo sourcemap -o sourcemap.json`, then `luau-lsp analyze --sourcemap=sourcemap.json --definitions=types/globalTypes.d.luau src` reports no errors. If it flags the 3 existing files, fix only type errors.
- [ ] **Step 7:** Commit with `chore: tooling, folder-mapped project, lune test harness`.

### Task 1: Static data (config, prompts, remote names)

**Files:**
- Create: `src/ReplicatedStorage/Shared/GameConfig.luau`, `src/ReplicatedStorage/Shared/PromptBank.luau`, `src/ReplicatedStorage/Shared/RemoteNames.luau`
- Test: `tests/Data.spec.luau`

**Interfaces:**
- Produces `GameConfig`. These starting values are tunable later, but the field names are fixed.
  - `COMPONENTS = { "FrontendUnits", "BackendEndpoints", "DatabaseTables", "PromptTokens" }`
  - `STATION_NAMES = { FrontendUnits = "Frontend Terminal", BackendEndpoints = "Server Rack", DatabaseTables = "Database Console", PromptTokens = "AI Model Rig" }`
  - `RECIPES = { LandingPage = { FrontendUnits = 2, BackendEndpoints = 1, DatabaseTables = 1, PromptTokens = 1 } }`
  - `CLIENTS = { { Id = "PawsAndSuds", Name = "Paws & Suds Grooming", Project = "LandingPage", TierMultiplier = 20, UnlockAtDeploys = 0 }, { Id = "RollingTaco", Name = "Rolling Taco Truck", Project = "LandingPage", TierMultiplier = 30, UnlockAtDeploys = 2 }, { Id = "CornerBakery", Name = "Corner Bakery", Project = "LandingPage", TierMultiplier = 40, UnlockAtDeploys = 4 } }`
  - `GEAR = { MechanicalKeyboard = { Name = "Mechanical Keyboard", Price = 300, TimeBonus = 2 }, SecondMonitor = { Name = "Second Monitor", Price = 500, PreviewNext = true }, ModelV2 = { Name = "Model v2", Price = 800, ForgiveEdits = 1 } }`
  - `HIRES = { FrontendUnits = { Name = "Frontend Intern", Price = 250 }, ... }`: one per component, each priced 250.
  - `BURST_PROMPT_COUNT = 3`
  - `BURST_RULES = { TimeLimit = 10, LatencyGrace = 0.5, MaxCharsPerSecond = 20, ForgivenEditsPerBurst = 0 }`
  - `BATTLE_RULES = { ShipPromptsRequired = 4, BugTravelTime = 6, FirstBugDelay = 2, LatencyGrace = 0.25, MoodHitPenalty = 15, BadPromptPenalty = 5, MinPromptAccuracy = 0.6, CleanPromptAccuracy = 0.9, MaxDuration = 120, MaxCharsPerSecond = 20 }`
  - `STARTING_VALUATION = 1.0`
  - `RENT_GOAL = 1500`
  - `MAX_PLAYERS = 6`
  - `MAX_REMOTE_STRING = 200`
  - `SAVE = { DataStoreName = "VibecoderSave_v1", KeyPrefix = "player_", AutosaveInterval = 60, LockStaleAfter = 120, MaxLoadRetries = 3 }`
- Produces `PromptBank`:
  - `BURST_PROMPTS: { [string]: { string } }`: at least 8 short prompts (25–50 characters) per component, lowercase ASCII, no punctuation except spaces and commas.
  - `BATTLE_PROMPTS: { string }`: at least 10 prompts of 40–70 characters.
  - `BUG_WORDS: { string }`: at least 12 lowercase words, 3–6 characters, e.g. `null`, `cors`, `race`, `typo`, `leak`, `loop`.
  - Example prompt: `"make the navbar sticky and add a dark mode toggle"`.
- Produces `RemoteNames`: string constants for `AcceptJob`, `OpenUI`, `Notice`, `StateSync`, `BurstPrompt`, `SubmitBurstPrompt`, `BurstFinished`, `BattleStarted`, `BattleSubmitPrompt`, `BattleSquash`, `BattleUpdate`, `BattleEnded`, `Purchase`, `StoryBeat` and `IntroSeen`. Each value equals its key.

- [ ] **Step 1: Write the failing tests** in `tests/Data.spec.luau`:
  - `every recipe names only known components`
  - `every client project has a recipe`
  - `prompts are lowercase ascii`: every prompt matches `^[a-z0-9 ,]+$`.
  - `no prompt contains a bug word as a whole word`: for each prompt (burst and battle) and each bug word, `(" " .. prompt .. " "):find(" " .. word .. " ", 1, true) == nil`.
  - `bug words are unique`
  - `remote names map to themselves`
- [ ] **Step 2:** Run `lune run tests/run.luau`. Expected: FAIL (modules missing).
- [ ] **Step 3:** Write the three modules with the values above. Write the prompt copy in English with generic everyday software requests.
- [ ] **Step 4:** Run `lune run tests/run.luau`. Expected: all PASS.
- [ ] **Step 5:** Commit with `feat: game config, prompt bank, remote names`.

### Task 2: TypingJudge (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/TypingJudge.luau`
- Test: `tests/TypingJudge.spec.luau`

**Interfaces:**
- Produces:
  - Types:
    - `export type Grade = "S" | "A" | "B" | "C"`
    - `export type BurstRules = { TimeLimit: number, LatencyGrace: number, MaxCharsPerSecond: number, ForgivenEditsPerBurst: number }`
    - `export type IssuedPrompt = { Text: string, IssuedAt: number }`
    - `export type Submission = { Text: string, ReceivedAt: number }`
    - `export type BurstResult = { Accuracy: number, Completed: number, Grade: Grade, Flagged: boolean }`
  - `TypingJudge.Normalize(text: string): string`: trims, collapses runs of whitespace to one space, and lowercases.
  - `TypingJudge.Accuracy(expected: string, typed: string, forgivenEdits: number): number`. Both inputs are normalized. The result is `max(0, 1 - max(0, levenshtein - forgivenEdits) / max(#expected, 1))`. It returns `0` when `#typed > 2 * #expected` or when `typed` is empty. Levenshtein is computed over bytes.
  - `TypingJudge.IsPlausible(charCount: number, elapsed: number, maxCharsPerSecond: number): boolean`: `elapsed > 0 and charCount / elapsed <= maxCharsPerSecond`.
  - `TypingJudge.JudgeBurst(prompts: { IssuedPrompt }, submissions: { [number]: Submission }, rules: BurstRules): BurstResult`
    - The deadline is `prompts[1].IssuedAt + rules.TimeLimit + rules.LatencyGrace`.
    - A prompt scores 0 if its submission is missing or late.
    - A prompt scores 0 and sets `Flagged` if `IsPlausible(#text, ReceivedAt - IssuedAt, MaxCharsPerSecond)` is false.
    - `ForgivenEditsPerBurst` applies to the first prompt with any error, once per burst.
    - `Accuracy` is the mean over all prompts. `Completed` counts in-time, non-flagged submissions.
    - Grade: `S` if all prompts were completed and accuracy is at least 0.98; otherwise `A` at 0.93 or more, `B` at 0.80 or more, else `C`.

- [ ] **Step 1: Write the failing tests:**
  - `normalize`: `Normalize("  Make   the NAVBAR sticky ") == "make the navbar sticky"`
  - `exact match`: `Accuracy("abc", "abc", 0) == 1`
  - `one substitution`: `Accuracy("abcd", "abed", 0) == 0.75`
  - `forgiven edit`: `Accuracy("abcd", "abed", 1) == 1`
  - `empty typed`: `Accuracy("abc", "", 0) == 0`
  - `huge paste`: `Accuracy("ab", string.rep("x", 5), 0) == 0`
  - `emoji does not crash`: `Accuracy("add a button", "add a button 🚀", 0)` is a number between 0 and 1, exclusive of 1.
  - `plausibility`: `IsPlausible(20, 1, 20) == true`, `IsPlausible(21, 1, 20) == false`, `IsPlausible(5, 0, 20) == false`
  - `perfect burst is S`: 3 prompts issued at t = 0, 3 and 6, submitted exactly at t = 2.9, 5.9 and 8.9 with rules `{TimeLimit=10, LatencyGrace=0.5, MaxCharsPerSecond=20, ForgivenEditsPerBurst=0}` and texts of 25–40 characters. Expect `Grade == "S"`, `Accuracy == 1`, `Completed == 3`, `Flagged == false`.
  - `late submission scores zero`: the third prompt arrives at `10.51`. Expect `Completed == 2` and `Grade ~= "S"`.
  - `missing submission`: the third submission is absent. Expect `Completed == 2`.
  - `superhuman speed flagged`: 40 characters arriving 0.5 s after issue. Expect `Flagged == true` and that prompt counts 0.
  - `forgiven once per burst`: with `ForgivenEditsPerBurst = 1` and two prompts each with 1 typo, the first scores 1 and the second scores below 1.
- [ ] **Step 2:** Run `lune run tests/run.luau`. Expected: FAIL.
- [ ] **Step 3:** Implement `TypingJudge.luau`. Use the standard two-row dynamic-programming Levenshtein.
- [ ] **Step 4:** Run `lune run tests/run.luau`. Expected: PASS.
- [ ] **Step 5:** Commit with `feat: server-side typing judge`.

### Task 3: Economy (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/Economy.luau`
- Test: `tests/Economy.spec.luau`

**Interfaces:**
- Produces:
  - Types:
    - `export type Grade = "S" | "A" | "B" | "C"`. This duplicates TypingJudge's literal union, because pure modules can't require each other. Comment it as `-- shortcut: duplicated literal type, pure modules cannot require each other; unify if require-by-string is adopted`.
    - `export type GradeCounts = { S: number, A: number, B: number, C: number }`
    - `export type Inventory = { [string]: GradeCounts }`, keyed by component name.
    - `export type Recipe = { [string]: number }`
    - `export type ClientDef = { Id: string, Name: string, Project: string, TierMultiplier: number, UnlockAtDeploys: number }`
    - `export type GearDef = { Name: string, Price: number, TimeBonus: number?, PreviewNext: boolean?, ForgiveEdits: number? }`
    - `export type BurstRules`: the same shape as TypingJudge's.
  - `Economy.EmptyInventory(components: { string }): Inventory`
  - `Economy.TotalUnits(inv: Inventory): number`
  - `Economy.AverageQuality(inv: Inventory): number`: S = 3, A = 2, B = 1, C = 0. Returns 0 for an empty inventory.
  - `Economy.MeetsRecipe(inv: Inventory, recipe: Recipe): boolean`
  - `Economy.AddUnit(inv: Inventory, component: string, grade: Grade): Inventory`: returns a new table. If the grade is better than C and a C unit exists for that component, one C is replaced; otherwise the unit is added.
  - `Economy.ApplyHires(inv: Inventory, recipe: Recipe, hired: { [string]: boolean }): Inventory`: for each hired component, adds C units until that component meets its recipe count.
  - `Economy.PerformanceScore(moodRatio: number, accuracy: number, maxCombo: number): number`. Inputs are clamped to 0–1 and NaN counts as 0. Result: `2 * (0.5 * mood + 0.3 * accuracy + 0.2 * min(maxCombo / 30, 1))`.
  - `Economy.Payout(totalUnits: number, valuation: number, score: number, tierMultiplier: number): number` = `math.floor(totalUnits * valuation * math.clamp(score, 0, 2) * tierMultiplier)`
  - `Economy.ValuationGain(score: number): number` = `0.05 * math.clamp(score, 0, 2)`
  - `Economy.AvailableClients(clients: { ClientDef }, deploysShipped: number): { ClientDef }`
  - `Economy.ApplyGear(base: BurstRules, owned: { [string]: boolean }, gear: { [string]: GearDef }): (BurstRules, boolean)`: adds owned `TimeBonus` to `TimeLimit` and owned `ForgiveEdits` to `ForgivenEditsPerBurst`. The second return value is true if any owned gear has `PreviewNext`.

- [ ] **Step 1: Write the failing tests** (`C = {S=0,A=0,B=0,C=0}` shorthand):
  - `total and average`: an inventory with FrontendUnits `{S=1,A=0,B=0,C=1}` gives `TotalUnits == 2` and `AverageQuality == 1.5`. An empty inventory gives `AverageQuality == 0`.
  - `recipe`: the landing-page recipe isn't met with 1 frontend unit and is met with exactly 2/1/1/1.
  - `add unit replaces a C`: adding A to `{C=1}` gives `{A=1, C=0}`. Adding C to `{C=1}` gives `{C=2}`. The input table is unchanged.
  - `hires fill to recipe`: with FrontendUnits hired and the landing-page recipe, an empty inventory gets `FrontendUnits.C == 2`, and other components stay 0.
  - `score bounds`: `PerformanceScore(1, 1, 30) == 2`, `PerformanceScore(0, 0, 0) == 0`, `PerformanceScore(0/0, 2, -5) == 0.6`
  - `payout`: `Payout(5, 1.0, 1.0, 20) == 100` and `Payout(5, 1.0, 9, 20) == 200`
  - `clients unlock`: with GameConfig's clients, `#AvailableClients(clients, 0) == 1` and `#AvailableClients(clients, 4) == 3`
  - `gear`: owning MechanicalKeyboard and ModelV2 gives `TimeLimit == 12`, `ForgivenEditsPerBurst == 1` and preview `false`. Owning SecondMonitor gives preview `true`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `Economy.luau`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit with `feat: economy rules`.

### Task 4: SaveSchema (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/SaveSchema.luau`
- Test: `tests/SaveSchema.spec.luau`

**Interfaces:**
- Consumes: the `Inventory` shape from Task 3 (redeclared locally, as in Task 3).
- Produces:
  - `SaveSchema.VERSION = 1`
  - `export type PlayerSave = { Version: number, Cash: number, Valuation: number, Act: number, DeploysShipped: number, RentPaid: boolean, SeenIntro: boolean, Inventory: Inventory, Gear: { [string]: boolean }, Hires: { [string]: boolean }, StoryFlags: { [string]: boolean }, LockJobId: string?, LockTime: number }`
  - `export type SaveCatalog = { Components: { string }, GearIds: { string }, HireIds: { string }, StartingValuation: number }`
  - `SaveSchema.Default(catalog: SaveCatalog): PlayerSave`: Cash 0, Valuation = `StartingValuation`, Act 1, empty inventory over the catalog's components, empty maps, `LockTime = 0`.
  - `SaveSchema.Sanitize(raw: any, catalog: SaveCatalog): PlayerSave`
    - A non-table input returns `Default`.
    - Numbers must be finite. Cash, DeploysShipped and grade counts are ≥ 0 and floored. Valuation is ≥ `StartingValuation`.
    - Act is clamped to 1–3.
    - Gear, hire and component keys not in the catalog are dropped.
    - Unknown top-level fields are dropped.
  - `SaveSchema.ResolveLoad(ok: boolean, raw: any): "Fail" | "UseDefault" | "UseRaw"`: returns `Fail` when `ok` is false, `UseDefault` when `raw == nil`, and otherwise `UseRaw`.
  - `SaveSchema.TryClaimLock(save: PlayerSave, jobId: string, now: number, staleAfter: number): boolean`. It returns true and sets `LockJobId`/`LockTime` when there is no lock, the lock is held by the same `jobId`, or `now - LockTime > staleAfter`. Otherwise it returns false and leaves the save unchanged.

- [ ] **Step 1: Write the failing tests:**
  - `sanitize nil gives default`
  - `negative and NaN cash become 0`: covers `Cash = -5`, `Cash = 0/0` and `Cash = math.huge`.
  - `valuation floor`: `Valuation = 0.2` becomes `1.0`.
  - `unknown gear dropped`: `Gear = { Jetpack = true, MechanicalKeyboard = true }` keeps only MechanicalKeyboard.
  - `grade counts floored`: `{ S = 2.7 }` becomes `S == 2`.
  - `act clamped`: `Act = 9` becomes `3`.
  - `resolve load`: `(false, nil)` is `"Fail"`, `(false, {})` is `"Fail"`, `(true, nil)` is `"UseDefault"`, `(true, {})` is `"UseRaw"`.
  - `lock claims`:
    - With no lock, `TryClaimLock` returns true.
    - With a lock from another job 10 s ago (`staleAfter = 120`), it returns false and the save is unchanged.
    - With a lock from another job 121 s ago, it returns true.
    - With the same job, it returns true.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `SaveSchema.luau`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit with `feat: save schema sanitising and session lock`.

### Task 5: BattleState (pure)

**Files:**
- Create: `src/ReplicatedStorage/Shared/BattleState.luau`
- Test: `tests/BattleState.spec.luau`

**Interfaces:**
- Consumes: `TypingJudge.Accuracy` and `TypingJudge.IsPlausible`, both injected.
- Produces:
  - Types:
    - `export type BattleRules`: the shape of `GameConfig.BATTLE_RULES`.
    - `export type Judge = { Accuracy: (string, string, number) -> number, IsPlausible: (number, number, number) -> boolean }`
    - `export type Bug = { Id: number, Word: string, Side: number, SpawnAt: number, ReachAt: number, State: "Pending" | "Squashed" | "Hit" }`
    - `export type Battle = { StartTime: number, Mood: number, Combo: number, MaxCombo: number, Progress: number, PromptIndex: number, PromptIssuedAt: number, Prompts: { string }, Bugs: { Bug }, AccuracySum: number, PromptsJudged: number, Status: "Running" | "Shipped" | "Failed", Rules: BattleRules }`
    - `export type BattleResult = { Status: "Shipped" | "Failed", MoodRatio: number, Accuracy: number, MaxCombo: number }`
    - `export type BattleSnapshot = { Mood: number, Combo: number, Progress: number, PromptText: string, BugStates: { [number]: string }, Status: string }`
  - `BattleState.New(startTime: number, avgQuality: number, prompts: { string }, bugWords: { string }, rules: BattleRules, rng: () -> number): Battle`
    - Starting mood is `math.clamp(70 + 10 * avgQuality, 70, 100)`.
    - Bugs spawn at `startTime + FirstBugDelay`, then every `1.6 + 0.3 * avgQuality` seconds, up to `startTime + MaxDuration`.
    - Each bug's `ReachAt = SpawnAt + BugTravelTime`.
    - `rng` (0–1) picks the word and `Side` (−1 or 1).
    - `PromptIssuedAt = startTime`.
  - `BattleState.Tick(b: Battle, now: number)`
    - Every pending bug with `now > ReachAt + LatencyGrace` becomes `Hit`, applying `Mood -= MoodHitPenalty` and `Combo = 0`.
    - `Mood <= 0` sets `Failed`.
    - `now > StartTime + MaxDuration` while still running sets `Failed`.
  - `BattleState.Squash(b: Battle, word: string, now: number): boolean`
    - Calls `Tick` first.
    - Finds the earliest pending bug with a matching normalized word, where `SpawnAt <= now <= ReachAt + LatencyGrace`. If found, it becomes `Squashed`, `Combo += 1`, and `MaxCombo` updates. If none matches, `Combo = 0` and the call returns false.
  - `BattleState.SubmitPrompt(b: Battle, text: string, now: number, judge: Judge): number`
    - Calls `Tick` first.
    - Accuracy is `judge.Accuracy(prompt, text, 0)`, or 0 if `judge.IsPlausible(#text, now - PromptIssuedAt, MaxCharsPerSecond)` is false.
    - At `CleanPromptAccuracy` or above: `Combo += 1` and `Progress += 1`.
    - Below `MinPromptAccuracy`: `Mood -= BadPromptPenalty`, `Combo = 0`, the same prompt is reissued, and `Progress` doesn't change.
    - Otherwise: `Progress += 1`.
    - When the prompt is accepted, it advances to the next prompt (wrapping around), and `PromptIssuedAt = now` either way.
    - `Progress >= ShipPromptsRequired` sets `Shipped`.
    - The accuracy is added to `AccuracySum`/`PromptsJudged`, and the function returns it.
  - `BattleState.Result(b: Battle): BattleResult`: `MoodRatio = Mood / 100`, `Accuracy = AccuracySum / max(PromptsJudged, 1)`.
  - `BattleState.Snapshot(b: Battle): BattleSnapshot`

- [ ] **Step 1: Write the failing tests.** Use `GameConfig.BATTLE_RULES`, a fixed-sequence `rng` (e.g. a cycle of `0.1, 0.6`), and the real `TypingJudge` as `judge`.
  - `start mood from quality`: `avgQuality` 0 gives 70, 3 gives 100.
  - `first bug timing`: `Bugs[1].SpawnAt == startTime + 2` and `Bugs[1].ReachAt == startTime + 8`.
  - `bug hit after grace`: `Tick` at `ReachAt + 0.26` makes it `Hit` and drops mood by 15. At `ReachAt + 0.24` it stays `Pending`.
  - `squash within grace (lag)`: `Squash(word, ReachAt + 0.2)` returns true. A fresh battle with `Squash(word, ReachAt + 0.3)` returns false.
  - `squash before spawn fails`: squashing at `SpawnAt - 0.1` returns false, and the combo resets.
  - `clean prompt`: exact text at +4 s gives `Progress == 1`, `Combo == 1`, returns 1.
  - `garbage prompt`: `"zzzz"` gives `Progress == 0`, mood drops by 5, and the same `PromptIndex`.
  - `superhuman prompt`: a 60-character exact text at +0.5 s returns 0.
  - `ships after 4 clean prompts`: use `avgQuality = 3` and submit exact texts at +4, +8, +12 and +16 s. Four bugs hit by then, leaving mood 40. Expect `Status == "Shipped"` and `Result(b).Accuracy == 1`.
  - `garbage prompt` above is submitted at +1 s, before any bug reaches the prompt.
  - `fails at zero mood`: enough unsquashed bugs ticked past reach sets `Status == "Failed"`.
  - `fails on timeout`: `Tick(startTime + 121)` on a running battle sets `Failed`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `BattleState.luau`, with word matching through a local normalize (trim and lowercase).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit with `feat: deterministic deploy battle simulation`.

### Task 6: Player data service, bootstraps, sync

**Files:**
- Modify: `src/ServerScriptService/Components/StartupDataModule.luau` (rewrite; replaces `IncrementComponent`/`ProcessDeploymentPayout`/`GetTotalComponents`)
- Modify: `src/ServerScriptService/Services/AssemblyService.luau` (temporarily reduced to an empty `Init`/`Start` service, so nothing references the removed functions; rebuilt in Task 8)
- Create: `src/ServerScriptService/Main.server.luau`, `src/StarterPlayer/StarterPlayerScripts/Main.client.luau`

**Interfaces:**
- Consumes: `SaveSchema` (Task 4), `GameConfig`, `RemoteNames`, `RemoteManager` (existing).
- Produces:
  - Service contract: every module in `ServerScriptService/Services` and `StarterPlayerScripts/Controllers` returns a table with `Init: () -> ()` and `Start: () -> ()`.
    - `Main.server.luau` requires `Components/StartupDataModule`, then every Services module. It calls all `Init`, then all `Start`.
    - `Main.client.luau` does the same for Controllers.
  - `StartupDataModule.OnPlayerLoaded(callback: (player: Player) -> ())`: also fires for players already loaded.
  - `StartupDataModule.IsLoaded(player: Player): boolean`
  - `StartupDataModule.GetSnapshot(player: Player): PlayerSave?`: returns a deep copy.
  - `StartupDataModule.Update(player: Player, mutator: (save: PlayerSave) -> ()): boolean`: returns false if the player isn't loaded. Otherwise it applies the mutator, marks the save dirty, and fires `StateSync` to that player with the public view (everything except the lock fields).
  - `export type Activity = "Idle" | "Burst" | "Battle"`; `StartupDataModule.GetActivity(player: Player): Activity`; `StartupDataModule.SetActivity(player: Player, activity: Activity)`: session-only, and reset to Idle on load.
  - `StartupDataModule.GetCatalog(): SaveCatalog`, built from GameConfig.

- [ ] **Step 1:** Rewrite `StartupDataModule`.
  - **Load:** load with `DataStore:UpdateAsync(KeyPrefix .. UserId)`, using `SaveSchema.Sanitize` and then `TryClaimLock(game.JobId, os.time(), LockStaleAfter)`.
  - **Result handling:** route the result through `ResolveLoad`.
    - On a lock conflict, retry up to `MaxLoadRetries` with a `task.wait(2 ^ attempt)` backoff.
    - On `Fail`, or when retries are exhausted, call `player:Kick("Couldn't load your save. Please rejoin.")` and never create a session.
  - **Save:**
    - Autosave dirty sessions every `AutosaveInterval`.
    - On `PlayerRemoving`, save and clear `LockJobId`.
    - In `game:BindToClose`, save every session in parallel with `task.spawn` and wait for them all.
- [ ] **Step 2:** Write both `Main` bootstraps, and reduce `AssemblyService` to an empty `Init`/`Start` service.
- [ ] **Step 3:** Verify: `rojo build -o game.rbxl` succeeds, and `luau-lsp analyze` (Task 0 command) reports no errors.
- [ ] **Step 4: Playtest** in Studio (game published, Studio API access enabled):
  - Join, then run `print(require(game.ServerScriptService.Components.StartupDataModule).GetSnapshot(game.Players:GetPlayers()[1]))` in the server command bar. Expected: a default save with Cash 0 and Valuation 1.
  - `Update` Cash to 50, stop, and play again. Expected: Cash 50 persisted.
  - **Review Focus 1:** temporarily make the load function `error("sim")`. Expected: the player is kicked with the rejoin message, and no save is written. Revert afterwards.
- [ ] **Step 5:** Commit with `feat: persistent player data with session lock, bootstraps`.

### Task 7: World blockout and plots

**Files:**
- Create: `src/ServerScriptService/World/WorldBuilder.luau`, `src/ServerScriptService/Services/PlotService.luau`

**Interfaces:**
- Produces:
  - `WorldBuilder.BuildFloor(): { Model }`: builds the megablock floor once and returns `MAX_PLAYERS` unit models named `Unit1`…`Unit6`. It also sets moody Lighting (dark ambient, `Atmosphere`, `BloomEffect`, `ColorCorrectionEffect` with a magenta/cyan tint).
  - Each unit model contains these parts, each tagged with CollectionService, carrying the `Unit` attribute (the unit index), and holding a `ProximityPrompt` with clear `ActionText` and `HoldDuration = 0`:
    - 4 station models: tag `Station`, attribute `Component`, a neon screen with a `SurfaceGui` label of `STATION_NAMES[component]`.
    - `DeployTerminal`
    - `ShopComputer`
    - `JobPhone`
    - `Sibling`: an R15 dummy built from a blank `HumanoidDescription`.
    - `UnitSpawn`
    - Couch and folding-table decoration with no tag.
  - `PlotService.GetUnitIndex(player: Player): number?`
  - `PlotService.IsOwnPrompt(player: Player, prompt: ProximityPrompt): boolean`: true when the prompt's ancestor model's `Unit` attribute equals the player's unit.
  - `PlotService.OnPromptTriggered(tag: string, handler: (player: Player, part: BasePart) -> ())`: connects every tagged prompt's server-side `Triggered`. It calls `handler` only for the owner's own unit; triggers from other players are ignored.
  - Assignment: the first free unit on `PlayerAdded`, freed on `PlayerRemoving`. The character spawns at `UnitSpawn` via `CharacterAdded` plus `PivotTo`. If no unit is free, the player is kicked with `"Server is full."`.

- [ ] **Step 1:** Implement both files. Use only Roblox parts and materials (`Neon`, `SmoothPlastic`, `Metal`, `Glass`).
- [ ] **Step 2:** Verify that build and analyze are clean.
- [ ] **Step 3: Playtest:**
  - Expected: you spawn in your unit, and the floor holds 6 units.
  - Each prompt shows on approach. Triggering a prompt in another player's unit (2-player local test) does nothing.
- [ ] **Step 4:** Commit with `feat: blockout megablock and plot assignment`.

### Task 8: Jobs and HUD

**Files:**
- Modify: `src/ServerScriptService/Services/AssemblyService.luau`
- Create: `src/StarterPlayer/StarterPlayerScripts/UI/Theme.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/HudController.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/JobController.luau`

**Interfaces:**
- Consumes: `PlotService.OnPromptTriggered`, `StartupDataModule.Update/GetSnapshot`, and `Economy.AvailableClients/ApplyHires/MeetsRecipe/TotalUnits/PerformanceScore/Payout/ValuationGain`.
- Produces:
  - `AssemblyService.GetActiveJob(player: Player): ClientDef?`: session-only and cleared on leave. The inventory persists.
  - `AssemblyService.SettleDeploy(player: Player, result: BattleResult): number`
    - When `Status == "Shipped"`: compute `score = PerformanceScore(...)` and `payout = Payout(TotalUnits, Valuation, score, job.TierMultiplier)`. Then `Cash += payout`, `Valuation += ValuationGain(score)` and `DeploysShipped += 1`, reset the inventory to empty, clear the job, and return the payout.
    - When `Failed`: change nothing and return 0.
  - `AssemblyService.OnDeployed(callback: (player: Player, payout: number) -> ())`
  - Remotes:
    - `JobPhone` trigger → `OpenUI(player, "Jobs", availableClients)`.
    - `AcceptJob(clientId: string)`: valid only for a loaded player who is `Idle` with no active job, when the client is available. It sets the job and applies `ApplyHires` with the recipe and owned hires.
    - `Notice(player, text)` carries feedback text.
  - `Theme` constants: colours from the approved mockup (`#0b0716` background, `#7dfcd0` typed, `#ff4fd8` accent, `#ffb84f` mood, `#ff5a6e` bug) and the font `Enum.Font.Code`.
  - `HudController` shows Cash, Valuation, the active job and the recipe progress per component, and Rent progress (`Cash / RENT_GOAL`). It updates on `StateSync` and shows `Notice` toasts.
  - `JobController` shows a list on `OpenUI("Jobs")` and fires `AcceptJob`.

- [ ] **Step 1:** Implement the server parts, then the client parts.
- [ ] **Step 2:** Verify that build and analyze are clean.
- [ ] **Step 3: Playtest:**
  - The phone opens the job list with only Paws & Suds.
  - Accepting shows the job and the recipe 0/2, 0/1, 0/1, 0/1 in the HUD.
  - Accepting a second time shows a Notice and doesn't replace the job.
  - From the command bar, firing `AcceptJob` with `"CornerBakery"` while it's locked is ignored.
- [ ] **Step 4:** Commit with `feat: client jobs and HUD`.

### Task 9: Station typing bursts

**Files:**
- Create: `src/ServerScriptService/Services/BurstService.luau`, `src/StarterPlayer/StarterPlayerScripts/UI/TypingInput.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/BurstController.luau`

**Interfaces:**
- Consumes: `TypingJudge.JudgeBurst`, `Economy.ApplyGear/AddUnit`, `PromptBank.BURST_PROMPTS`, and `AssemblyService.GetActiveJob`.
- Produces:
  - **Station trigger** (requires an active job and `Idle`): it sets `Burst` and builds the rules with `ApplyGear(BURST_RULES, save.Gear, GEAR)`. It picks `BURST_PROMPT_COUNT` random prompts for the component. It sends prompt 1 with `BurstPrompt(index: number, text: string, nextText: string?, timeLimit: number)`; `nextText` is sent only with a preview gear. It records `IssuedAt = os.clock()`.
  - **`SubmitBurstPrompt(index: number, text: string)`:** accepted only for the current index while the player is in `Burst`. It records `ReceivedAt = os.clock()` and issues the next prompt.
  - **Finish** (after the last submission, or by `task.delay(TimeLimit + LatencyGrace)`, whichever comes first, exactly once): `JudgeBurst`, then `Update` with `AddUnit(component, grade)` unless the result is `Flagged` (a flagged result adds a C unit). It sets `Idle` and sends `BurstFinished(grade: string, accuracy: number)`.
  - **Player leaves mid-burst:** the burst is discarded and nothing is added.
  - `TypingInput.Create(parent: GuiObject, mode: "Keyboard" | "Touch"): TypingField`, where `TypingField = { SetPrompt: (self, text: string) -> (), Clear: (self) -> (), Destroy: (self) -> (), OnSubmit: ((text: string) -> ())?, OnWord: ((word: string) -> boolean)? }`
    - Keyboard mode captures a focused hidden `TextBox`. It colours text as typed (correct), current or remaining, and submits when the typed length reaches the prompt length or on Enter.
    - Touch mode shows the prompt's words as scattered `TextButton` chips. Tapping appends a word, and it submits when the word count is reached.
    - `OnWord` is called at each space. If it returns true, that word is removed from the buffer; Task 10 uses this for bugs.
  - Mode: `"Touch"` if `UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled`, or if the last input was a gamepad; otherwise `"Keyboard"`.
  - `BurstController` renders the burst panel (prompt, timer bar from `timeLimit`, grade popup) with Theme styling and a keyboard click `Sound` (built-in `rbxasset://` sound) on each keystroke.

- [ ] **Step 1:** Implement BurstService, then TypingInput and BurstController.
- [ ] **Step 2:** Verify that build and analyze are clean.
- [ ] **Step 3: Playtest** (keyboard, then the Studio device emulator as a phone):
  - Typing 3 prompts cleanly gives grade S/A, and the HUD recipe counter goes up.
  - Ignoring the prompts gives a C after 10.5 s.
  - Triggering a second station mid-burst does nothing.
  - **Review Focus 2:** leave mid-burst and rejoin. Expected: no unit added, activity Idle, and stations work.
  - Touch chips submit, and the grade appears.
- [ ] **Step 4:** Commit with `feat: station typing bursts, keyboard and touch input`.

### Task 10: Deploy battle

**Files:**
- Create: `src/ServerScriptService/Services/BattleService.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/BattleController.luau`

**Interfaces:**
- Consumes: `BattleState.*` (Task 5), `TypingJudge` (as the `Judge`), `Economy.AverageQuality/MeetsRecipe`, `AssemblyService.GetActiveJob/SettleDeploy`, `PromptBank.BATTLE_PROMPTS/BUG_WORDS`, and `TypingInput`.
- Produces:
  - **DeployTerminal trigger** (requires `Idle`, an active job and `MeetsRecipe`; otherwise it sends a `Notice` naming what's missing):
    - It sets `Battle` and calls `BattleState.New(os.clock(), AverageQuality(inventory), shuffledPrompts, BUG_WORDS, BATTLE_RULES, function() return rng:NextNumber() end)` with `rng = Random.new()`.
    - It sends `BattleStarted(info)`, where `info = { ServerStart: number, ClientName: string, PromptText: string, Bugs: { { Id: number, Word: string, Side: number, SpawnOffset: number, ReachOffset: number } } }`. `ServerStart` is `workspace:GetServerTimeNow()` and the offsets are relative to it.
  - **Loop:** every 0.1 s `Tick(b, os.clock())`. When the snapshot changes, send `BattleUpdate(snapshot)`.
  - **Remotes:** `BattleSubmitPrompt(text: string)` → `SubmitPrompt`; `BattleSquash(word: string)` → `Squash`. Each is followed by `BattleUpdate`. Rate limits are 5/s for prompts and 15/s for squashes.
  - **End** (`Shipped` or `Failed`): `payout = AssemblyService.SettleDeploy(player, BattleState.Result(b))`, then send `BattleEnded(result: BattleResult, payout: number)` and set `Idle`.
  - **Player leaves mid-battle:** stop the loop with no settlement, so components and the job are kept.
  - **`BattleController`** renders the agreed layout:
    - Left: the client panel (name, face, mood bar, reaction lines picked from short English line pools by mood band).
    - Centre: the prompt via `TypingInput`, the combo, and the ship progress.
    - Bugs: `TextLabel`s that move from the sides toward the prompt using `ServerStart` and `workspace:GetServerTimeNow()`.
    - Keyboard: `OnWord` returns true and fires `BattleSquash` when the word matches a visible pending bug. Touch: bugs are buttons that fire `BattleSquash(word)`.
    - Server `BattleUpdate` values are the truth for mood, combo, progress and bug states.

- [ ] **Step 1:** Implement BattleService, then BattleController.
- [ ] **Step 2:** Verify that build and analyze are clean.
- [ ] **Step 3: Playtest:**
  - With the recipe met, the terminal starts the battle. Squashing bugs and clean prompts ship it, the payout appears, the HUD cash rises, and the recipe resets.
  - Letting bugs through fails the battle: no payout, and the components are kept.
  - Without the recipe, the terminal shows a Notice naming the missing components.
  - **Review Focus 2:** leave mid-battle and rejoin. Expected: components and inventory intact, Idle.
  - **Touch:** bug buttons squash.
- [ ] **Step 4:** Commit with `feat: deploy battle`.

### Task 11: Shop (gear and hires)

**Files:**
- Create: `src/ServerScriptService/Services/ShopService.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/ShopController.luau`

**Interfaces:**
- Produces:
  - **ShopComputer trigger:** `OpenUI(player, "Shop", catalog)`, where the catalog lists the gear and hires with name, price and owned flag.
  - **`Purchase(itemId: string)`:** valid only when the item is a known gear or hire id, not already owned, and `Cash >= Price`. It then deducts the price and sets `Gear[id]`/`Hires[id] = true` via `Update`. Any other case sends a Notice with the reason.
  - Gear takes effect on the next burst through `ApplyGear` (Task 9). Hires take effect on the next accepted job through `ApplyHires` (Task 8).

- [ ] **Step 1:** Implement both files.
- [ ] **Step 2:** Verify that build and analyze are clean.
- [ ] **Step 3: Playtest:**
  - Buying the keyboard with enough cash makes the next burst's timer read 12 s.
  - Buying the frontend intern and then accepting a job shows frontend at 2/2 (C).
  - Buying with too little cash shows a Notice and changes nothing.
  - From the command bar, firing `Purchase("FreeMoney")` is ignored.
- [ ] **Step 4:** Commit with `feat: gear and hires shop`.

### Task 12: Story and Act 1 completion

**Files:**
- Create: `src/ReplicatedStorage/Shared/StoryText.luau`, `src/ServerScriptService/Services/ProgressService.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/IntroController.luau`, `src/StarterPlayer/StarterPlayerScripts/Controllers/StoryController.luau`

**Interfaces:**
- Produces:
  - `StoryText`:
    - `INTRO: { string }`: scene lines. It must include the exact line `"That's not coding. That's autocomplete in a hoodie. You've got one month to make rent or you're out."`
    - `SIBLING_TEXTS: { string }`: at least 6 texts, ordered from mocking to grudging, e.g. `"lol it crashed for me"` early and `"...how much did that pay?"` later.
    - `RENT_PAID: { string }`
    - `ACT1_COMPLETE = "Act 1 complete. To be continued."`
  - `ProgressService`:
    - On player loaded with `SeenIntro == false`: `StoryBeat(player, "Intro")`.
    - `IntroSeen` → `SeenIntro = true`.
    - `AssemblyService.OnDeployed` → `StoryBeat(player, "SiblingText", SIBLING_TEXTS[min(DeploysShipped, #SIBLING_TEXTS)])`.
    - **Sibling trigger:**
      - If `Cash >= RENT_GOAL` and not `RentPaid`: `Cash -= RENT_GOAL`, `RentPaid = true`, `StoryFlags.Act1Complete = true`, then `StoryBeat("RentPaid")`.
      - If not enough cash: a Notice with the remaining amount.
      - If rent is already paid: `StoryBeat("Act1Complete")`.
  - `IntroController` plays `StoryBeat("Intro")`: fixed camera on the couch, lines typed out in the terminal style, then a skip/continue button that fires `IntroSeen`.
  - `StoryController` handles `SiblingText` (a phone-text toast) and `RentPaid`/`Act1Complete` (a full-screen card).

- [ ] **Step 1:** Implement the four files.
- [ ] **Step 2:** Verify that build and analyze are clean, and that `lune run tests/run.luau` still passes.
- [ ] **Step 3: Playtest:**
  - A fresh save plays the intro with the exact line, and rejoining doesn't replay it.
  - Each deploy shows a sibling text.
  - Talking to the sibling under 1500 shows the remaining amount.
  - At 1500 or more, rent is paid, cash drops by 1500, and the Act 1 complete card shows. It's still complete after rejoining.
- [ ] **Step 4:** Commit with `feat: intro, sibling texts, act 1 completion`.

### Task 13: Slice verification pass

- [ ] **Step 1:** Run `lune run tests/run.luau`, the full `luau-lsp analyze`, and `rojo build -o game.rbxl`. Expected: all clean.
- [ ] **Step 2: Fresh-save playthrough to rent** (keyboard). Note the time taken. The spec targets Act 1 as roughly one-third of a 2–3 hour run, so if it's under 25 or over 60 minutes, retune `RENT_GOAL`/`TierMultiplier` in `GameConfig` only.
- [ ] **Step 3:** Two-player local server. Expected: separate units, and no cross-unit prompt interference.
- [ ] **Step 4:** Grep `src` for `wait(`, `spawn(`, `delay(`, `pairs(` and `game%.%u` dot indexing. Expected: none outside `task.` calls.
- [ ] **Step 5:** Commit with `chore: act 1 slice verified`.
