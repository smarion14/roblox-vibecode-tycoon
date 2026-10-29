# Vibecoder Startup Tycoon - Project Context & Rules

## Tech Stack & Language
- Environment: Roblox Game Engine (Rojo-managed)
- Language: Luau (Strict Mode: `--!strict` required at the top of every file)
- Paradigm: Client-Server Authoritative architecture with decoupled modules

## Core Project Commands
- Sync Project: `rojo serve`
- Build Place: `rojo build -o "game.rbxl"`
- Code Quality: `luau-lsp analyze`

## Project Directory Map
- `src/ServerScriptService/` -> Authoritative player states, financial transactions, database handlers, and deployment evaluation engines.
- `src/ReplicatedStorage/` -> Shared configuration definitions, network Remote validation managers, and cross-boundary utility scripts.
- `src/StarterPlayer/StarterPlayerScripts/` -> Client interaction event listeners, screen animation controllers, and tactical mini-game UI engines.

## Coding Conventions & Guardrails
- **Service Retrieval:** Always use `game:GetService("ServiceName")` at the absolute top of files. Never use direct dot index notation (e.g., `game.Workspace`).
- **Threading & Delays:** Use the modern `task` library (`task.wait()`, `task.spawn()`, `task.delay()`). The global legacy `wait()`, `spawn()`, or `delay()` functions are strictly banned.
- **Loops & Collections:** Utilize modern generalized iteration for all sequential and dictionary lookups (e.g., `for key, value in targetTable do`) instead of wrapping structures in `pairs()` or `ipairs()`.
- **Typing Style:** Explicitly type-hint function arguments, return metrics, custom dictionaries, and state objects to eliminate implicit runtime execution errors.
- **Naming Cadence:** Use `PascalCase` for Services, Component Classes, and Module variables. Use `camelCase` for internal function states and local references. Use `LOUD_SNAKE_CASE` for immutable static configurations.

## Game Design & Architecture Constraints
- **Subversion of "Slop":** No glowing green button pads or static passive collection bins. Progress must be earned through physical workstation interactions and tactical UI deployment battles.
- **Atmospheric Aesthetic:** Gritty, atmospheric cyberpunk/vaporwave office environment. Mechanics must emphasize clicky keyboard acoustics, glowing retro terminal displays, and moody lighting matrices.
- **Language & Setting:** All player-facing text is English. The setting is generic and not tied to any real country or region: no Philippine (or other regional) names, slang, brands, or locales.
- **Client Hostility:** Trust absolutely nothing originating from the client. All wallet modifications, state adjustments, component collection triggers, and deployment calculations must be authorized, verified, and processed safely on the Server.
