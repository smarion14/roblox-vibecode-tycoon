--!strict
-- Story copy. English, generic setting. The doubter is the player's older sibling, a senior engineer.
local StoryText = {}

StoryText.INTRO = {
	"3:07 AM. Your sibling's couch.",
	"Your first AI-built app is one prompt away from shipping.",
	"Your sibling reads your screen over your shoulder. Then closes the laptop.",
	"That's not coding. That's autocomplete in a hoodie. You've got one month to make rent or you're out.",
	"Rent goal is on your screen. Check your phone for work.",
}

-- Sent after each deploy, in order: mocking first, grudging later.
StoryText.SIBLING_TEXTS = {
	"lol it crashed for me",
	"who is paying you for this",
	"why is the button pink. why is it always pink",
	"ok the taco truck site is kind of clean",
	"...how much did that pay?",
	"fine. it works. don't tell anyone i said that",
	"are you eating? you should eat",
}

StoryText.RENT_PAID = {
	"You hand over the rent. Your sibling counts it twice.",
	"\"...Okay. You can stay.\"",
	"\"Don't make it weird.\"",
}

StoryText.ACT1_COMPLETE = "Act 1 complete. To be continued."

-- Act 1 ending cutscene (after paying rent). The last line points to the office for Act 2.
StoryText.ACT1_END = {
	{ Speaker = "Brother", Text = "...Okay. You can stay." },
	{ Speaker = "Brother", Text = "Don't make it weird." },
	{ Speaker = "Brother", Text = "A buddy of mine is subletting a tiny office downtown. First month's free. Take it. Get off my couch." },
} :: { { Speaker: string, Text: string } }

-- Act 1 opening cutscene lines.
StoryText.ACT1_INTRO = {
	{ Speaker = "Brother", Text = "You're STILL doing this garbage? Typing wishes at a robot all night won't get you anywhere!" },
	{ Speaker = "Brother", Text = "One month. I'll give you one month to make rent or you and your little robot pal are sleeping on the curb!" },
} :: { { Speaker: string, Text: string } }

StoryText.ACT2_INTRO_TEXT = "Two weeks later…"
StoryText.BROTHER_TEXT_ACT2 = "don't burn it down"
-- Shown once, right after the Act 2 opening.
StoryText.ACT2_TUTORIAL = {
	{ Title = "Congratulations on getting your own office space!", Body = "No more couch. Here's how running an office works." },
	{ Title = "Buy stuff", Body = "The computer at reception is your shop. Gear and hires are bought there." },
	{ Title = "Hire people", Body = "Each hire sits at a desk and builds their station's parts for you. You can still jump on any station to make a better part." },
	{ Title = "Place furniture", Body = "Press DECORATE to place items in the open area up front. Perks like the coffee machine make your whole team faster." },
	{ Title = "Add decoration", Body = "Plants, lamps, rugs, beanbags and more are just for looks. Rotate, move or sell anything you've placed." },
	{ Title = "Ship it", Body = "Your team builds the parts, but you run every deploy at the meeting-room screen. Hit your valuation goal to finish Act 2." },
} :: { { Title: string, Body: string } }

StoryText.ACT_TITLES = {
	Act1 = "ACT 1: MAKE RENT",
	Act1Done = "ACT 1 COMPLETE",
	Act2 = "ACT 2: MOVE OUT",
}

return StoryText
