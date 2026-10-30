# Act 3: Big Tech — Design

Status: approved in chat, pending document review. Owner decisions are marked *(owner)*; calls the designer made are marked *(designer)* and listed in §14. Builds on the Act 2 rework (`2026-10-30-act2-rework-employees-squad-decor-design.md`), which must land first.

## 1. Intent

The final act. The startup becomes a big tech company, and big tech attracts enemies: hackers probing for holes, vulnerability reports, naysayers piling on. The player keeps shipping deploys, but now also defends the company: handling incidents, hiring key specialists, and building reputation through conferences. Reputation is a flat multiplier on money earned *(owner)*. The act, and the story, end once the company earns a target amount *(owner)*; afterwards the player keeps playing their campus freely *(owner)*.

## 2. Goals, non-goals, anti-goals

**Goals**
- A clear step up in intensity: incidents interrupt the loop, and the deploy battle becomes a Touhou-style bullet hell *(owner)*.
- Key hires that visibly counter specific threats *(owner: cybersecurity, quality assurance, and similar)*.
- Conferences that pay off a well-played keynote with reputation *(owner)*.
- A satisfying finale cutscene, "THE END", then free play.

**Non-goals**
- An Act 4, prestige or reset.
- PvP or players attacking each other.
- Robux purchases tied to incidents or reputation.

**Anti-goals**
- Incidents so frequent that the player never gets to build or decorate.
- A bullet hell that is unfair on phones or for younger players.
- Losing progress because of incidents: incidents cost time and reputation, never cash already earned, parts or hires.

## 3. Constraints

Same as Act 2: `CLAUDE.md` rules, server authority over every incident, minigame result, reputation change, conference grade and battle payout. Cash still only comes from deploys the player plays.

## 4. Story beats and cutscenes

Same in-engine cutscene style as Acts 1–2 (letterbox, scripted camera, campy close-ups, shakes and zooms on the brother's lines).

- **Act 2 ending** (replaces today's "Act 2 complete" card): the valuation goal hits. The phone buzzes non-stop; a news ticker on the office screen reads that the startup just closed a huge funding round. Camera pulls back out of the office. Title: **ACT 2 COMPLETE**. Fade to black.
- **Act 3 opening:** "One year later…" on black. The player walks into a tall glass campus lobby with their startup name in giant letters. The brother texts: "saw you on the news. don't let it go to your head." Then a security alarm blares for the first time, a red light sweeps the room, and the title card lands: **ACT 3: BIG TECH**, subtitle "Earn $40,000".
- **Finale** (when the Act 3 target is reached): the brother visits the campus lobby. He looks around, slowly. Lines *(designer, campy)*:
  1. "...Okay. This is actually impressive."
  2. "I'm still not calling it real coding."
  3. "...Proud of you. Don't make it weird."
  Then "THE END" and a short credits roll (game title, the player's startup name as "Founded by <player>"), then back to free play.
- The same resume rules as today: Story.NextBeat decides what is owed; leaving mid-scene replays it.

## 5. The campus *(owner: only the main office is decoratable)*

- Same 64×64 unit footprint as Act 2, rebuilt as a two-floor glass campus *(designer)*. Units have no ceiling and the megablock has open sky, so the campus simply rises higher (about 32 studs) with no change to the corridor:
  - **Ground floor = the main office:** the same work zone, desks and decorate zone (same size and position as Act 2), so the player's saved decor carries over unchanged. The meeting room becomes the **conference stage** entrance.
  - **Upper floor (stairs plus a quick elevator pad):** the **security desk**, the **QA lab** and the **press room**, each a station-like workstation with a prompt.
- Only the ground-floor decorate zone is editable. The rest of the campus is fixed.
- The night-light rules, the startup sign and employee desks all carry over.

## 6. Incidents *(owner: malicious actors, vulnerability hunters, naysayers; designer: mechanics)*

Incidents show up physically: an alarm sound, a red rotating light in the room that handles it, and a HUD alert with an arrow pointing the way and a countdown.

- One incident at a time on a random timer, every 3–4 minutes *(designer)*. None during a deploy battle, a station minigame, a conference or a cutscene; an incident that would start then waits.
- The player has 90 seconds to deal with each one *(designer)*. If the timer runs out, the consequence applies and the incident ends.

| Incident | Where it's fixed | Minigame | Consequence if ignored |
|---|---|---|---|
| **Breach** (hacker) | Security desk | **Firewall:** tap red packets before they reach the core, let green ones pass (about 20 s) | One station is locked for 2 minutes: no player runs and no employee parts from it. Reputation −5 |
| **Vulnerability report** | QA lab | **Triage:** sort incoming bug reports into Critical / Minor / Not a bug before they stack up (about 20 s) | The next deploy battle gets an extra elite wave. Reputation −5 |
| **Naysayer storm** | Press room | **Clap back:** pick the best of three campy replies to each hostile post, quickly (5 posts) | Reputation drains −1 every 5 s until the storm passes (60 s) |

- Handling an incident well (grade A or S) gives reputation +3; a weak result still clears it with no bonus.

## 7. Key hires (Act 3 only) *(owner: cybersecurity, quality assurance, and similar; designer: effects)*

Bought in the shop once Act 3 starts. Each sits at their upstairs workstation as an employee NPC (friend's avatar, as with other hires).

| Hire | Price | Effect |
|---|---|---|
| Security Engineer | $3,000 | Breaches clear themselves after 30 s if the player hasn't handled them, with no penalty |
| QA Manager | $3,000 | Vulnerability reports only add half an elite wave if ignored, and the triage minigame is shorter |
| PR Lead | $3,500 | Naysayer storms drain half as fast, and clap back needs 3 posts instead of 5 |

## 8. Reputation *(owner: flat multiplier on money)*

- A meter from 0 to 100, starting at 50 when Act 3 begins.
- Multiplier on every deploy payout: `x0.8` at 0 up to `x1.5` at 100, linear *(designer)*. Shown on the HUD next to valuation, for example "REP 62 · x1.23".
- Changes: incidents (§6), conferences (§9). It never drops below 0 or above 100.

## 9. Conferences *(owner: a reputation boost if done properly)*

- Started at the conference stage, any time outside other activities, then on a 10-minute cooldown *(designer)*.
- The keynote is a rhythm-typing performance: the player types short campy slogans on the beat ("SHIP FAST", "AI-NATIVE", "WE'RE HIRING"), while a crowd hype meter rises and falls.
- Graded S/A/B/C on accuracy and timing. Reputation: S +20, A +12, B +6, C +0. A results card shows the grade and the new multiplier.
- A crowd of simple audience NPCs and stage lights make it feel like an event.

## 10. Act 3 deploy battle: bullet hell *(owner)*

Acts 1 and 2 keep their battles. Act 3's deploy battle is a Touhou-style bullet hell.

- **Feel:** high octane and juicy. Dense, colorful, readable bullet patterns; heavy screen shake and hit-stop on big moments; music switch for bosses.
- **Fairness (Roblox's young, mobile-heavy audience):**
  - a tiny visible hitbox
  - a **focus** button (and Shift on keyboard) for slow movement that also shows the hitbox
  - touch: drag anywhere, with the ship offset above the finger
  - **graze:** bullets passing very close fill a meter and add to the combo
  - 3 lives, brief invulnerability after a hit
  - battles last 60–90 seconds
- **Loadout:** the player's station-grade weapons and the four Act 2 wingmen carry over.
- **Bosses are the threats** (one per battle, chosen by the client's contract type):
  - **The Hacker:** fires spiraling green data streams
  - **The Naysayer:** rains slow-falling hate-comment bubbles in walls with gaps
  - **The Swarm:** a vulnerability that splits into smaller bosses
- An ignored vulnerability report adds an elite wave before the boss (§6).
- The battle is simulated on the server like today's, with the client rendering and sending inputs. It reuses Act 2's ship-position streaming and server-checked hits, with a tolerance for latency *(designer)*. Bullet patterns come from a seed both sides share, so the server can check hits without sending every bullet.
- **Scoring and failure** *(designer)*:
  - Lives replace mood. Losing all 3 lives fails the deploy: no payout, the job stays, and the player can try again. Parts and cash already earned are never lost.
  - Score (which feeds the existing payout formula) comes from accuracy, graze count, max combo and lives left.
  - Enemies no longer dive at "your code"; the danger is their bullets.
  - Loadout mapping: Shield absorbs one hit per wave; Rollback is an extra life; Homing makes the player's shots seek.

## 11. Act 3 clients and goal *(designer)*

- Three big-tech contracts unlock by Act 3 deploys (0 / 2 / 4): "Global Payments Platform", "Smart City Dashboard", "Streaming Service Relaunch". New recipes with 7–8 parts each, tiers about x110 to x160.
- **Goal:** earn **$40,000 in deploy payouts during Act 3**. This is a running total of earnings, not the cash balance, so spending on decor and hires never sets the player back. It counts payouts after the reputation multiplier, so good reputation finishes the act sooner. HUD: "GOAL $12,400 / $40,000".
- Valuation keeps growing with every deploy, as in earlier acts, so payouts climb a little through the act.
- Milestones on the way (same banner system as Act 2): first incident handled, first conference, first key hire, halfway.
- At an average grade, a deploy starts at roughly $3,000–3,500 with reputation near x1.1 and climbs with valuation, so about 10–12 deploys reach the goal. That's about an hour including incidents. Tune during playtests.

## 12. After the end (free play) *(owner: keep playing freely)*

- Everything keeps working: deploys, employees, decor, conferences.
- Incidents slow to every 6–8 minutes *(designer)* so free play is relaxed.
- The HUD goal row becomes "LIFETIME EARNINGS $xx,xxx".
- The finale can be rewatched from a "Replay ending" button on the startup sign *(designer)*.

## 13. Save data (additions)

- `Reputation` (0–100), `Act3Earned` (number ≥ 0), `ConferenceReadyAt` (a timestamp), `GameComplete` (via StoryFlags), owned key hires (in the existing Hires set with new ids).
- Active incidents are not saved; they restart on rejoin.
- Existing saves upgrade in place. A player who already saw the old "Act 2 complete" card gets the new Act 2 ending cutscene on their next join, then moves into Act 3.

## 14. Calls made by the designer (not explicitly decided by the owner)

- Story beats and the brother's finale lines; "One year later…".
- Two-floor campus in the same footprint; upstairs security desk, QA lab and press room.
- Incident timing (3–4 min, 90 s to respond, none during other activities), consequences and the three incident minigames.
- Key hire prices and effects.
- Reputation range x0.8–x1.5, start 50, incident and conference amounts.
- Conference cooldown 10 min; rhythm-typing keynote; S/A/B/C rewards.
- Bullet hell details: 3 lives, graze, focus, 60–90 s, the three bosses, server-validated hits with latency tolerance.
- Act 3 clients, $40,000 earnings goal counted as earnings not balance, milestones.
- Free-play incident rate and "Replay ending".
- Campus about 32 studs tall under open sky; no megablock restructuring.
- Bullet hell: lives replace mood, 0 lives fails the deploy (retry, nothing lost), score from accuracy/graze/combo/lives, loadout mapping, shared-seed patterns with server-checked hits.
- Valuation keeps growing; the goal counts payouts after the reputation multiplier.
- Players past the old Act 2 card get the new ending, then Act 3.
