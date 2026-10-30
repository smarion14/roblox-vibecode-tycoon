--!strict
-- Pure: no requires, no Roblox APIs. Server Rack minigame: rotate cable tiles to route a connection from the
-- router (left edge, StartRow) to the server (right edge, EndRow). Grid index = (row - 1) * cols + col.

export type Shape = "Straight" | "Corner"

export type Tile = { Shape: Shape }

export type Puzzle = {
	Cols: number,
	Rows: number,
	StartRow: number,
	EndRow: number,
	Tiles: { Tile },
	Start: { number }, -- scrambled rotations the player starts from
	Solution: { number }, -- one set of rotations that solves it
	PathLength: number,
}

export type TraceResult = { Solved: boolean, Connected: number, Path: { number } } -- Path: tile indices in order

-- Arm bits: N=1, E=2, S=4, W=8. Rotation turns clockwise in 90 degree steps.
local NORTH, EAST, SOUTH, WEST = 1, 2, 4, 8
local BASE_ARMS: { [Shape]: number } = { Straight = NORTH + SOUTH, Corner = NORTH + EAST }
local OPPOSITE: { [number]: number } = { [NORTH] = SOUTH, [EAST] = WEST, [SOUTH] = NORTH, [WEST] = EAST }
local STEP: { [number]: { number } } = { [NORTH] = { 0, -1 }, [EAST] = { 1, 0 }, [SOUTH] = { 0, 1 }, [WEST] = { -1, 0 } }

local SOLVED_BASE = 0.8 -- a solve is always at least a B
local FAST_SHARE = 0.6 -- solving within 40% of the time limit earns full marks
local UNSOLVED_WEIGHT = 0.6

local PatchPanel = {}

function PatchPanel.Arms(shape: Shape, rotation: number): number
	local mask = BASE_ARMS[shape]
	local r = rotation % 4
	return bit32.band(bit32.bor(bit32.lshift(mask, r), bit32.rshift(mask, 4 - r)), 15)
end

local function index(cols: number, col: number, row: number): number
	return (row - 1) * cols + col
end

-- Rotation that turns a shape into exactly the given arm mask (nil if impossible).
local function rotationFor(shape: Shape, mask: number): number?
	for rotation = 0, 3 do
		if PatchPanel.Arms(shape, rotation) == mask then
			return rotation
		end
	end
	return nil
end

function PatchPanel.Generate(cols: number, rows: number, rng: () -> number): Puzzle
	local function randomInt(low: number, high: number): number
		return math.clamp(low + math.floor(rng() * (high - low + 1)), low, high)
	end

	-- Path: in each column run vertically to a random row, then step east. Columns only increase,
	-- so the path never revisits a cell.
	local startRow = randomInt(1, rows)
	local cells: { { number } } = {}
	local row = startRow
	for col = 1, cols do
		local targetRow = randomInt(1, rows)
		table.insert(cells, { col, row })
		while row ~= targetRow do
			row += if targetRow > row then 1 else -1
			table.insert(cells, { col, row })
		end
	end
	local endRow = row

	local tiles: { Tile } = {}
	local solution: { number } = {}
	for i, cell in cells do
		-- Each path cell connects to where it came from and where it goes next.
		local mask = 0
		local previous = cells[i - 1]
		local nextCell = cells[i + 1]
		if previous then
			mask += if previous[1] < cell[1] then WEST elseif previous[2] < cell[2] then NORTH else SOUTH
		else
			mask += WEST -- the router feeds in from the left edge
		end
		if nextCell then
			mask += if nextCell[1] > cell[1] then EAST elseif nextCell[2] > cell[2] then SOUTH else NORTH
		else
			mask += EAST -- out to the server on the right edge
		end
		local shape: Shape = if mask == NORTH + SOUTH or mask == EAST + WEST then "Straight" else "Corner"
		local at = index(cols, cell[1], cell[2])
		tiles[at] = { Shape = shape }
		solution[at] = rotationFor(shape, mask) :: number
	end

	-- Filler tiles are decoys with random shapes.
	for at = 1, cols * rows do
		if not tiles[at] then
			tiles[at] = { Shape = if rng() < 0.5 then "Straight" else "Corner" }
			solution[at] = randomInt(0, 3)
		end
	end

	local puzzle: Puzzle = {
		Cols = cols,
		Rows = rows,
		StartRow = startRow,
		EndRow = endRow,
		Tiles = tiles,
		Start = {},
		Solution = solution,
		PathLength = #cells,
	}

	for at = 1, cols * rows do
		puzzle.Start[at] = randomInt(0, 3)
	end
	-- Never hand out a puzzle that is already solved: twist the first path tile if it is.
	if PatchPanel.Trace(puzzle, puzzle.Start).Solved then
		local first = index(cols, 1, startRow)
		puzzle.Start[first] = (puzzle.Start[first] + 1) % 4
		if PatchPanel.Trace(puzzle, puzzle.Start).Solved then
			puzzle.Start[first] = (puzzle.Start[first] + 1) % 4
		end
	end
	return puzzle
end

-- Follows the cable from the router. Connected counts tiles reached in order; Solved when it exits to the server.
function PatchPanel.Trace(puzzle: Puzzle, rotations: { number }): TraceResult
	local col, row = 1, puzzle.StartRow
	local entering = WEST
	local connected = 0
	local path: { number } = {}
	for _ = 1, puzzle.Cols * puzzle.Rows do
		local at = index(puzzle.Cols, col, row)
		local tile = puzzle.Tiles[at]
		local rotation = rotations[at]
		if not tile or type(rotation) ~= "number" then
			break
		end
		local arms = PatchPanel.Arms(tile.Shape, rotation)
		if bit32.band(arms, entering) == 0 then
			break
		end
		connected += 1
		table.insert(path, at)
		local exit = arms - entering
		if col == puzzle.Cols and row == puzzle.EndRow and exit == EAST then
			return { Solved = true, Connected = connected, Path = path }
		end
		local step = STEP[exit]
		if not step then
			break
		end
		col += step[1]
		row += step[2]
		if col < 1 or col > puzzle.Cols or row < 1 or row > puzzle.Rows then
			break
		end
		entering = OPPOSITE[exit]
	end
	return { Solved = false, Connected = connected, Path = path }
end

-- 0-1 score: solves earn 0.8-1 depending on speed; unsolved boards earn partial credit for the cable laid.
function PatchPanel.Score(solved: boolean, elapsed: number, timeLimit: number, connected: number, pathLength: number): number
	if solved then
		local speed = math.clamp((timeLimit - elapsed) / (timeLimit * FAST_SHARE), 0, 1)
		return SOLVED_BASE + (1 - SOLVED_BASE) * speed
	end
	return UNSOLVED_WEIGHT * math.clamp(connected / math.max(pathLength, 1), 0, 1)
end

return PatchPanel
