extends RefCounted
## Accuracy corpus for the PrivacyEngine scanner.
##
## Each entry:
##   text         - a realistic line of game UI
##   should_match - whether the scanner must flag it
##   pack         - which pattern pack is responsible ("" for negatives)
##   secret       - the exact substring that should be masked, when the whole
##                  line is not private. Used by the sub-rect precision test.
##
## Negatives deliberately include strings that look code-like: player names with
## digits, version strings, clock times, scores, wave counters, achievements and
## chat that uses the word "room" conversationally.

const ENTRIES := [
	# --- lobby_codes: true positives ---------------------------------
	{"text": "Room: GAME-2231", "should_match": true, "pack": "lobby_codes", "secret": "GAME-2231"},
	{"text": "Lobby code: XP4829", "should_match": true, "pack": "lobby_codes", "secret": "XP4829"},
	{"text": "Join code ABC-1234", "should_match": true, "pack": "lobby_codes", "secret": "ABC-1234"},
	{"text": "SESSION KX7Q-22F1", "should_match": true, "pack": "lobby_codes", "secret": "KX7Q-22F1"},
	{"text": "Party code: bright-otter-42", "should_match": true, "pack": "lobby_codes", "secret": "bright-otter-42"},
	{"text": "Room 4512", "should_match": true, "pack": "lobby_codes", "secret": "4512"},
	{"text": "Invite: zQ4t9x", "should_match": true, "pack": "lobby_codes", "secret": "zQ4t9x"},
	{"text": "Your lobby: HHJ-882", "should_match": true, "pack": "lobby_codes", "secret": "HHJ-882"},
	{"text": "Match ID: PL-99213", "should_match": true, "pack": "lobby_codes", "secret": "PL-99213"},
	{"text": "Arena code TT9021", "should_match": true, "pack": "lobby_codes", "secret": "TT9021"},

	# --- network: true positives -------------------------------------
	{"text": "Server 192.168.1.1:7777", "should_match": true, "pack": "network", "secret": "192.168.1.1:7777"},
	{"text": "Connect to 10.0.0.5", "should_match": true, "pack": "network", "secret": "10.0.0.5"},
	{"text": "Relay 203.0.113.42:27015", "should_match": true, "pack": "network", "secret": "203.0.113.42:27015"},
	{"text": "discord.gg/xK9pQ2", "should_match": true, "pack": "network", "secret": "discord.gg/xK9pQ2"},
	{"text": "https://discord.gg/aBcD1234", "should_match": true, "pack": "network", "secret": "https://discord.gg/aBcD1234"},
	{"text": "Host: 2001:0db8:85a3:0000:0000:8a2e:0370:7334", "should_match": true, "pack": "network", "secret": "2001:0db8:85a3:0000:0000:8a2e:0370:7334"},
	{"text": "IPv6 fe80::1ff:fe23:4567:890a", "should_match": true, "pack": "network", "secret": "fe80::1ff:fe23:4567:890a"},
	{"text": "Endpoint [2001:db8::1]:8080", "should_match": true, "pack": "network", "secret": "[2001:db8::1]:8080"},
	{"text": "STEAM_0:1:12345678", "should_match": true, "pack": "network", "secret": "STEAM_0:1:12345678"},
	{"text": "Friend code: 445566778", "should_match": true, "pack": "network", "secret": "445566778"},
	{"text": "Port: 27015", "should_match": true, "pack": "network", "secret": "27015"},
	{"text": "Server ip 172.16.254.1", "should_match": true, "pack": "network", "secret": "172.16.254.1"},

	# --- contact: true positives (opt-in pack) -----------------------
	{"text": "Contact: player@email.com", "should_match": true, "pack": "contact", "secret": "player@email.com"},
	{"text": "email me at shadow.gamer+tag@gmail.com", "should_match": true, "pack": "contact", "secret": "shadow.gamer+tag@gmail.com"},
	{"text": "Call 555-123-4567", "should_match": true, "pack": "contact", "secret": "555-123-4567"},
	{"text": "Phone +44 20 7946 0958", "should_match": true, "pack": "contact", "secret": "+44 20 7946 0958"},

	# --- identifiers: true positives (opt-in pack) -------------------
	{"text": "Session 3f2504e0-4f89-11d3-9a0c-0305e82c3301", "should_match": true, "pack": "identifiers", "secret": "3f2504e0-4f89-11d3-9a0c-0305e82c3301"},
	# "12345-KLMNO" is itself code-shaped, so lobby_codes catches part of this
	# line even with the identifiers pack off. Masking part of a license key is
	# the right outcome, so this overlap is declared rather than patched out.
	{"text": "Key: ABCDE-FGHIJ-12345-KLMNO", "should_match": true, "pack": "identifiers", "secret": "ABCDE-FGHIJ-12345-KLMNO", "default_overlap": true},
	{"text": "auth 9f8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b", "should_match": true, "pack": "identifiers", "secret": "9f8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b"},
	{"text": "token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQabcdefgh", "should_match": true, "pack": "identifiers", "secret": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQabcdefgh"},

	# --- mixed lines: only part of the line is private ----------------
	{"text": "Player: xXx_Shadow_xXx  |  Room: GAME-2231", "should_match": true, "pack": "lobby_codes", "secret": "GAME-2231"},
	{"text": "MATCH SERVER   203.0.113.42:7777", "should_match": true, "pack": "network", "secret": "203.0.113.42:7777"},
	{"text": "Squad: Alpha  -  Invite: pk39Zt", "should_match": true, "pack": "lobby_codes", "secret": "pk39Zt"},
	{"text": "Host 10.0.0.7  ping 22ms", "should_match": true, "pack": "network", "secret": "10.0.0.7"},

	# --- true negatives: code-like but harmless ----------------------
	{"text": "Sh4dow99", "should_match": false, "pack": "", "secret": ""},
	{"text": "xX_DarkLord_Xx", "should_match": false, "pack": "", "secret": ""},
	{"text": "v2.4.1", "should_match": false, "pack": "", "secret": ""},
	{"text": "Build 2024.11.03", "should_match": false, "pack": "", "secret": ""},
	{"text": "12:34:56", "should_match": false, "pack": "", "secret": ""},
	{"text": "Next wave in 0:30", "should_match": false, "pack": "", "secret": ""},
	{"text": "00 SHARDS", "should_match": false, "pack": "", "secret": ""},
	{"text": "Wave 12", "should_match": false, "pack": "", "secret": ""},
	{"text": "Level 42", "should_match": false, "pack": "", "secret": ""},
	{"text": "Score: 1250", "should_match": false, "pack": "", "secret": ""},
	{"text": "HP 100/100", "should_match": false, "pack": "", "secret": ""},
	{"text": "Ping 42ms", "should_match": false, "pack": "", "secret": ""},
	{"text": "1920x1080", "should_match": false, "pack": "", "secret": ""},
	{"text": "Loading... 45%", "should_match": false, "pack": "", "secret": ""},
	{"text": "this room is huge!", "should_match": false, "pack": "", "secret": ""},
	{"text": "nice room design here", "should_match": false, "pack": "", "secret": ""},
	{"text": "anyone else in this lobby yet", "should_match": false, "pack": "", "secret": ""},
	{"text": "FIRST BLOOD", "should_match": false, "pack": "", "secret": ""},
	{"text": "FIRST-BLOOD", "should_match": false, "pack": "", "secret": ""},
	{"text": "Achievement unlocked: Speed Demon", "should_match": false, "pack": "", "secret": ""},
	{"text": "Press F to pay respects", "should_match": false, "pack": "", "secret": ""},
	{"text": "Welcome to the arena, Shadow!", "should_match": false, "pack": "", "secret": ""},
	{"text": "GG WP everyone", "should_match": false, "pack": "", "secret": ""},
	{"text": "Team A vs Team B", "should_match": false, "pack": "", "secret": ""},
	{"text": "x2 damage boost", "should_match": false, "pack": "", "secret": ""},
	{"text": "Rank #4512", "should_match": false, "pack": "", "secret": ""},
	{"text": "W A S D  /  ARROWS   Move and collect shards", "should_match": false, "pack": "", "secret": ""},
	{"text": "Mode enabled - integrated features active", "should_match": false, "pack": "", "secret": ""},
]


## Entries whose pack is off unless the host opts in.
const OPT_IN_PACKS := ["contact", "identifiers"]
