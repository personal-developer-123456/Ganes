--[[
	GOLD RUSH CASINO  -  FAKE coins only (never touches Robux or the game's economy)
	Layout: header (game name + difficulty, X)  |  left: menu button + stats  |  divider  |  right: game
	Tap the 3 lines to open the menu: games, history, leaderboard, settings.
	Games: Slots, Coinflip, Dice  |  PC + mobile  |  Balance saves across every game
	Made for Arceus X Neo. Edit CONFIG below to change bets, odds and sounds.
]]

local CONFIG = {
	START_BALANCE = 1000,
	MIN_BET = 10,                       -- no max bet (only your balance limits you)
	SAVE_FILE = "GoldRushCasino.json",  -- same file in every game = balance carries over
	COINFLIP_PAYOUT = 1.95,             -- total returned on a win (2.5% house edge)
	DICE_RTP = 98,                      -- dice pays 98 / win-chance (2% house edge)
	SLOT_PAIR = 1,                      -- any pair gives your bet back
	SLOT_TRIPLE = { ["🍒"] = 4, ["🍋"] = 8, ["🔔"] = 15, ["⭐"] = 30, ["💎"] = 75, ["7"] = 200 },
	SOUNDS = { -- if silent in your executor, swap these for other sound ids
		click = "rbxasset://sounds/clickfast.wav",
		spin = "rbxasset://sounds/switch.wav",
		win = "rbxasset://sounds/victory.wav",
		lose = "rbxasset://sounds/uuhhh.wav",
	},
}
-- {symbol, weight}; every symbol needs an entry in SLOT_TRIPLE
local SYMBOLS = { {"🍒", 28}, {"🍋", 24}, {"🔔", 20}, {"⭐", 14}, {"💎", 9}, {"7", 5} }

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local C = {
	bg = Color3.fromRGB(12, 12, 14), panel = Color3.fromRGB(26, 26, 30), panel2 = Color3.fromRGB(40, 40, 46),
	gold = Color3.fromRGB(255, 200, 50), goldDark = Color3.fromRGB(160, 120, 20),
	text = Color3.fromRGB(240, 240, 240), dim = Color3.fromRGB(150, 150, 156),
	green = Color3.fromRGB(70, 210, 110), red = Color3.fromRGB(235, 70, 70), orange = Color3.fromRGB(255, 140, 50),
}
local alive, busy = true, false
local LEFT = Enum.TextXAlignment.Left
local ES, ED = Enum.EasingStyle, Enum.EasingDirection

-- ===== helpers =====
local function tw(obj, t, props, es, ed)
	local tween = TweenService:Create(obj, TweenInfo.new(t, es or ES.Quint, ed or ED.Out), props)
	tween:Play()
	return tween
end
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function round(o, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function stroke(o, col, th)
	return make("UIStroke", { Color = col, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function label(text, parent, size, pos, ts, col, font, xa)
	return make("TextLabel", { Text = text, Size = size, Position = pos or UDim2.new(), BackgroundTransparency = 1,
		TextColor3 = col or C.text, TextSize = ts or 14, Font = font or Enum.Font.GothamBold,
		TextXAlignment = xa or Enum.TextXAlignment.Center }, parent)
end
-- every button gets smooth hover + press animations
local function button(text, parent, size, pos, bg, fg)
	local b = make("TextButton", { Text = text, Size = size, Position = pos or UDim2.new(), BackgroundColor3 = bg or C.panel2,
		TextColor3 = fg or C.text, Font = Enum.Font.GothamBold, TextSize = 14, BorderSizePixel = 0, AutoButtonColor = false }, parent)
	round(b, 8)
	local sc = make("UIScale", {}, b)
	b.MouseEnter:Connect(function() tw(sc, 0.18, { Scale = 1.04 }) end)
	b.MouseLeave:Connect(function() tw(sc, 0.25, { Scale = 1 }) end)
	b.MouseButton1Down:Connect(function() tw(sc, 0.08, { Scale = 0.92 }, ES.Quad) end)
	b.MouseButton1Up:Connect(function() tw(sc, 0.35, { Scale = 1 }, ES.Back) end)
	return b
end
local function flat(text, parent, pos, hoverCol)
	local b = button(text, parent, UDim2.new(0, 34, 0, 30), pos, C.bg, C.dim)
	b.BackgroundTransparency = 1; b.TextSize = 20
	b.MouseEnter:Connect(function() tw(b, 0.15, { TextColor3 = hoverCol }) end)
	b.MouseLeave:Connect(function() tw(b, 0.25, { TextColor3 = C.dim }) end)
	return b
end
local function style(btn, on)
	tw(btn, 0.25, { BackgroundColor3 = on and C.gold or C.panel2, TextColor3 = on and C.bg or C.text })
end
local function fmt(n)
	local s = string.format("%.0f", math.abs(n))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if r:sub(1, 1) == "," then r = r:sub(2) end
	return (n < 0 and "-" or "") .. r
end
local function signed(n) return (n > 0 and "+" or n < 0 and "-" or "") .. fmt(math.abs(n)) end
local function rich(n)
	local col = n > 0 and "#46d26e" or n < 0 and "#eb4646" or "#c8c8c8"
	return '<font color="' .. col .. '">' .. signed(n) .. '</font>'
end

local totalWeight = 0
for _, s in ipairs(SYMBOLS) do totalWeight = totalWeight + s[2] end
local function pickSymbol()
	local r, acc = math.random(1, totalWeight), 0
	for _, s in ipairs(SYMBOLS) do
		acc = acc + s[2]
		if r <= acc then return s[1] end
	end
	return SYMBOLS[1][1]
end
local function randomSymbol() return SYMBOLS[math.random(#SYMBOLS)][1] end
local function slotRTP()
	local rtp = 0
	for _, s in ipairs(SYMBOLS) do
		local p = s[2] / totalWeight
		rtp = rtp + p ^ 3 * CONFIG.SLOT_TRIPLE[s[1]] + 3 * p ^ 2 * (1 - p) * CONFIG.SLOT_PAIR
	end
	return rtp * 100
end

-- ===== state, saving, sounds =====
local state = { balance = CONFIG.START_BALANCE, sound = true }
local S = { rounds = 0, wagered = 0, net = 0, wins = 0, losses = 0, pushes = 0, bigWin = 0, streak = 0, bestStreak = 0,
	games = { Slots = { rounds = 0, net = 0 }, Coinflip = { rounds = 0, net = 0 }, Dice = { rounds = 0, net = 0 } } }
local history = {}

local canSave = (writefile ~= nil and readfile ~= nil and isfile ~= nil)
local function saveData()
	if not canSave then return end
	pcall(function() writefile(CONFIG.SAVE_FILE, HttpService:JSONEncode({ balance = state.balance, sound = state.sound })) end)
end
local function loadData()
	if not canSave then return end
	pcall(function()
		if isfile(CONFIG.SAVE_FILE) then
			local d = HttpService:JSONDecode(readfile(CONFIG.SAVE_FILE))
			if type(d.balance) == "number" and d.balance == d.balance and d.balance >= 0 then state.balance = math.floor(d.balance) end
			if type(d.sound) == "boolean" then state.sound = d.sound end
		end
	end)
end
loadData()

for _, s in ipairs(SoundService:GetChildren()) do if s.Name == "GoldRushSfx" then s:Destroy() end end
local sfx = {}
for name, id in pairs(CONFIG.SOUNDS) do
	pcall(function() sfx[name] = make("Sound", { Name = "GoldRushSfx", SoundId = id, Volume = 0.6 }, SoundService) end)
end
local function play(name)
	if state.sound and sfx[name] then pcall(function() sfx[name]:Play() end) end
end

-- ===== GUI =====
-- remove an older copy if you run the script twice
local spots = { LocalPlayer:FindFirstChildOfClass("PlayerGui"), CoreGui }
if gethui then pcall(function() table.insert(spots, gethui()) end) end
for _, sp in pairs(spots) do
	pcall(function() local o = sp:FindFirstChild("GoldRushCasino"); if o then o:Destroy() end end)
end

local gui = make("ScreenGui", { Name = "GoldRushCasino", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local mounted = false
if gethui then mounted = pcall(function() gui.Parent = gethui() end) and gui.Parent ~= nil end
if not mounted then mounted = pcall(function() gui.Parent = CoreGui end) and gui.Parent ~= nil end
if not mounted then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local main = make("Frame", { Name = "Main", Size = UDim2.new(0, 512, 0, 304), Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true }, gui)
round(main, 14)
local mainStroke = stroke(main, C.gold, 2)
local uiScale = make("UIScale", { Scale = 0.6 }, main)
local fit = 1                                              -- screen-fit scale
local popVal = make("NumberValue", { Value = 0.6 }, gui)  -- open / close / minimize pop
popVal.Changed:Connect(function() uiScale.Scale = fit * popVal.Value end)

local mini = button("$", gui, UDim2.new(0, 0, 0, 0), UDim2.new(0, 36, 0.5, 0), C.gold, C.bg)
mini.AnchorPoint = Vector2.new(0.5, 0.5); mini.TextSize = 28; mini.Visible = false

-- HEADER: game name + difficulty, minimize + X
local top = make("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Active = true }, main)
local titleLbl = label("", top, UDim2.new(1, -130, 0, 24), UDim2.new(0, 16, 0, 5), 17, C.gold, Enum.Font.GothamBlack, LEFT)
local subLbl = label("", top, UDim2.new(1, -130, 0, 14), UDim2.new(0, 16, 0, 28), 11, C.dim, Enum.Font.Gotham, LEFT)
subLbl.RichText = true
local minBtn = flat("-", top, UDim2.new(1, -80, 0, 8), C.gold)
local closeBtn = flat("X", top, UDim2.new(1, -42, 0, 8), C.red)
local headLine = make("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 0, 46), BackgroundColor3 = C.goldDark, BorderSizePixel = 0 }, main)
local vLine = make("Frame", { Size = UDim2.new(0, 2, 0, 256), Position = UDim2.new(0, 126, 0, 48), BackgroundColor3 = C.goldDark, BorderSizePixel = 0 }, main)

-- LEFT: 3-line menu button + stats
local side = make("Frame", { Size = UDim2.new(0, 126, 0, 256), Position = UDim2.new(0, 0, 0, 48), BackgroundTransparency = 1 }, main)
local menuBtn = button("", side, UDim2.new(0, 40, 0, 34), UDim2.new(0, 12, 0, 10))
local bars = {}
for i = 1, 3 do
	bars[i] = make("Frame", { Size = UDim2.new(0, 20, 0, 3), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 9 + (i - 1) * 8), BackgroundColor3 = C.gold, BorderSizePixel = 0 }, menuBtn)
	round(bars[i], 2)
end
label("STATS", side, UDim2.new(1, -20, 0, 20), UDim2.new(0, 14, 0, 56), 16, C.gold, Enum.Font.GothamBlack, LEFT)
label("COINS", side, UDim2.new(1, -20, 0, 12), UDim2.new(0, 14, 0, 80), 10, C.dim, Enum.Font.Gotham, LEFT)
local balLabel = label("", side, UDim2.new(0, 104, 0, 24), UDim2.new(0, 14, 0, 92), 20, C.gold, Enum.Font.GothamBlack, LEFT)
balLabel.TextScaled = true
make("UITextSizeConstraint", { MaxTextSize = 20 }, balLabel)
local balScale = make("UIScale", {}, balLabel)
local sideStats = label("", side, UDim2.new(0, 108, 0, 124), UDim2.new(0, 14, 0, 124), 12, C.text, Enum.Font.Gotham, LEFT)
sideStats.RichText = true; sideStats.TextYAlignment = Enum.TextYAlignment.Top; sideStats.LineHeight = 1.2

-- RIGHT: game area (menu / games / history / leaderboard / settings)
local body = make("Frame", { Size = UDim2.new(0, 356, 0, 234), Position = UDim2.new(0, 140, 0, 58), BackgroundTransparency = 1 }, main)
local PAGES = { "Menu", "Slots", "Coinflip", "Dice", "History", "Leaderboard", "Settings" }
local GAME_PAGES = { Slots = true, Coinflip = true, Dice = true }
local pages = {}
for _, name in ipairs(PAGES) do
	pages[name] = make("CanvasGroup", { Name = name, Size = GAME_PAGES[name] and UDim2.new(1, 0, 0, 150) or UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, body)
end

-- MENU page: game cards + other pages
label("GAMES", pages.Menu, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 0), 12, C.gold, Enum.Font.GothamBold, LEFT)
label("MORE", pages.Menu, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 122), 12, C.gold, Enum.Font.GothamBold, LEFT)
local function cardText(icon, name, sub)
	return '<font size="28">' .. icon .. '</font>\n<b>' .. name .. '</b>\n<font size="11" color="#9a9aa0">' .. sub .. '</font>'
end
local CARDS = {
	{ "Slots", "🎰", "SLOTS", "Hard  |  up to " .. CONFIG.SLOT_TRIPLE["7"] .. "x" },
	{ "Coinflip", "💰", "COINFLIP", "Easy  |  " .. CONFIG.COINFLIP_PAYOUT .. "x" },
	{ "Dice", "🎲", "DICE", "Your risk  |  up to " .. string.format("%.1f", CONFIG.DICE_RTP / 5) .. "x" },
}
local MENU_ORDER = { "Slots", "Coinflip", "Dice", "History", "Leaderboard", "Settings" }
local menuTargets, menuBase = {}, {}
for i, c in ipairs(CARDS) do
	local b = button("", pages.Menu, UDim2.new(0, 112, 0, 92), UDim2.new(0, (i - 1) * 122, 0, 20), C.panel2)
	b.RichText = true; b.Text = cardText(c[2], c[3], c[4]); b.TextSize = 15
	stroke(b, C.goldDark, 1)
	menuTargets[c[1]] = b; menuBase[c[1]] = b.Position
end
for i, n in ipairs({ { "History", "HISTORY" }, { "Leaderboard", "LEADERBOARD" }, { "Settings", "SETTINGS" } }) do
	local b = button(n[2], pages.Menu, UDim2.new(0, 112, 0, 40), UDim2.new(0, (i - 1) * 122, 0, 142), C.panel2, C.gold)
	b.TextSize = 12
	menuTargets[n[1]] = b; menuBase[n[1]] = b.Position
end

-- SLOTS page (reels slide vertically)
local reels = {}
local startSyms = { "🍒", "🍋", "🔔" }
for i = 1, 3 do
	local box = make("Frame", { Size = UDim2.new(0, 80, 0, 70), Position = UDim2.new(0.5, -130 + (i - 1) * 90, 0, 0),
		BackgroundColor3 = C.panel2, ClipsDescendants = true }, pages.Slots)
	round(box, 10)
	local st = stroke(box, C.goldDark, 2)
	local function sym(pos, text)
		return make("TextLabel", { Size = UDim2.new(1, 0, 1, 0), Position = pos, BackgroundTransparency = 1, Text = text,
			TextSize = 42, Font = Enum.Font.GothamBold, TextColor3 = C.gold }, box)
	end
	reels[i] = { a = sym(UDim2.new(0, 0, 0, 0), startSyms[i]), b = sym(UDim2.new(0, 0, -1, 0), ""), stroke = st }
end
local payParts = {}
for _, s in ipairs(SYMBOLS) do payParts[#payParts + 1] = s[1] .. " x" .. CONFIG.SLOT_TRIPLE[s[1]] end
local payLbl = label(table.concat(payParts, "   ") .. "\nthree of a kind pays the multiplier  |  any pair = bet back",
	pages.Slots, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 76), 11, C.dim, Enum.Font.Gotham)
payLbl.TextWrapped = true
local spinBtn = button("SPIN", pages.Slots, UDim2.new(0, 220, 0, 36), UDim2.new(0.5, -110, 0, 112), C.gold, C.bg)
spinBtn.TextSize = 18

-- COINFLIP page
local COIN_REST = UDim2.new(0.5, 0, 0, 8)
local coin = make("TextLabel", { Size = UDim2.new(0, 64, 0, 64), AnchorPoint = Vector2.new(0.5, 0), Position = COIN_REST,
	BackgroundColor3 = C.gold, Text = "H", TextColor3 = C.bg, Font = Enum.Font.GothamBlack, TextSize = 32 }, pages.Coinflip)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, coin)
stroke(coin, C.goldDark, 3)
local headsBtn = button("HEADS", pages.Coinflip, UDim2.new(0, 110, 0, 30), UDim2.new(0.5, -116, 0, 78))
local tailsBtn = button("TAILS", pages.Coinflip, UDim2.new(0, 110, 0, 30), UDim2.new(0.5, 6, 0, 78))
local flipBtn = button("FLIP  (pays " .. CONFIG.COINFLIP_PAYOUT .. "x)", pages.Coinflip, UDim2.new(0, 220, 0, 36), UDim2.new(0.5, -110, 0, 114), C.gold, C.bg)
flipBtn.TextSize = 17

-- DICE page
local diceNum = label("--", pages.Dice, UDim2.new(0, 160, 0, 44), UDim2.new(0.5, -80, 0, 0), 36, C.gold, Enum.Font.GothamBlack)
local underBtn = button("UNDER", pages.Dice, UDim2.new(0, 100, 0, 26), UDim2.new(0.5, -106, 0, 46))
local overBtn = button("OVER", pages.Dice, UDim2.new(0, 100, 0, 26), UDim2.new(0.5, 6, 0, 46))
local m5Btn = button("-5", pages.Dice, UDim2.new(0, 40, 0, 26), UDim2.new(0.5, -157, 0, 76))
local m1Btn = button("-1", pages.Dice, UDim2.new(0, 40, 0, 26), UDim2.new(0.5, -111, 0, 76))
local diceTarget = label("", pages.Dice, UDim2.new(0, 130, 0, 26), UDim2.new(0.5, -65, 0, 76), 13, C.text)
local p1Btn = button("+1", pages.Dice, UDim2.new(0, 40, 0, 26), UDim2.new(0.5, 71, 0, 76))
local p5Btn = button("+5", pages.Dice, UDim2.new(0, 40, 0, 26), UDim2.new(0.5, 117, 0, 76))
local diceInfoLbl = label("", pages.Dice, UDim2.new(1, 0, 0, 14), UDim2.new(0, 0, 0, 106), 12, C.dim, Enum.Font.Gotham)
local rollBtn = button("ROLL", pages.Dice, UDim2.new(0, 220, 0, 28), UDim2.new(0.5, -110, 0, 122), C.gold, C.bg)
rollBtn.TextSize = 18

-- HISTORY page
local histScroll = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.panel, BorderSizePixel = 0,
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, pages.History)
round(histScroll, 8)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, histScroll)
make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4) }, histScroll)

-- LEADERBOARD page (session stats)
local statsLabel = label("", pages.Leaderboard, UDim2.new(1, 0, 0, 108), UDim2.new(0, 0, 0, 0), 14, C.text, Enum.Font.Gotham, LEFT)
statsLabel.RichText = true; statsLabel.TextYAlignment = Enum.TextYAlignment.Top
label("GAME RANKING (net profit)", pages.Leaderboard, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 114), 13, C.gold, Enum.Font.GothamBold, LEFT)
local leaderLabel = label("", pages.Leaderboard, UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0, 134), 14, C.text, Enum.Font.Gotham, LEFT)
leaderLabel.RichText = true; leaderLabel.TextYAlignment = Enum.TextYAlignment.Top

-- SETTINGS page
local resetBtn = button("RESET BALANCE", pages.Settings, UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 0), C.red)
local soundBtn = button("", pages.Settings, UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 48))
label(canSave and ("Auto-save ON  (" .. CONFIG.SAVE_FILE .. ")") or "Auto-save not supported here: balance resets each run",
	pages.Settings, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 100), 12, C.dim, Enum.Font.Gotham, LEFT)
label("Min bet " .. CONFIG.MIN_BET .. "  |  no max bet  |  fake coins only", pages.Settings,
	UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 118), 12, C.dim, Enum.Font.Gotham, LEFT)

-- status strip + bet bar (game pages only)
local statusLabel = label("", body, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 154), 12, C.dim, Enum.Font.GothamBold)
statusLabel.Visible = false
local BET_Y = 176
local betBar = make("CanvasGroup", { Size = UDim2.new(1, 0, 0, 58), Position = UDim2.new(0, 0, 0, BET_Y + 10),
	BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, body)
label("BET", betBar, UDim2.new(0, 30, 0, 28), UDim2.new(0, 0, 0, 0), 13, C.gold)
local betBox = make("TextBox", { Size = UDim2.new(0, 120, 0, 28), Position = UDim2.new(0, 34, 0, 0), BackgroundColor3 = C.panel2,
	TextColor3 = C.gold, PlaceholderText = "Bet amount", PlaceholderColor3 = C.dim, Text = tostring(CONFIG.MIN_BET),
	Font = Enum.Font.GothamBold, TextSize = 15, ClearTextOnFocus = false, BorderSizePixel = 0 }, betBar)
round(betBox, 8)
local betStroke = stroke(betBox, C.goldDark, 1)
local halfBtn = button("1/2", betBar, UDim2.new(0, 50, 0, 28), UDim2.new(0, 160, 0, 0))
local dblBtn = button("2x", betBar, UDim2.new(0, 50, 0, 28), UDim2.new(0, 216, 0, 0))
local allBtn = button("ALL IN", betBar, UDim2.new(0, 84, 0, 28), UDim2.new(0, 272, 0, 0), C.red)
local CHIPS = { { "+10", 10 }, { "+100", 100 }, { "+1K", 1000 }, { "+10K", 10000 }, { "MIN", 0 } }
local chipBtns = {}
for i, ch in ipairs(CHIPS) do
	chipBtns[i] = button(ch[1], betBar, UDim2.new(0, 66, 0, 28), UDim2.new(0, (i - 1) * 72, 0, 30), C.panel2, C.gold)
end

-- ===== logic =====
local diceMode, diceChance, coinPick = "under", 50, "H"
local currentPage, lastGame = "Menu", "Slots"

local function notify(text, color)
	statusLabel.Text = text; statusLabel.TextColor3 = color or C.dim
	statusLabel.TextTransparency = 0.8
	tw(statusLabel, 0.3, { TextTransparency = 0 })
end

local DIFF = { Easy = "#46d26e", Medium = "#ffc832", Hard = "#ff8c32", Extreme = "#eb4646" }
local function diff(level) return 'Difficulty: <font color="' .. DIFF[level] .. '">' .. level .. '</font>' end
local function diceDifficulty()
	return diceChance >= 60 and "Easy" or diceChance >= 35 and "Medium" or diceChance >= 15 and "Hard" or "Extreme"
end
local function headerFor(name)
	if name == "Slots" then return "SLOTS", diff("Hard") .. string.format("  |  RTP %.1f%%", slotRTP()) end
	if name == "Coinflip" then return "COINFLIP", diff("Easy") .. "  |  50/50, pays " .. CONFIG.COINFLIP_PAYOUT .. "x" end
	if name == "Dice" then return "DICE", diff(diceDifficulty()) .. "  |  " .. diceChance .. "% win chance" end
	if name == "History" then return "HISTORY", "Your last 50 bets" end
	if name == "Leaderboard" then return "LEADERBOARD", "Your stats this session" end
	if name == "Settings" then return "SETTINGS", "Balance, sound and saving" end
	return "GOLD RUSH CASINO", "Pick a game to start"
end
local function updateHeader(animate)
	local t, s = headerFor(currentPage)
	if animate and titleLbl.Text ~= t then
		tw(titleLbl, 0.12, { TextTransparency = 1, Position = UDim2.new(0, 6, 0, 5) }, ES.Quad, ED.In)
		tw(subLbl, 0.12, { TextTransparency = 1, Position = UDim2.new(0, 6, 0, 28) }, ES.Quad, ED.In)
		task.delay(0.13, function()
			local t2, s2 = headerFor(currentPage)
			titleLbl.Text = t2; subLbl.Text = s2
			titleLbl.Position = UDim2.new(0, 28, 0, 5); subLbl.Position = UDim2.new(0, 28, 0, 28)
			tw(titleLbl, 0.4, { TextTransparency = 0, Position = UDim2.new(0, 16, 0, 5) })
			tw(subLbl, 0.5, { TextTransparency = 0, Position = UDim2.new(0, 16, 0, 28) })
		end)
	else
		titleLbl.Text = t; subLbl.Text = s
	end
end

-- balance counts up/down smoothly
local balShown = make("NumberValue", { Value = state.balance }, gui)
balShown.Changed:Connect(function(v) balLabel.Text = fmt(math.floor(v + 0.5)) end)
balLabel.Text = fmt(state.balance)
local function refreshBalance(flash)
	tw(balShown, 0.7, { Value = state.balance }, ES.Quad)
	if flash then
		balLabel.TextColor3 = flash
		tw(balLabel, 0.9, { TextColor3 = C.gold })
		tw(balScale, 0.18, { Scale = 1.14 }, ES.Quad).Completed:Connect(function() tw(balScale, 0.35, { Scale = 1 }, ES.Back) end)
	end
end

local function refreshHistory(animateTop)
	for _, ch in ipairs(histScroll:GetChildren()) do if ch:IsA("TextLabel") then ch:Destroy() end end
	if #history == 0 then
		label("No bets yet - go play!", histScroll, UDim2.new(1, -8, 0, 22), nil, 12, C.dim, Enum.Font.Gotham, LEFT)
		return
	end
	for i, h in ipairs(history) do
		local t = label(h.game .. "  |  bet " .. fmt(h.bet) .. "  |  " .. signed(h.profit) .. "  |  " .. h.detail, histScroll,
			UDim2.new(1, -8, 0, 22), nil, 12, h.profit > 0 and C.green or (h.profit < 0 and C.red or C.dim), Enum.Font.Gotham, LEFT)
		t.LayoutOrder = i
		t.TextTruncate = Enum.TextTruncate.AtEnd
		if i == 1 and animateTop then t.TextTransparency = 1; tw(t, 0.5, { TextTransparency = 0 }) end
	end
end

local function refreshStats()
	local winRate = S.rounds > 0 and (S.wins / S.rounds * 100) or 0
	sideStats.Text = string.format("Net  %s\nRounds  %d\nWin rate  %.1f%%\nStreak  %d (best %d)\nBest win  %s\nWagered  %s",
		rich(S.net), S.rounds, winRate, S.streak, S.bestStreak, fmt(S.bigWin), fmt(S.wagered))
	sideStats.TextTransparency = 0.7; tw(sideStats, 0.5, { TextTransparency = 0 })
	statsLabel.Text = string.format("Net profit:  %s\nRounds:  %d   (W %d / L %d / Push %d)\nWin rate:  %.1f%%\nTotal wagered:  %s\nBiggest win:  %s\nBest win streak:  %d",
		rich(S.net), S.rounds, S.wins, S.losses, S.pushes, winRate, fmt(S.wagered), fmt(S.bigWin), S.bestStreak)
	local list = {}
	for name, g in pairs(S.games) do list[#list + 1] = { name = name, net = g.net, rounds = g.rounds } end
	table.sort(list, function(a, b) return a.net > b.net end)
	local lines = {}
	for i, g in ipairs(list) do lines[#lines + 1] = string.format("%d. %s   %s   (%d rounds)", i, g.name, rich(g.net), g.rounds) end
	leaderLabel.Text = table.concat(lines, "\n")
end

local function diceInfo()
	diceTarget.Text = diceMode == "under" and ("Roll " .. diceChance .. " or less") or ("Roll over " .. (100 - diceChance))
	diceInfoLbl.Text = string.format("Win chance %d%%   |   Pays %.2fx", diceChance, CONFIG.DICE_RTP / diceChance)
	if currentPage == "Dice" then updateHeader(false) end
end

-- 3 lines <-> back arrow
local function setMenuActive(on)
	tw(menuBtn, 0.3, { BackgroundColor3 = on and C.gold or C.panel2 })
	for i = 1, 3 do tw(bars[i], 0.3, { BackgroundColor3 = on and C.bg or C.gold }) end
	tw(bars[1], 0.4, { Size = UDim2.new(0, on and 11 or 20, 0, 3), Position = UDim2.new(0.5, on and -5 or 0, 0, on and 13 or 9), Rotation = on and -45 or 0 }, ES.Back)
	tw(bars[2], 0.4, { Size = UDim2.new(0, on and 18 or 20, 0, 3) }, ES.Back)
	tw(bars[3], 0.4, { Size = UDim2.new(0, on and 11 or 20, 0, 3), Position = UDim2.new(0.5, on and -5 or 0, 0, on and 21 or 25), Rotation = on and 45 or 0 }, ES.Back)
end

local function animateMenuIn()
	for i, name in ipairs(MENU_ORDER) do
		local b, base = menuTargets[name], menuBase[name]
		local st = b:FindFirstChildOfClass("UIStroke")
		b.Position = base + UDim2.new(0, 0, 0, 16)
		b.BackgroundTransparency = 1; b.TextTransparency = 1
		if st then st.Transparency = 1 end
		task.delay(0.1 + i * 0.05, function()
			if currentPage ~= "Menu" then return end
			tw(b, 0.45, { Position = base, BackgroundTransparency = 0, TextTransparency = 0 }, ES.Back)
			if st then tw(st, 0.4, { Transparency = 0 }) end
		end)
	end
end

local function showPage(name)
	if name == currentPage and pages[name].Visible then return end
	currentPage = name
	if GAME_PAGES[name] then lastGame = name end
	-- old page slides/fades out
	for n, p in pairs(pages) do
		if n ~= name and p.Visible then
			tw(p, 0.16, { GroupTransparency = 1, Position = UDim2.new(0, -16, 0, 0) }, ES.Quad, ED.In)
			task.delay(0.17, function() if currentPage ~= n then p.Visible = false end end)
		end
	end
	-- new page slides/fades in
	local pg = pages[name]
	pg.Position = UDim2.new(0, 20, 0, 0); pg.GroupTransparency = 1; pg.Visible = true
	task.delay(0.1, function()
		if currentPage == name then tw(pg, 0.4, { GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0) }) end
	end)
	-- bet bar + status slide in for games, out for everything else
	if GAME_PAGES[name] then
		if not betBar.Visible then betBar.GroupTransparency = 1; betBar.Position = UDim2.new(0, 0, 0, BET_Y + 10); betBar.Visible = true end
		statusLabel.Visible = true
		tw(betBar, 0.45, { GroupTransparency = 0, Position = UDim2.new(0, 0, 0, BET_Y) })
		tw(statusLabel, 0.3, { TextTransparency = 0 })
	else
		tw(betBar, 0.16, { GroupTransparency = 1, Position = UDim2.new(0, 0, 0, BET_Y + 10) }, ES.Quad, ED.In)
		tw(statusLabel, 0.16, { TextTransparency = 1 })
		task.delay(0.17, function()
			if not GAME_PAGES[currentPage] then betBar.Visible = false; statusLabel.Visible = false end
		end)
	end
	setMenuActive(name == "Menu")
	updateHeader(true)
	if name == "Menu" then animateMenuIn() end
	if name == "History" then refreshHistory(false) elseif name == "Leaderboard" then refreshStats() end
end

local function shake(obj)
	local base = obj.Position
	for _, dx in ipairs({ 6, -6, 4, -3, 0 }) do
		tw(obj, 0.045, { Position = base + UDim2.new(0, dx, 0, 0) }, ES.Sine)
		task.wait(0.045)
	end
end

local function winFx(amount)
	play("win")
	local banner = label("+" .. fmt(amount), main, UDim2.new(0, 300, 0, 50), UDim2.new(0.5, -150, 0.42, 0), 8, C.gold, Enum.Font.GothamBlack)
	banner.ZIndex = 20; banner.TextStrokeTransparency = 0
	tw(banner, 0.45, { TextSize = 38 }, ES.Back)
	tw(mainStroke, 0.2, { Thickness = 6 }, ES.Quad).Completed:Connect(function() tw(mainStroke, 0.5, { Thickness = 2 }) end)
	for _ = 1, 16 do
		local p = make("Frame", { Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0.5, -5, 0.45, 0), BackgroundColor3 = C.gold, BorderSizePixel = 0, ZIndex = 19 }, main)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
		tw(p, 0.9, { Position = UDim2.new(0.5, math.random(-230, 230), 0.45, math.random(-130, 90)), BackgroundTransparency = 1, Size = UDim2.new(0, 4, 0, 4) }, ES.Quad)
		task.delay(1, function() p:Destroy() end)
	end
	task.delay(1.2, function()
		if not alive then return end
		tw(banner, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.new(0.5, -150, 0.3, 0) }, ES.Quad)
		task.wait(0.6)
		banner:Destroy()
	end)
end

local function setBusy(on)
	busy = on
	for _, b in ipairs({ spinBtn, flipBtn, rollBtn }) do
		tw(b, 0.25, { BackgroundTransparency = on and 0.6 or 0, TextTransparency = on and 0.5 or 0 })
	end
end

local function settle(gname, bet, payout, detail)
	local profit = payout - bet
	state.balance = state.balance + payout
	S.rounds = S.rounds + 1; S.wagered = S.wagered + bet; S.net = S.net + profit
	if profit > 0 then
		S.wins = S.wins + 1; S.streak = S.streak + 1
		if S.streak > S.bestStreak then S.bestStreak = S.streak end
		if profit > S.bigWin then S.bigWin = profit end
	elseif profit < 0 then
		S.losses = S.losses + 1; S.streak = 0
	else
		S.pushes = S.pushes + 1
	end
	local g = S.games[gname]
	g.rounds = g.rounds + 1; g.net = g.net + profit
	table.insert(history, 1, { game = gname, bet = bet, profit = profit, detail = detail })
	if #history > 50 then table.remove(history) end
	saveData()
	if not alive then return end
	refreshBalance(profit > 0 and C.green or (profit < 0 and C.red or C.gold))
	refreshHistory(true); refreshStats()
	if profit > 0 then
		notify("YOU WON " .. fmt(profit) .. "!  (" .. detail .. ")", C.green); winFx(profit)
	elseif profit == 0 then
		notify("Push - bet returned  (" .. detail .. ")", C.gold)
	else
		notify("Lost " .. fmt(-profit) .. "  (" .. detail .. ")", C.red); play("lose")
		task.spawn(shake, body)
	end
end

local function takeBet()
	if busy then notify("Round in progress...", C.dim) return nil end
	if state.balance < CONFIG.MIN_BET then notify("Out of coins! Menu > Settings > Reset balance.", C.red) return nil end
	local n = tonumber((betBox.Text:gsub(",", "")))
	if not n or n ~= n then notify("Enter a valid bet.", C.red) return nil end
	n = math.floor(n)
	if n < CONFIG.MIN_BET then notify("Minimum bet is " .. CONFIG.MIN_BET .. ".", C.red) return nil end
	if n > state.balance then notify("Not enough coins.", C.red) return nil end
	setBusy(true)
	state.balance = state.balance - n
	saveData(); refreshBalance(C.red); play("click")
	return n
end

local function startRound(gname, fn)
	local bet = takeBet()
	if not bet then return end
	local ok, payout, detail = pcall(fn, bet)
	if not ok then payout, detail = bet, "error - refunded" end
	settle(gname, bet, payout, detail)
	setBusy(false)
end

-- one reel tick: the visible symbol slides down, a new one slides in from the top
local function reelStep(i, sym, dur, es)
	local r = reels[i]
	r.b.Text = sym; r.b.Position = UDim2.new(0, 0, -1, 0)
	tw(r.a, dur, { Position = UDim2.new(0, 0, 1, 0) }, es, ED.Out)
	tw(r.b, dur, { Position = UDim2.new(0, 0, 0, 0) }, es, ED.Out)
	r.a, r.b = r.b, r.a
end

local function playSlots(bet)
	local final = { pickSymbol(), pickSymbol(), pickSymbol() }
	for i = 1, 3 do tw(reels[i].stroke, 0.2, { Color = C.goldDark, Thickness = 2 }) end
	notify("Spinning...", C.gold); play("spin")
	local stopAt, done, t0 = { 0.8, 1.2, 1.6 }, { false, false, false }, os.clock()
	while alive and not (done[1] and done[2] and done[3]) do
		local el = os.clock() - t0
		for i = 1, 3 do
			if not done[i] then
				if el >= stopAt[i] then
					done[i] = true; reelStep(i, final[i], 0.3, ES.Back); play("click")
				else
					reelStep(i, randomSymbol(), 0.075, ES.Linear)
				end
			end
		end
		task.wait(0.08)
	end
	task.wait(0.32)
	local a, b, c = final[1], final[2], final[3]
	local payout, detail = 0, a .. b .. c .. " no match"
	if a == b and b == c then
		payout = math.floor(bet * CONFIG.SLOT_TRIPLE[a] + 0.5); detail = a .. b .. c .. " triple"
	elseif a == b or b == c or a == c then
		payout = bet * CONFIG.SLOT_PAIR; detail = a .. b .. c .. " pair"
	end
	if alive and payout > bet then
		for i = 1, 3 do
			tw(reels[i].stroke, 0.3, { Color = C.green, Thickness = 5 }, ES.Back)
			task.delay(0.8, function() tw(reels[i].stroke, 0.5, { Thickness = 2 }) end)
		end
	end
	return payout, detail
end

local function playFlip(bet)
	local pick = coinPick
	notify("Flipping...", C.gold); play("spin")
	tw(coin, 0.55, { Position = UDim2.new(0.5, 0, 0, 0) }, ES.Quad, ED.Out)
	task.delay(0.55, function() tw(coin, 0.55, { Position = COIN_REST }, ES.Bounce, ED.Out) end)
	for i = 1, 6 do
		if not alive then break end
		tw(coin, 0.09, { Size = UDim2.new(0, 4, 0, 64) }, ES.Sine, ED.In)
		task.wait(0.09)
		coin.Text = (i % 2 == 0) and "H" or "T"
		tw(coin, 0.09, { Size = UDim2.new(0, 64, 0, 64) }, ES.Sine, ED.Out)
		task.wait(0.09)
	end
	local res = math.random(2) == 1 and "H" or "T"
	local win = (res == pick)
	coin.Size = UDim2.new(0, 64, 0, 64); coin.Text = res
	task.wait(0.1)
	if alive then
		tw(coin, 0.3, { BackgroundColor3 = win and C.green or C.red })
		task.delay(1, function() tw(coin, 0.5, { BackgroundColor3 = C.gold }) end)
	end
	local payout = win and math.floor(bet * CONFIG.COINFLIP_PAYOUT + 0.5) or 0
	return payout, (res == "H" and "heads" or "tails") .. (win and " - win" or " - loss")
end

local function playDice(bet)
	local mode, chance = diceMode, diceChance
	notify("Rolling...", C.gold); play("spin")
	tw(diceNum, 0.2, { TextColor3 = C.text })
	for i = 1, 16 do                       -- number flicker slows down like a real roll
		if not alive then break end
		diceNum.Text = tostring(math.random(1, 100))
		task.wait(0.03 + (i / 16) ^ 2 * 0.1)
	end
	local roll = math.random(1, 100)
	local win = (mode == "under" and roll <= chance) or (mode == "over" and roll > 100 - chance)
	if alive then
		diceNum.Text = tostring(roll)
		tw(diceNum, 0.3, { TextColor3 = win and C.green or C.red })
		tw(diceNum, 0.2, { TextSize = 44 }, ES.Back)
		task.delay(0.2, function() tw(diceNum, 0.35, { TextSize = 36 }, ES.Quad) end)
	end
	local payout = win and math.floor(bet * CONFIG.DICE_RTP / chance + 0.5) or 0
	return payout, "rolled " .. roll .. (win and " - win" or " - loss")
end

-- ===== wiring =====
local conns = {}

menuBtn.Activated:Connect(function()
	play("click")
	if currentPage == "Menu" then showPage(lastGame) else showPage("Menu") end
end)
for name, b in pairs(menuTargets) do
	b.Activated:Connect(function() play("click"); showPage(name) end)
end

local function setBet(n)
	n = math.max(CONFIG.MIN_BET, math.floor(n))
	betBox.Text = string.format("%.0f", n)
end
local function curBet() return tonumber((betBox.Text:gsub(",", ""))) or CONFIG.MIN_BET end
betBox.Focused:Connect(function() tw(betStroke, 0.2, { Color = C.gold, Thickness = 2 }) end)
betBox.FocusLost:Connect(function()
	tw(betStroke, 0.3, { Color = C.goldDark, Thickness = 1 })
	setBet(curBet())
end)
halfBtn.Activated:Connect(function() play("click"); setBet(curBet() / 2) end)
dblBtn.Activated:Connect(function() play("click"); setBet(curBet() * 2) end)
allBtn.Activated:Connect(function() play("click"); setBet(math.max(state.balance, CONFIG.MIN_BET)) end)
for i, ch in ipairs(CHIPS) do
	chipBtns[i].Activated:Connect(function()
		play("click")
		if ch[2] == 0 then setBet(CONFIG.MIN_BET) else setBet(curBet() + ch[2]) end
	end)
end

spinBtn.Activated:Connect(function() startRound("Slots", playSlots) end)
flipBtn.Activated:Connect(function() startRound("Coinflip", playFlip) end)
rollBtn.Activated:Connect(function() startRound("Dice", playDice) end)

local function setPick(p)
	if busy then return end
	coinPick = p; play("click"); style(headsBtn, p == "H"); style(tailsBtn, p == "T")
end
headsBtn.Activated:Connect(function() setPick("H") end)
tailsBtn.Activated:Connect(function() setPick("T") end)

local function setMode(m)
	if busy then return end
	diceMode = m; play("click"); style(underBtn, m == "under"); style(overBtn, m == "over"); diceInfo()
end
underBtn.Activated:Connect(function() setMode("under") end)
overBtn.Activated:Connect(function() setMode("over") end)
local function nudge(d)
	if busy then return end
	diceChance = math.clamp(diceChance + d, 5, 90); play("click"); diceInfo()
end
m5Btn.Activated:Connect(function() nudge(-5) end)
m1Btn.Activated:Connect(function() nudge(-1) end)
p1Btn.Activated:Connect(function() nudge(1) end)
p5Btn.Activated:Connect(function() nudge(5) end)

local resetArmed = false
resetBtn.Activated:Connect(function()
	if busy then return end
	if not resetArmed then
		resetArmed = true; resetBtn.Text = "TAP AGAIN TO CONFIRM"
		tw(resetBtn, 0.25, { BackgroundColor3 = C.orange })
		task.delay(3, function()
			if alive and resetArmed then
				resetArmed = false; resetBtn.Text = "RESET BALANCE"; tw(resetBtn, 0.3, { BackgroundColor3 = C.red })
			end
		end)
		return
	end
	resetArmed = false
	state.balance = CONFIG.START_BALANCE; saveData(); refreshBalance(C.gold)
	resetBtn.Text = "BALANCE RESET!"
	tw(resetBtn, 0.25, { BackgroundColor3 = C.green })
	task.delay(1.5, function()
		if alive then resetBtn.Text = "RESET BALANCE"; tw(resetBtn, 0.4, { BackgroundColor3 = C.red }) end
	end)
end)
local function soundText()
	soundBtn.Text = "SOUND: " .. (state.sound and "ON" or "OFF")
	tw(soundBtn, 0.3, { BackgroundColor3 = state.sound and C.panel2 or C.red })
end
soundBtn.Activated:Connect(function() state.sound = not state.sound; soundText(); saveData(); play("click") end)

-- minimize (shrinks into a $ button) / close (shrinks away)
minBtn.Activated:Connect(function()
	tw(popVal, 0.25, { Value = 0.01 }, ES.Back, ED.In)
	task.delay(0.26, function()
		main.Visible = false
		mini.Visible = true
		tw(mini, 0.45, { Size = UDim2.new(0, 48, 0, 48) }, ES.Back)
	end)
end)
mini.Activated:Connect(function()
	tw(mini, 0.2, { Size = UDim2.new(0, 0, 0, 0) }, ES.Quad, ED.In)
	task.delay(0.21, function()
		mini.Visible = false
		popVal.Value = 0.01
		main.Visible = true
		tw(popVal, 0.5, { Value = 1 }, ES.Back)
	end)
end)
closeBtn.Activated:Connect(function()
	alive = false
	tw(popVal, 0.3, { Value = 0.01 }, ES.Back, ED.In)
	task.delay(0.32, function()
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		for _, s in pairs(sfx) do pcall(function() s:Destroy() end) end
		gui:Destroy()
	end)
end)

-- drag (mouse + touch) by the header
local dragging, dragStart, startPos = false, nil, nil
top.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = true; dragStart = i.Position; startPos = main.Position
		i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)
conns[#conns + 1] = UserInputService.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

-- shrink on small screens so it always fits
local cam = workspace.CurrentCamera
local function rescale()
	local v = cam.ViewportSize
	fit = math.clamp(math.min(v.X / 532, v.Y / 324), 0.5, 1)
	uiScale.Scale = fit * popVal.Value
end
rescale()
conns[#conns + 1] = cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

-- ===== start (intro animation) =====
style(headsBtn, true); style(tailsBtn, false)
style(underBtn, true); style(overBtn, false)
diceInfo(); soundText()
refreshHistory(false); refreshStats()
notify("Set your bet and play!", C.gold)
headLine.Size = UDim2.new(0, 0, 0, 2)
vLine.Size = UDim2.new(0, 2, 0, 0)
tw(popVal, 0.6, { Value = 1 }, ES.Back)
task.delay(0.2, function()
	tw(headLine, 0.8, { Size = UDim2.new(1, 0, 0, 2) })
	tw(vLine, 0.8, { Size = UDim2.new(0, 2, 0, 256) })
end)
showPage("Menu")
