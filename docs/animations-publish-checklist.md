# Publishing the cutscene and employee animations

The game ships with six hand-authored R15 animations: `LaptopClose`, `HandOverCash`, `CountCash`, `Talk`, `SitCouch` and `DeskType`. Their keyframes live in `tools/animations/data.luau`. Running `lune run tools/animations/build.luau` turns them into `KeyframeSequence` files in `src/ServerStorage/Animations/`, and Rojo syncs those into Studio.

Roblox only plays an animation after it has been published to an asset ID owned by the experience's owner (you, or your group). Until an ID is filled in, `GameConfig.ANIMATIONS.<Name>` stays `0`. With `0`, the cutscenes fall back to Roblox's default sit and idle animations, or play no animation.

## Steps

1. Open the place in Studio with Rojo connected (`rojo serve`, then Connect in the Rojo plugin).
2. In Explorer, open **ServerStorage → Animations**.
3. Right-click each `KeyframeSequence` and choose **Save to Roblox** (in newer Studio builds, **Publish to Roblox**). Publish as the experience owner, or as its group if the experience belongs to a group.
4. Copy the asset ID that Studio shows after publishing.
5. Paste it into `src/ReplicatedStorage/Shared/GameConfig.luau` under `GameConfig.ANIMATIONS.<Name>`, replacing the `0`.
6. Play the game and replay the cutscenes to check each animation. On a test save, the Act 1 opening uses `SitCouch` and `LaptopClose`; the Act 1 ending uses `HandOverCash`, `CountCash` and `Talk`; employees in the office use `DeskType`.

## Tweaking a pose

The poses are a first pass. If an arm swings the wrong way, either:
- edit the degrees in `tools/animations/data.luau`, rerun the build, and publish again; or
- open the `KeyframeSequence` in Studio's Animation Editor, adjust it there, and publish from the editor.

Republishing gives a new asset ID, so update `GameConfig.ANIMATIONS` each time.
