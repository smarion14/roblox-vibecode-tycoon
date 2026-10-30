# Act 2 Rework: Employees at Work, Squad Galaga, Office Decorating — Design

Status: approved in chat, pending document review. Owner decisions are marked *(owner)*; calls the designer made are marked *(designer)* and listed in §11.

## 1. Intent

Act 2 is long on purpose (about 20–30 deploys). Playing four station minigames by hand for every deploy goes stale long before the act ends, and Act 3 will need the player's attention for incidents and conferences. So Act 2 is where the player stops doing everything and starts running a team: hired employees build parts on their own, the deploy battle grows a squad, and the office becomes the player's own space to decorate.

The skill moments stay with the player. Cash only ever comes from a deploy battle the player plays *(owner: keep the "no passive income" rule in CLAUDE.md)*.

## 2. Goals, non-goals, anti-goals

**Goals**
- Hired employees build their station's parts automatically, visibly, at their desks.
- Office perks (coffee machine, lounge couch, arcade cabinet) make employees better.
- Players decorate a roomy part of the office with cosmetic and cozy items, saved and carried into Act 3.
- The Act 2 deploy battle feels different from Act 1's: wingmen, client-specific enemies, and bosses that fire simple bullet patterns as a warm-up for Act 3's bullet hell.

**Non-goals**
- Act 3 (separate design: `2026-10-30-act3-big-tech-design.md`).
- Changing Act 1's stations, battle or homelab.
- Monetized (Robux) decor. Decor is bought with in-game cash.

**Anti-goals**
- Idle play: nothing produces cash without the player finishing a deploy battle.
- Decor that can block a station, a desk, a chair or the walkways to them.
- An office so tight that any decoration looks cluttered.

## 3. Constraints

All project rules in `CLAUDE.md` apply: Luau `--!strict`, `task` library, no `pairs`/`ipairs`, `GetService` at the top, server-authoritative state, English generic setting, the cyberpunk/vaporwave look. Every purchase, placement and part grant is validated on the server.

## 4. Employees at work *(owner, numbers designer)*

- A hired employee builds their station's parts at their desk in real time.
  - One part about every 25 seconds per employee *(designer)*.
  - Employee parts are grade B.
  - They only build what the active job still needs for their component, then stop. With no active job, they idle (the typing animation pauses).
- Visible work: the employee plays `DeskType`; their desk monitor shows a progress bar filling over the build time; when a part lands, a small pop and sound play at the desk and the HUD recipe count updates.
- The player can still play any station. A player run still follows "upgrade, don't add": once the job's need is met, a better grade replaces the worst copy. So going for S stays worthwhile.
- Unhired stations stay manual. Hiring all four makes parts fully hands-off; the player still chooses jobs and plays every deploy battle.
- The old hire effect (pre-filling grade C parts when a job is accepted) is removed.
- Timing is server-driven: the server ticks each owner's employees and grants parts; the client only shows progress.

## 5. Office perks *(owner: capped at one each)*

Perks are office items with an effect on all employees. Each can be owned and placed once.

| Perk | Price *(designer)* | Effect |
|---|---|---|
| Coffee machine | $400 | Employees build 20% faster |
| Lounge couch | $650 | Each employee part has a 15% chance to be grade A instead of B |
| Arcade cabinet | $900 | Employees build 10% faster |

- Effects stack across different perks (coffee plus arcade = 30% faster). They apply only while the perk is placed in the office.
- Perks are bought in the office shop (§7) and placed like decor.

## 6. Squad Galaga (Act 2 deploy battle) *(owner, weapon list designer)*

Act 1's Galaga is unchanged. In Act 2:

- **Wingmen:** each hired employee flies as a small wingman ship beside the player's ship, firing their role weapon automatically:
  - Frontend: a 3-way spread shot
  - Backend: a piercing beam that hits every enemy in a column
  - Database: a shield that absorbs one hit on the player, recharging after 8 s *(designer)*
  - Prompt/AI: homing missiles
- **Client-specific enemies** (on top of the regular waves):
  - Mobile app jobs (PocketFit, BrewCrew): crash reports that split into two smaller enemies when shot
  - Game studio jobs (PixelForge): lag spikes that briefly slow the player's ship when they reach it
- **Bosses fire light bullet patterns:** slow, readable spreads (a fan of 5–7 bullets every few seconds). They are dodgeable, never dense; they teach dodging before Act 3.
- The existing station loadout (the player's own weapons from part grades), combos, results screen and payout stay as they are. The existing `ACT_BATTLE[2]` tuning stays.
- The battle is still simulated on the server; wingmen and new enemy types are part of the server battle state, not client decoration.
- **Ship position and hits** *(designer)*: Act 2 is where the ship first gets a hitbox. The client streams its ship position to the server about 10 times a second; the server clamps impossible moves and checks boss bullets and lag spikes against that position, with a small tolerance for latency. A bullet hit costs the same mood as a bug reaching your code. This position-streaming layer is built once here and reused by Act 3.
- **Kills:** the existing "client claims a kill, server checks it was possible" model is extended to wingman shots, piercing beams, homing missiles and splitting enemies (the server knows each weapon's reach and rate).
- The Database wingman's shield stacks with the loadout Shield from part grades: each absorbs its own hit.

## 7. Office decorating *(owner)*

### 7.1 Space *(owner: spacious; designer: numbers)*

- Every unit grows from 44×44 to **64×64 studs**, the homelab included, so the megablock floor layout scales with it.
- The Act 2 office splits into:
  - a **work zone** along the back: four stations, with the four employee desks in front of them, fixed;
  - the **meeting room** in a back corner (deploy wall screen);
  - an open **decorate zone** across the front half, about 28×24 studs of empty floor.
- Reception (shop computer, phone) and the startup sign stay by the door, outside the decorate zone.
- Nothing can be placed outside the decorate zone, and the decorate zone never overlaps a station, desk, chair, prompt or walkway.

### 7.2 Decorate mode

- A "Decorate" button on the HUD, only in Act 2 and later and only inside the player's own unit.
- In decorate mode the camera goes top-down over the decorate zone, which shows as a grid. 1 cell = 2×2 studs *(designer)*.
- Controls: pick an item from the shop panel, a ghost preview follows the cursor or finger snapped to the grid; tap/click to place; R or a button to rotate 90°; Move; Sell (50% refund); Done.
- The server validates every placement: the item is owned, it is inside the decorate zone, it doesn't overlap another item, the rotation is a multiple of 90°.
- Works with mouse, touch and gamepad.

### 7.3 Catalog *(designer, including the cozy set the owner asked for)*

Perks (one each): coffee machine, lounge couch, arcade cabinet (§5).

Decor (looks only, buy as many as you like):

| Item | Footprint (cells) | Price |
|---|---|---|
| Potted plant | 1×1 | $60 |
| Rug | 3×2 | $90 |
| Floor lamp (warm) | 1×1 | $120 |
| Neon sign | 2×1 | $150 |
| Poster frame | 1×1 (wall-height stand) | $80 |
| Beanbag | 1×1 | $110 |
| Bookshelf | 2×1 | $200 |
| String-light arch | 2×1 | $180 |
| Fairy-light plant | 1×1 | $140 |
| Cat bed (with sleeping cat) | 1×1 | $250 |
| Side table with mug | 1×1 | $90 |

- All items are built from code (parts and built-in materials), like the rest of the world, in the same palette. Cozy items lean warm: amber lights, soft fabrics.
- Lights on decor follow the night-only rule for building lights where they are lamps or neon.

### 7.4 Saving

- The layout is saved per player: a list of `{ ItemId, Cell X, Cell Z, Rotation }` plus owned counts.
- It is loaded and built whenever the office is built.
- It carries into Act 3: the campus's main office has the same decorate zone size and position (Act 3 design).

## 8. Economy

- Perks and decor are cash sinks for Acts 2–3. The rest of Act 2's economy is unchanged: valuation goal +1.5, milestones, client unlocks.
- The FIRST HIRE milestone keeps working. Hires keep their current prices.

## 9. Save data (additions)

- `Decor`: list of placed items `{ ItemId, X, Z, Rotation }` (validated: known item, inside the zone, no overlaps, at most 200 items *(designer)*).
- `DecorOwned`: counts per decor item; perks as a set (max one each).
- Employee build progress is not saved; it restarts on rejoin.

## 10. Existing saves *(designer)*

- Saves upgrade in place; nobody's progress is reset. New fields get defaults on load.
- Hires already owned simply start working at their desks; the old C-part pre-fill is gone.
- Units growing to 64×64 rebuilds every layout, homelab included. Act 1 mechanics don't change, only the room size.

## 11. Left to the builder

- Exact geometry of the 64×64 office layout within the zones above, and resizing the homelab to fill the larger unit.
- The ghost preview look, grid rendering and decorate-mode camera details.
- Wingman ship art and the new enemy art (code-built, matching the existing battle style).
- Sounds, choosing from the existing licensed set or the Creator Store's licensed catalog.

## 12. Calls made by the designer (not explicitly decided by the owner)

- Employee build time 25 s per part, grade B.
- Perk prices and numbers: coffee +20% speed $400, lounge 15% grade A $650, arcade +10% speed $900.
- Wingman weapons: spread / piercing beam / shield (8 s recharge) / homing.
- Units grow to 64×64 for everyone; decorate zone about 28×24 studs; grid cell 2×2 studs.
- Decor catalog items and prices; 50% sell-back; 200-item cap.
- Employee progress isn't saved across sessions.
- Ship position streamed at about 10 Hz, server-checked hits; a bullet hit costs the same mood as a landed bug; the extended kill-claim model; the Database shield stacks with the loadout Shield.
- Saves upgrade in place with defaults; no reset.
