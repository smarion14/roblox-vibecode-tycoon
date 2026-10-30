--!strict
-- Player-facing typing content. English, generic setting, lowercase ascii only.
-- Prompts and boss phrases must never contain a bug word as a whole word.
local PromptBank = {}

PromptBank.BURST_PROMPTS = {
	FrontendUnits = {
		"make the navbar sticky on scroll",
		"add a dark mode toggle to the header",
		"center the hero image on mobile",
		"give the buttons rounded corners",
		"show a spinner while the page loads",
		"make the footer links bigger",
		"add a contact form with an email field",
		"use a bold font for every heading",
		"put the logo in the top left corner",
		"fade in the cards when they appear",
	},
	BackendEndpoints = {
		"add an endpoint that lists all orders",
		"return a friendly error when login fails",
		"send a welcome email after signup",
		"limit each user to ten requests a second",
		"add a health check route for the server",
		"save uploaded photos to cloud storage",
		"cache the menu for five minutes",
		"log every payment with a timestamp",
		"add a route to cancel a booking",
		"validate the phone number on signup",
	},
	DatabaseTables = {
		"create a table for customer bookings",
		"add an index on the email column",
		"store prices as whole cents",
		"keep a history of every order change",
		"add a created at column to each table",
		"link each pet to its owner",
		"delete expired sessions every night",
		"make usernames unique in the users table",
		"back up the database every hour",
		"add a table for gift card balances",
	},
	PromptTokens = {
		"write a cheerful welcome message",
		"summarize each review in one sentence",
		"suggest three names for a new menu item",
		"reply to support emails in a calm tone",
		"turn this price list into a short poem",
		"write alt text for every product photo",
		"translate the menu into plain words",
		"draft a thank you note for new customers",
		"pick an emoji for each food category",
		"explain the refund policy simply",
	},
} :: { [string]: { string } }

-- Boss bugs: a phrase typed word by word in the deploy battle. Words must never be bug words.
PromptBank.BOSS_PHRASES = {
	"memory overflow in production",
	"infinite render storm",
	"database deadlock at midnight",
	"payment gateway timeout",
	"corrupted session cache",
	"unhandled promise rejection",
	"broken login redirect chain",
	"rogue scheduled job",
}

PromptBank.BUG_WORDS = {
	"null",
	"cors",
	"race",
	"typo",
	"leak",
	"loop",
	"crash",
	"lag",
	"panic",
	"stack",
	"hang",
	"nan",
	"drift",
	"fault",
	"oops",
	"segv",
}

return PromptBank
