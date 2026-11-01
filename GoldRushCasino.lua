--[[
	GOLD RUSH CASINO  -  FAKE coins only (never touches Robux or the game's economy)
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
-- {symbol, weight}; weights add up to 100 (slots return ~95.7% overall)
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
	green = Color3.fromRGB(70, 210, 110), red = Color3.fromRGB(235, 70, 70),
}
local alive, busy = true, false

-- ===== helpers =====
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
local function button(text, parent, size, pos, bg, fg)
	local b = make("TextButton", { Text = text, Size = size, Position = pos or UDim2.new(), BackgroundColor3 = bg or C.panel2,
		TextColor3 = fg or C.text, Font = Enum.Font.GothamBold, TextSize = 14, BorderSizePixel = 0 }, parent)
	round(b, 8)
	return b
end
local function style(btn, on)
	btn.BackgroundColor3 = on and C.gold or C.panel2
	btn.TextColor3 = on and C.bg or C.text
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
local function pickSymbol()
	local r, acc = math.random(1, 100), 0
	for _, s in ipairs(SYMBOLS) do
		acc = acc + s[2]
		if r <= acc then return s[1] end
	end
	return SYMBOLS[1][1]
end
local function randomSymbol() return SYMBOLS[math.random(#SYMBOLS)][1] end

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

local main = make("Frame", { Name = "Main", Size = UDim2.new(0, 440, 0, 336), Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true }, gui)
round(main, 12)
local mainStroke = stroke(main, C.gold, 2)
local uiScale = make("UIScale", {}, main)

local mini = button("$", gui, UDim2.new(0, 48, 0, 48), UDim2.new(0, 12, 0.5, -24), C.gold, C.bg)
mini.TextSize = 28; mini.Visible = false

-- top bar
local top = make("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.panel, BorderSizePixel = 0, Active = true }, main)
round(top, 12)
make("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, top)
label("GOLD RUSH", top, UDim2.new(0, 120, 1, 0), UDim2.new(0, 12, 0, 0), 16, C.gold, Enum.Font.GothamBlack, Enum.TextXAlignment.Left)
local balLabel = label("", top, UDim2.new(0, 170, 1, 0), UDim2.new(0.5, -85, 0, 0), 16, C.gold)
local minBtn = button("-", top, UDim2.new(0, 30, 0, 26), UDim2.new(1, -74, 0, 6))
local closeBtn = button("X", top, UDim2.new(0, 30, 0, 26), UDim2.new(1, -38, 0, 6), C.red, C.text)
minBtn.TextSize = 18

-- tabs + pages
local TABS = { "Slots", "Coinflip", "Dice", "History", "Stats" }
local GAME_TABS = { Slots = true, Coinflip = true, Dice = true }
local tabBar = make("Frame", { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 8, 0, 44), BackgroundTransparency = 1 }, main)
local pages, tabBtns = {}, {}
for i, name in ipairs(TABS) do
	local tb = button(name, tabBar, UDim2.new(0, 83, 1, 0), UDim2.new(0, (i - 1) * 85, 0, 0))
	tb.TextSize = 13
	tabBtns[name] = tb
	pages[name] = make("Frame", { Name = name, Size = UDim2.new(1, -16, 0, GAME_TABS[name] and 168 or 254),
		Position = UDim2.new(0, 8, 0, 76), BackgroundTransparency = 1, Visible = false }, main)
end

-- SLOTS page
local reels, reelStrokes = {}, {}
local startSyms = { "🍒", "🍋", "🔔" }
for i = 1, 3 do
	local r = make("TextLabel", { Size = UDim2.new(0, 90, 0, 80), Position = UDim2.new(0.5, -145 + (i - 1) * 100, 0, 4),
		BackgroundColor3 = C.panel, Text = startSyms[i], TextSize = 46, Font = Enum.Font.GothamBold, TextColor3 = C.gold }, pages.Slots)
	round(r, 10)
	reelStrokes[i] = stroke(r, C.goldDark, 2)
	reels[i] = r
end
local payParts = {}
for _, s in ipairs(SYMBOLS) do payParts[#payParts + 1] = s[1] .. " x" .. CONFIG.SLOT_TRIPLE[s[1]] end
local payLbl = label(table.concat(payParts, "   ") .. "\nthree of a kind pays the multiplier  |  any pair = bet back",
	pages.Slots, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 90), 11, C.dim, Enum.Font.Gotham)
payLbl.TextWrapped = true
local spinBtn = button("SPIN", pages.Slots, UDim2.new(0, 240, 0, 36), UDim2.new(0.5, -120, 0, 128), C.gold, C.bg)
spinBtn.TextSize = 18

-- COINFLIP page
local coin = make("TextLabel", { Size = UDim2.new(0, 76, 0, 76), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4),
	BackgroundColor3 = C.gold, Text = "H", TextColor3 = C.bg, Font = Enum.Font.GothamBlack, TextSize = 38 }, pages.Coinflip)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, coin)
stroke(coin, C.goldDark, 3)
local headsBtn = button("HEADS", pages.Coinflip, UDim2.new(0, 120, 0, 32), UDim2.new(0.5, -126, 0, 88))
local tailsBtn = button("TAILS", pages.Coinflip, UDim2.new(0, 120, 0, 32), UDim2.new(0.5, 6, 0, 88))
local flipBtn = button("FLIP  (pays " .. CONFIG.COINFLIP_PAYOUT .. "x)", pages.Coinflip, UDim2.new(0, 240, 0, 36), UDim2.new(0.5, -120, 0, 128), C.gold, C.bg)
flipBtn.TextSize = 17

-- DICE page
local diceNum = label("--", pages.Dice, UDim2.new(0, 160, 0, 46), UDim2.new(0.5, -80, 0, 0), 40, C.gold, Enum.Font.GothamBlack)
local underBtn = button("UNDER", pages.Dice, UDim2.new(0, 110, 0, 28), UDim2.new(0.5, -116, 0, 50))
local overBtn = button("OVER", pages.Dice, UDim2.new(0, 110, 0, 28), UDim2.new(0.5, 6, 0, 50))
local m5Btn = button("-5", pages.Dice, UDim2.new(0, 44, 0, 28), UDim2.new(0.5, -175, 0, 82))
local m1Btn = button("-1", pages.Dice, UDim2.new(0, 44, 0, 28), UDim2.new(0.5, -125, 0, 82))
local diceTarget = label("", pages.Dice, UDim2.new(0, 150, 0, 28), UDim2.new(0.5, -75, 0, 82), 14, C.text)
local p1Btn = button("+1", pages.Dice, UDim2.new(0, 44, 0, 28), UDim2.new(0.5, 81, 0, 82))
local p5Btn = button("+5", pages.Dice, UDim2.new(0, 44, 0, 28), UDim2.new(0.5, 131, 0, 82))
local diceInfoLbl = label("", pages.Dice, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 113), 12, C.dim, Enum.Font.Gotham)
local rollBtn = button("ROLL", pages.Dice, UDim2.new(0, 240, 0, 34), UDim2.new(0.5, -120, 0, 132), C.gold, C.bg)
rollBtn.TextSize = 18

-- HISTORY page
local histScroll = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.panel, BorderSizePixel = 0,
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, pages.History)
round(histScroll, 8)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, histScroll)
make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4) }, histScroll)

-- STATS page
local statsLabel = label("", pages.Stats, UDim2.new(1, 0, 0, 108), UDim2.new(0, 0, 0, 0), 14, C.text, Enum.Font.Gotham, Enum.TextXAlignment.Left)
statsLabel.RichText = true; statsLabel.TextYAlignment = Enum.TextYAlignment.Top
label("SESSION LEADERBOARD (net profit)", pages.Stats, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 112), 13, C.gold, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
local leaderLabel = label("", pages.Stats, UDim2.new(1, 0, 0, 52), UDim2.new(0, 0, 0, 130), 14, C.text, Enum.Font.Gotham, Enum.TextXAlignment.Left)
leaderLabel.RichText = true; leaderLabel.TextYAlignment = Enum.TextYAlignment.Top
local resetBtn = button("RESET BALANCE", pages.Stats, UDim2.new(0.5, -4, 0, 36), UDim2.new(0, 0, 0, 190), C.red)
local soundBtn = button("", pages.Stats, UDim2.new(0.5, -4, 0, 36), UDim2.new(0.5, 4, 0, 190))
label(canSave and ("Auto-save ON (" .. CONFIG.SAVE_FILE .. ")") or "Auto-save not supported here: balance resets each run",
	pages.Stats, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 232), 11, C.dim, Enum.Font.Gotham)

-- status strip + bet bar (game tabs only)
local statusLabel = label("", main, UDim2.new(1, -16, 0, 20), UDim2.new(0, 8, 0, 246), 12, C.dim, Enum.Font.GothamBold)
local betBar = make("Frame", { Size = UDim2.new(1, -16, 0, 60), Position = UDim2.new(0, 8, 0, 270), BackgroundTransparency = 1 }, main)
label("BET", betBar, UDim2.new(0, 36, 0, 28), UDim2.new(0, 0, 0, 0), 14, C.gold)
local betBox = make("TextBox", { Size = UDim2.new(0, 190, 0, 28), Position = UDim2.new(0, 42, 0, 0), BackgroundColor3 = C.panel2,
	TextColor3 = C.gold, PlaceholderText = "Bet amount", PlaceholderColor3 = C.dim, Text = tostring(CONFIG.MIN_BET),
	Font = Enum.Font.GothamBold, TextSize = 15, ClearTextOnFocus = false, BorderSizePixel = 0 }, betBar)
round(betBox, 8)
local halfBtn = button("1/2", betBar, UDim2.new(0, 56, 0, 28), UDim2.new(0, 238, 0, 0))
local dblBtn = button("2x", betBar, UDim2.new(0, 56, 0, 28), UDim2.new(0, 300, 0, 0))
local allBtn = button("ALL IN", betBar, UDim2.new(0, 56, 0, 28), UDim2.new(0, 362, 0, 0), C.red)
local CHIPS = { { "+10", 10 }, { "+100", 100 }, { "+1K", 1000 }, { "+10K", 10000 }, { "MIN", 0 } }
local chipBtns = {}
for i, ch in ipairs(CHIPS) do
	chipBtns[i] = button(ch[1], betBar, UDim2.new(0, 80, 0, 28), UDim2.new(0, (i - 1) * 86, 0, 32), C.panel2, C.gold)
end

-- ===== logic =====
local diceMode, diceChance, coinPick = "under", 50, "H"

local function notify(text, color) statusLabel.Text = text; statusLabel.TextColor3 = color or C.dim end

local function refreshBalance(flash)
	balLabel.Text = "COINS  " .. fmt(state.balance)
	if flash then
		balLabel.TextColor3 = flash
		TweenService:Create(balLabel, TweenInfo.new(0.7), { TextColor3 = C.gold }):Play()
	end
end

local function refreshHistory()
	for _, ch in ipairs(histScroll:GetChildren()) do if ch:IsA("TextLabel") then ch:Destroy() end end
	if #history == 0 then
		label("No bets yet - go play!", histScroll, UDim2.new(1, -8, 0, 22), nil, 12, C.dim, Enum.Font.Gotham, Enum.TextXAlignment.Left)
		return
	end
	for i, h in ipairs(history) do
		local t = label(h.game .. "  |  bet " .. fmt(h.bet) .. "  |  " .. signed(h.profit) .. "  |  " .. h.detail, histScroll,
			UDim2.new(1, -8, 0, 22), nil, 12, h.profit > 0 and C.green or (h.profit < 0 and C.red or C.dim), Enum.Font.Gotham, Enum.TextXAlignment.Left)
		t.LayoutOrder = i
		t.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

local function refreshStats()
	local winRate = S.rounds > 0 and (S.wins / S.rounds * 100) or 0
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
end

local function winFx(amount)
	play("win")
	local banner = label("+" .. fmt(amount), main, UDim2.new(0, 300, 0, 50), UDim2.new(0.5, -150, 0.42, 0), 8, C.gold, Enum.Font.GothamBlack)
	banner.ZIndex = 20; banner.TextStrokeTransparency = 0
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { TextSize = 36 }):Play()
	TweenService:Create(mainStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 2, true), { Thickness = 6 }):Play()
	for _ = 1, 14 do
		local p = make("Frame", { Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0.5, -5, 0.45, 0), BackgroundColor3 = C.gold, BorderSizePixel = 0, ZIndex = 19 }, main)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
		TweenService:Create(p, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, math.random(-190, 190), 0.45, math.random(-130, 70)), BackgroundTransparency = 1 }):Play()
		task.delay(0.9, function() p:Destroy() end)
	end
	task.delay(1.2, function()
		if not alive then return end
		TweenService:Create(banner, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.5)
		banner:Destroy()
	end)
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
	refreshHistory(); refreshStats()
	if profit > 0 then
		notify("YOU WON " .. fmt(profit) .. "!  (" .. detail .. ")", C.green); winFx(profit)
	elseif profit == 0 then
		notify("Push - bet returned  (" .. detail .. ")", C.gold)
	else
		notify("Lost " .. fmt(-profit) .. "  (" .. detail .. ")", C.red); play("lose")
	end
end

local function takeBet()
	if busy then notify("Round in progress...", C.dim) return nil end
	if state.balance < CONFIG.MIN_BET then notify("Out of coins! Reset your balance in the Stats tab.", C.red) return nil end
	local n = tonumber((betBox.Text:gsub(",", "")))
	if not n or n ~= n then notify("Enter a valid bet.", C.red) return nil end
	n = math.floor(n)
	if n < CONFIG.MIN_BET then notify("Minimum bet is " .. CONFIG.MIN_BET .. ".", C.red) return nil end
	if n > state.balance then notify("Not enough coins.", C.red) return nil end
	busy = true
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
	busy = false
end

local function playSlots(bet)
	local final = { pickSymbol(), pickSymbol(), pickSymbol() }
	for i = 1, 3 do reelStrokes[i].Color = C.goldDark end
	notify("Spinning...", C.gold); play("spin")
	local stopAt, done, t0 = { 0.7, 1.1, 1.5 }, { false, false, false }, os.clock()
	while alive and not (done[1] and done[2] and done[3]) do
		local el = os.clock() - t0
		for i = 1, 3 do
			if not done[i] then
				if el >= stopAt[i] then
					done[i] = true; reels[i].Text = final[i]; play("click")
				else
					reels[i].Text = randomSymbol()
				end
			end
		end
		task.wait(0.07)
	end
	local a, b, c = final[1], final[2], final[3]
	local payout, detail = 0, a .. b .. c .. " no match"
	if a == b and b == c then
		payout = math.floor(bet * CONFIG.SLOT_TRIPLE[a] + 0.5); detail = a .. b .. c .. " triple"
	elseif a == b or b == c or a == c then
		payout = bet * CONFIG.SLOT_PAIR; detail = a .. b .. c .. " pair"
	end
	if alive then
		for i = 1, 3 do reels[i].Text = final[i]; reelStrokes[i].Color = payout > bet and C.green or C.goldDark end
	end
	return payout, detail
end

local function playFlip(bet)
	local pick = coinPick
	notify("Flipping...", C.gold); play("spin")
	for i = 1, 6 do
		if not alive then break end
		TweenService:Create(coin, TweenInfo.new(0.1), { Size = UDim2.new(0, 6, 0, 76) }):Play()
		task.wait(0.1)
		coin.Text = (i % 2 == 0) and "H" or "T"
		TweenService:Create(coin, TweenInfo.new(0.1), { Size = UDim2.new(0, 76, 0, 76) }):Play()
		task.wait(0.1)
	end
	local res = math.random(2) == 1 and "H" or "T"
	local win = (res == pick)
	if alive then coin.Size = UDim2.new(0, 76, 0, 76); coin.Text = res end
	local payout = win and math.floor(bet * CONFIG.COINFLIP_PAYOUT + 0.5) or 0
	return payout, (res == "H" and "heads" or "tails") .. (win and " - win" or " - loss")
end

local function playDice(bet)
	local mode, chance = diceMode, diceChance
	notify("Rolling...", C.gold); play("spin")
	for _ = 1, 14 do
		if not alive then break end
		diceNum.Text = tostring(math.random(1, 100)); diceNum.TextColor3 = C.text
		task.wait(0.05)
	end
	local roll = math.random(1, 100)
	local win = (mode == "under" and roll <= chance) or (mode == "over" and roll > 100 - chance)
	if alive then diceNum.Text = tostring(roll); diceNum.TextColor3 = win and C.green or C.red end
	local payout = win and math.floor(bet * CONFIG.DICE_RTP / chance + 0.5) or 0
	return payout, "rolled " .. roll .. (win and " - win" or " - loss")
end

local function showTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabBtns) do style(b, n == name) end
	local isGame = GAME_TABS[name] == true
	betBar.Visible = isGame; statusLabel.Visible = isGame
	if name == "History" then refreshHistory() elseif name == "Stats" then refreshStats() end
end

-- ===== wiring =====
local conns = {}
for name, tb in pairs(tabBtns) do
	tb.Activated:Connect(function() play("click"); showTab(name) end)
end

local function setBet(n)
	n = math.max(CONFIG.MIN_BET, math.floor(n))
	betBox.Text = string.format("%.0f", n)
end
local function curBet() return tonumber((betBox.Text:gsub(",", ""))) or CONFIG.MIN_BET end
betBox.FocusLost:Connect(function() setBet(curBet()) end)
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
		task.delay(3, function() if alive then resetArmed = false; resetBtn.Text = "RESET BALANCE" end end)
		return
	end
	resetArmed = false
	state.balance = CONFIG.START_BALANCE; saveData(); refreshBalance(C.gold)
	resetBtn.Text = "BALANCE RESET!"
	task.delay(1.5, function() if alive then resetBtn.Text = "RESET BALANCE" end end)
end)
local function soundText() soundBtn.Text = "SOUND: " .. (state.sound and "ON" or "OFF") end
soundBtn.Activated:Connect(function() state.sound = not state.sound; soundText(); saveData(); play("click") end)

-- minimize / close
minBtn.Activated:Connect(function() main.Visible = false; mini.Visible = true end)
mini.Activated:Connect(function() main.Visible = true; mini.Visible = false end)
closeBtn.Activated:Connect(function()
	alive = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	for _, s in pairs(sfx) do pcall(function() s:Destroy() end) end
	gui:Destroy()
end)

-- drag (mouse + touch) by the top bar
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
	uiScale.Scale = math.clamp(math.min(v.X / 460, v.Y / 356), 0.5, 1)
end
rescale()
conns[#conns + 1] = cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

-- ===== start =====
style(headsBtn, true); style(tailsBtn, false)
style(underBtn, true); style(overBtn, false)
diceInfo(); soundText()
refreshBalance(); refreshHistory(); refreshStats()
showTab("Slots")
notify("Welcome to Gold Rush! Set your bet and play.", C.gold)
