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
	{ Title = "Place furniture", Body = "Press DECORATE to place items anywhere on the office floor, and to move your reception desk. Perks like the coffee machine make your whole team faster." },
	{ Title = "Add decoration", Body = "Plants, lamps, rugs, beanbags and more are just for looks. Rotate, move or sell anything you've placed." },
	{ Title = "Ship it", Body = "Your team builds the parts, but you run every deploy at the meeting-room screen. Hit your valuation goal to finish Act 2." },
} :: { { Title: string, Body: string } }

-- Act 2 ending: {name} is the startup name.
StoryText.ACT2_END_TICKER = "BREAKING: {name} closes record funding round"

StoryText.ACT3_INTRO_TEXT = "One year later…"
StoryText.BROTHER_TEXT_ACT3 = "saw you on the news. don't let it go to your head."

-- Finale cutscene: the brother visits the campus lobby.
StoryText.FINALE = {
	{ Speaker = "Brother", Text = "...Okay. This is actually impressive." },
	{ Speaker = "Brother", Text = "I'm still not calling it real coding." },
	{ Speaker = "Brother", Text = "...Proud of you. Don't make it weird." },
} :: { { Speaker: string, Text: string } }

-- Act 3 incident minigames (Triage / ClapBack). Passed into the pure modules through options.Bank.
StoryText.TRIAGE_REPORTS = {
	{ Text = "Checkout button deletes every customer's cart. Confetti still plays.", Answer = "Critical" },
	{ Text = "Login page accepts any password, including 'password'.", Answer = "Critical" },
	{ Text = "The database backup has been running into a wall since Tuesday.", Answer = "Critical" },
	{ Text = "App crashes on launch for everyone holding a left-handed mouse.", Answer = "Critical" },
	{ Text = "Payments are charged twice, once in dollars and once in vibes.", Answer = "Critical" },
	{ Text = "Logo is two pixels off-center on the loading screen.", Answer = "Minor" },
	{ Text = "Settings page says 'Setings'.", Answer = "Minor" },
	{ Text = "Dark mode is a slightly different dark on Thursdays.", Answer = "Minor" },
	{ Text = "Tooltip appears half a second late and looks a bit smug.", Answer = "Minor" },
	{ Text = "Footer link color is teal when the brand guide says cyan.", Answer = "Minor" },
	{ Text = "User reports the app 'works too fast' and wants a slower mode.", Answer = "NotABug" },
	{ Text = "Customer says the Back button doesn't work. They are pressing Refresh.", Answer = "NotABug" },
	{ Text = "Bug: the office plant is not in the app.", Answer = "NotABug" },
	{ Text = "Report says 'it's broken' with no screenshot, steps, or hope.", Answer = "NotABug" },
	{ Text = "Tester wants the intern's lunch order to appear in the analytics.", Answer = "NotABug" },
} :: { { Text: string, Answer: string } }

-- Best = index of the reply that de-escalates with humor. The other two are too hostile or too robotic.
StoryText.CLAPBACK_POSTS = {
	{
		Post = "your app deleted my homework and also my streak of 3 days",
		Replies = {
			"Skill issue. Next.",
			"Ouch! We restored both and added a small cape to your streak. Thanks for the shout.",
			"Per policy 4.2.1, homework is out of scope. Have a productive day.",
		},
		Best = 2,
	},
	{
		Post = "this startup is just a hoodie with a logo lol",
		Replies = {
			"The hoodie is premium and the logo is vector. We accept your respect.",
			"We have lawyers and also lawyers for the lawyers.",
			"Delete this or we'll mute you.",
		},
		Best = 1,
	},
	{
		Post = "why does the app take 40 seconds to load??",
		Replies = {
			"It builds anticipation. Just kidding, fix incoming, grab a snack while we sprint.",
			"Your internet is the problem. Our internet is perfect.",
			"Loading time is a feature. Please re-read the feature list.",
		},
		Best = 1,
	},
	{
		Post = "updated the app and now it's purple?? I hate purple",
		Replies = {
			"Purple is now mandatory.",
			"Noted! We added a color picker. Retro cyan is one tap away.",
			"Have you tried not hating purple?",
		},
		Best = 2,
	},
	{
		Post = "support never replies. i've waited a whole day",
		Replies = {
			"Our team replied at the speed of light. You were in a tunnel.",
			"A whole day? Ouch. Sorry! We just bumped you to the front of the line and sent snacks.",
			"We are experiencing high volumes of nothing wrong.",
		},
		Best = 2,
	},
	{
		Post = "ur CEO's keynote slides had 47 emojis. cringe",
		Replies = {
			"Forty-eight. You missed the tiny one. We're proud of every single emoji.",
			"Emoji count is confidential.",
			"Bold of you to read slides this carefully and not hire us.",
		},
		Best = 1,
	},
	{
		Post = "bug: the app says 'good morning' at 11 PM",
		Replies = {
			"It's morning somewhere. Probably.",
			"That is not a bug, that is your clock being dramatic.",
			"Fair catch! The app is now a night owl and says 'good evening'. Thanks for the tip.",
		},
		Best = 3,
	},
	{
		Post = "your mascot looks like a toaster in a tie",
		Replies = {
			"He prefers 'executive appliance'. We'll pass along the compliment.",
			"Our mascot has feelings. Please apologize.",
			"Sticks and stones, toaster-hater.",
		},
		Best = 1,
	},
	{
		Post = "Hey, I paid for premium and got ads for premium",
		Replies = {
			"Premium ads are a premium experience.",
			"Whoops, that's on us! Ads are gone and you get a free month. Thank you for flagging it.",
			"Please consult the Terms of Service, page 900.",
		},
		Best = 2,
	},
	{
		Post = "the retro terminal font gives me eye strain",
		Replies = {
			"Eyes get used to greatness.",
			"Maybe try a bigger monitor and a better attitude.",
			"Good point. We added a font size slider and a rest-your-eyes dim mode. Hydrate, friend!",
		},
		Best = 3,
	},
} :: { { Post: string, Replies: { string }, Best: number } }

StoryText.ACT_TITLES = {
	Act1 = "ACT 1: MAKE RENT",
	Act1Done = "ACT 1 COMPLETE",
	Act2 = "ACT 2: MOVE OUT",
	Act2Done = "ACT 2 COMPLETE",
	Act3 = "ACT 3: BIG TECH",
}

return StoryText
