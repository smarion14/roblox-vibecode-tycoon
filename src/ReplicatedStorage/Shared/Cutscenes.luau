--!strict
-- Pure: no requires, no Roblox APIs. Cutscene scripts as data, played by CutsceneController in the player's own
-- unit. Shots and actors refer to named markers that each unit layout provides (HOMELAB_MARKERS, OFFICE_MARKERS,
-- CAMPUS_MARKERS).
-- Text comes in through `copy` so this module stays pure; the beats follow the Act 2 design §5.

export type Step = {
	Kind: string, -- "Fade" | "CenterText" | "Shot" | "Actor" | "Animate" | "Prop" | "Line" | "PhoneText" | "NameStartup" | "Title" | "Credits"
	To: string?, -- Fade: "Black" | "Clear"; Shot: optional end marker for a camera move
	From: string?, -- Shot start marker
	Seconds: number?,
	Text: string?,
	Sub: string?,
	Actor: string?, -- "Player" | "Brother"
	Marker: string?,
	Walk: boolean?,
	Seated: boolean?, -- Actor: the marker is a seat surface, so place the rig sitting on it
	Animation: string?,
	Wait: boolean?,
	Prop: string?, -- "LaptopLid" | "CashStack" | "PhoneBuzz" | "NewsTicker" (Text scrolls on the deploy screen) | "Alarm" (red sweep, siren and a camera jolt)
	Action: string?,
	Speaker: string?,
	Focus: string?, -- Line: the actor the camera turns to while the line plays
	Fx: string?, -- Line: how it's delivered, one of LINE_FX
	Lines: { string }?, -- Credits: the rolling lines
}

export type Line = { Speaker: string, Text: string }

export type Copy = {
	RentGoal: number,
	ActGoal: number,
	Act1Intro: { Line },
	Act1End: { Line },
	Act2Text: string,
	BrotherText: string,
	Titles: { Act1: string, Act1Done: string, Act2: string, Act2Done: string, Act3: string },
	Act3Goal: number,
	StartupName: string,
	PlayerName: string,
	Act2Ticker: string, -- "{name}" is replaced by StartupName
	Act3Text: string,
	BrotherTextAct3: string,
	Finale: { Line },
}

local Cutscenes = {}

-- Line deliveries: Shout = camera punch-in and shaking text; Stress = a slow push-in with text that shakes harder
-- until a slam on the last word; Push = a gentle push-in.
Cutscenes.LINE_FX = { Shout = true, Stress = true, Push = true } :: { [string]: boolean }
local ACTORS = { Player = true, Brother = true }

-- Markers each layout must place (invisible parts named Marker_<Name>; cameras look along the part's front).
Cutscenes.HOMELAB_MARKERS = {
	CamWide = true,
	CamCouch = true,
	CamShoulder = true,
	CamFace = true,
	CamDoor = true,
	CouchSeat = true,
	BrotherEnter = true,
	BrotherBehindCouch = true,
	HandoverPlayer = true,
	HandoverBrother = true,
	BrotherDoor = true,
} :: { [string]: boolean }

Cutscenes.OFFICE_MARKERS = {
	CamOutside = true,
	CamInside = true,
	CamDesks = true,
	CamSign = true,
	CamPullBack = true,
	PlayerDoor = true,
	PlayerCenter = true,
} :: { [string]: boolean }

Cutscenes.CAMPUS_MARKERS = {
	CamLobbyWide = true,
	CamLobbyName = true,
	CamAlarm = true,
	CamFinale = true,
	PlayerEntrance = true,
	PlayerLobby = true,
	BrotherEntrance = true,
	BrotherLobby = true,
} :: { [string]: boolean }

local function line(source: Line, focus: string?, fx: string?): Step
	return { Kind = "Line", Speaker = source.Speaker, Text = source.Text, Focus = focus, Fx = fx }
end

local function act1Intro(copy: Copy): { Step }
	return {
		{ Kind = "Actor", Actor = "Player", Marker = "CouchSeat", Seated = true },
		{ Kind = "Animate", Actor = "Player", Animation = "SitCouch" },
		{ Kind = "Fade", To = "Clear", Seconds = 0.8 },
		{ Kind = "Shot", From = "CamWide", To = "CamCouch", Seconds = 3.2 },
		{ Kind = "Shot", From = "CamCouch", Seconds = 1.6 },
		{ Kind = "Actor", Actor = "Brother", Marker = "BrotherEnter" },
		{ Kind = "Actor", Actor = "Brother", Marker = "BrotherBehindCouch", Walk = true, Seconds = 2 },
		{ Kind = "Shot", From = "CamShoulder", Seconds = 1.2 },
		{ Kind = "Animate", Actor = "Brother", Animation = "LaptopClose", Wait = true },
		{ Kind = "Prop", Prop = "LaptopLid", Action = "Close" },
		{ Kind = "Animate", Actor = "Brother", Animation = "Talk" },
		line(copy.Act1Intro[1], "Brother", "Shout"),
		line(copy.Act1Intro[2], "Brother", "Stress"),
		{ Kind = "Actor", Actor = "Brother", Marker = "BrotherEnter", Walk = true, Seconds = 1.6 },
		{ Kind = "Shot", From = "CamFace", Seconds = 1.2 },
		{ Kind = "Title", Text = copy.Titles.Act1, Sub = `Rent: ${copy.RentGoal}` },
	}
end

local function act1End(copy: Copy): { Step }
	return {
		{ Kind = "Actor", Actor = "Player", Marker = "HandoverPlayer" },
		{ Kind = "Actor", Actor = "Brother", Marker = "HandoverBrother" },
		{ Kind = "Fade", To = "Clear", Seconds = 0.6 },
		{ Kind = "Shot", From = "CamDoor", Seconds = 1 },
		{ Kind = "Prop", Prop = "CashStack", Action = "Show" },
		{ Kind = "Animate", Actor = "Player", Animation = "HandOverCash", Wait = true },
		{ Kind = "Animate", Actor = "Brother", Animation = "CountCash", Wait = true },
		{ Kind = "Animate", Actor = "Brother", Animation = "Talk" },
		line(copy.Act1End[1], "Brother", "Push"),
		line(copy.Act1End[2], "Brother", "Shout"),
		{ Kind = "Actor", Actor = "Brother", Marker = "BrotherDoor", Walk = true, Seconds = 2.2 },
		{ Kind = "Animate", Actor = "Brother", Animation = "Talk" },
		line(copy.Act1End[3], "Brother", "Push"),
		{ Kind = "Title", Text = copy.Titles.Act1Done },
		-- Ends black: the server swaps the unit to the office while the screen is dark.
		{ Kind = "Fade", To = "Black", Seconds = 0.8 },
	}
end

local function act2Intro(copy: Copy): { Step }
	return {
		{ Kind = "Fade", To = "Black", Seconds = 0.05 },
		{ Kind = "CenterText", Text = copy.Act2Text, Seconds = 2.4 },
		{ Kind = "Actor", Actor = "Player", Marker = "PlayerDoor" },
		{ Kind = "Shot", From = "CamOutside", Seconds = 0.1 },
		{ Kind = "Fade", To = "Clear", Seconds = 0.8 },
		{ Kind = "Shot", From = "CamOutside", To = "CamInside", Seconds = 2.6 },
		{ Kind = "Actor", Actor = "Player", Marker = "PlayerCenter", Walk = true, Seconds = 3.6 },
		{ Kind = "Shot", From = "CamDesks", Seconds = 1.6 },
		{ Kind = "Prop", Prop = "PhoneBuzz", Action = "Buzz" },
		{ Kind = "PhoneText", Speaker = "Brother", Text = copy.BrotherText },
		{ Kind = "Shot", From = "CamSign", Seconds = 1 },
		{ Kind = "NameStartup" },
		{ Kind = "Title", Text = copy.Titles.Act2, Sub = string.format("Reach valuation x%.2f", copy.ActGoal) },
	}
end

-- 40000 -> "40,000"
local function money(amount: number): string
	local text = tostring(math.floor(amount))
	while true do
		local grouped, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = grouped
		if count == 0 then
			return text
		end
	end
end

-- Plain replace of "{name}" so a startup name containing "%" can't break it.
local function fillName(template: string, name: string): string
	local first, last = string.find(template, "{name}", 1, true)
	if not first then
		return template
	end
	return string.sub(template, 1, first - 1) .. name .. string.sub(template, (last :: number) + 1)
end

local function act2End(copy: Copy): { Step }
	return {
		{ Kind = "Shot", From = "CamDesks", Seconds = 0.8 },
		{ Kind = "Prop", Prop = "PhoneBuzz", Action = "Buzz" },
		{ Kind = "Prop", Prop = "PhoneBuzz", Action = "Buzz" },
		{ Kind = "Prop", Prop = "PhoneBuzz", Action = "Buzz" },
		{ Kind = "Prop", Prop = "NewsTicker", Action = "Show", Text = fillName(copy.Act2Ticker, copy.StartupName) },
		{ Kind = "Shot", From = "CamInside", Seconds = 3.2 },
		{ Kind = "Shot", From = "CamDesks", To = "CamPullBack", Seconds = 3.4 },
		{ Kind = "Title", Text = copy.Titles.Act2Done },
		-- Ends black: the server swaps the unit to the campus while the screen is dark.
		{ Kind = "Fade", To = "Black", Seconds = 0.8 },
	}
end

local function act3Intro(copy: Copy): { Step }
	return {
		{ Kind = "Fade", To = "Black", Seconds = 0.05 },
		{ Kind = "CenterText", Text = copy.Act3Text, Seconds = 2.4 },
		{ Kind = "Actor", Actor = "Player", Marker = "PlayerEntrance" },
		{ Kind = "Shot", From = "CamLobbyWide", Seconds = 0.1 },
		{ Kind = "Fade", To = "Clear", Seconds = 0.8 },
		{ Kind = "Actor", Actor = "Player", Marker = "PlayerLobby", Walk = true, Seconds = 3 },
		{ Kind = "Shot", From = "CamLobbyName", Seconds = 1.6 },
		{ Kind = "Prop", Prop = "PhoneBuzz", Action = "Buzz" },
		{ Kind = "PhoneText", Speaker = "Brother", Text = copy.BrotherTextAct3 },
		{ Kind = "Prop", Prop = "Alarm", Action = "Sweep" },
		{ Kind = "Shot", From = "CamAlarm", Seconds = 2.2 },
		{ Kind = "Title", Text = copy.Titles.Act3, Sub = `Earn ${money(copy.Act3Goal)}` },
	}
end

local function finale(copy: Copy): { Step }
	return {
		{ Kind = "Actor", Actor = "Player", Marker = "PlayerLobby" },
		{ Kind = "Actor", Actor = "Brother", Marker = "BrotherEntrance" },
		{ Kind = "Fade", To = "Clear", Seconds = 0.6 },
		{ Kind = "Shot", From = "CamLobbyWide", To = "CamFinale", Seconds = 3 },
		{ Kind = "Actor", Actor = "Brother", Marker = "BrotherLobby", Walk = true, Seconds = 3 },
		{ Kind = "Animate", Actor = "Brother", Animation = "Talk" },
		line(copy.Finale[1], "Brother", "Push"),
		line(copy.Finale[2], "Brother", "Shout"),
		line(copy.Finale[3], "Brother", "Push"),
		{ Kind = "Title", Text = "THE END" },
		{
			Kind = "Credits",
			Lines = {
				"Vibecoder Startup Tycoon",
				`Founded by {copy.PlayerName}`,
				copy.StartupName,
				"Thanks for playing",
			},
		},
		{ Kind = "Fade", To = "Clear", Seconds = 0.8 },
	}
end

local BUILDERS: { [string]: (Copy) -> { Step } } = {
	Act1Intro = act1Intro,
	Act1End = act1End,
	Act2Intro = act2Intro,
	Act2End = act2End,
	Act3Intro = act3Intro,
	Finale = finale,
}

function Cutscenes.Get(id: string, copy: { [string]: any }): { Step }
	local build = BUILDERS[id]
	assert(build, `unknown cutscene {id}`)
	return build(copy :: any)
end

-- Every marker used exists in the layout, timings are positive, and the scene ends on a title card
-- (trailing credits and fades after the title are allowed).
function Cutscenes.Validate(steps: { Step }, markers: { [string]: boolean }): (boolean, string?)
	for index, step in steps do
		for _, name in { step.From, step.Marker, if step.Kind == "Shot" then step.To else nil } do
			if name and not markers[name] then
				return false, `step {index}: unknown marker {name}`
			end
		end
		if step.Fx and not Cutscenes.LINE_FX[step.Fx] then
			return false, `step {index}: unknown effect {step.Fx}`
		end
		if step.Focus and not ACTORS[step.Focus] then
			return false, `step {index}: unknown focus {step.Focus}`
		end
		if step.Seconds ~= nil and step.Seconds <= 0 then
			return false, `step {index}: Seconds must be positive`
		end
	end
	local lastIndex = #steps
	while lastIndex > 0 and (steps[lastIndex].Kind == "Fade" or steps[lastIndex].Kind == "Credits") do
		lastIndex -= 1
	end
	local last = steps[lastIndex]
	if not last or last.Kind ~= "Title" then
		return false, "cutscene must end on a Title"
	end
	return true, nil
end

return Cutscenes
