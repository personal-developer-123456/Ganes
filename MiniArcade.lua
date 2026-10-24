-- MINI ARCADE + ANTI-AFK
-- Type: LocalScript
-- Put it in: StarterPlayer > StarterPlayerScripts
-- Mobile + PC friendly. Draggable menu, 3 games, anti-AFK tap every 19 min.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ANTI_AFK_SECONDS = 19 * 60 -- Roblox idle-kicks at 20 min

-- colors
local BG = Color3.fromRGB(24, 26, 34)
local CARD = Color3.fromRGB(38, 41, 54)
local ACCENT = Color3.fromRGB(88, 101, 242)
local GOOD = Color3.fromRGB(67, 181, 129)
local BAD = Color3.fromRGB(237, 66, 69)
local WHITE = Color3.new(1, 1, 1)

------------------------------------------------------------------
-- ANTI-AFK
------------------------------------------------------------------
local antiAfk = { enabled = true, nextTap = os.clock() + ANTI_AFK_SECONDS, taps = 0 }

local function doTap()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
	antiAfk.taps += 1
	antiAfk.nextTap = os.clock() + ANTI_AFK_SECONDS
end

task.spawn(function()
	while true do
		task.wait(1)
		if antiAfk.enabled and os.clock() >= antiAfk.nextTap then
			doTap()
		end
	end
end)

------------------------------------------------------------------
-- UI HELPERS
------------------------------------------------------------------
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(inst, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, inst)
end

local function pad(inst, n)
	make("UIPadding", {
		PaddingTop = UDim.new(0, n),
		PaddingBottom = UDim.new(0, n),
		PaddingLeft = UDim.new(0, n),
		PaddingRight = UDim.new(0, n),
	}, inst)
end

local function label(parent, text, props)
	local l = make("TextLabel", {
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = WHITE,
		BackgroundTransparency = 1,
		TextWrapped = true,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent, text, props)
	local b = make("TextButton", {
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = WHITE,
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		TextWrapped = true,
	}, parent)
	corner(b, 8)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	return b
end

-- fires instantly on touch/click (feels better than Activated for games)
local function onPress(obj, fn)
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			fn()
		end
	end)
end

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos = false, nil, nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end)
end

-- left = game area, right = controls / info
local function split(parent)
	local left = make("Frame", {
		Size = UDim2.fromScale(0.62, 1),
		BackgroundTransparency = 1,
	}, parent)
	local right = make("Frame", {
		Position = UDim2.fromScale(0.62, 0),
		Size = UDim2.fromScale(0.38, 1),
		BackgroundTransparency = 1,
	}, parent)
	pad(left, 8)
	pad(right, 8)
	return left, right
end

local function fmt(n)
	if n < 1000 then
		return tostring(math.floor(n))
	end
	local units = { "K", "M", "B", "T", "Qa" }
	local i = 0
	while n >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	return string.format("%.2f%s", n, units[i])
end

------------------------------------------------------------------
-- GAME 1: SNAKE (D-pad for mobile, arrow keys for PC)
------------------------------------------------------------------
local function snakeGame(parent)
	local left, right = split(parent)
	local N = 15

	local board = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(26, 28, 38),
		BorderSizePixel = 0,
	}, left)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, board)

	local C1, C2 = Color3.fromRGB(30, 33, 44), Color3.fromRGB(26, 28, 38)
	local function baseColor(x, y)
		return ((x + y) % 2 == 0) and C1 or C2
	end

	local cells = {}
	for y = 1, N do
		cells[y] = {}
		for x = 1, N do
			cells[y][x] = make("Frame", {
				Position = UDim2.fromScale((x - 1) / N, (y - 1) / N),
				Size = UDim2.fromScale(1 / N, 1 / N),
				BackgroundColor3 = baseColor(x, y),
				BorderSizePixel = 0,
			}, board)
		end
	end

	local info = label(right, "", { Size = UDim2.fromScale(1, 0.2), TextSize = 14 })

	local snake, dir, nextDir, food, score
	local alive = false
	local running = true

	local function placeFood()
		local occ = {}
		for _, s in ipairs(snake) do
			occ[s[2] * 100 + s[1]] = true
		end
		local free = {}
		for y = 1, N do
			for x = 1, N do
				if not occ[y * 100 + x] then
					table.insert(free, { x, y })
				end
			end
		end
		food = (#free > 0) and free[math.random(#free)] or nil
	end

	local function draw()
		for y = 1, N do
			for x = 1, N do
				cells[y][x].BackgroundColor3 = baseColor(x, y)
			end
		end
		if food then
			cells[food[2]][food[1]].BackgroundColor3 = BAD
		end
		for i, s in ipairs(snake) do
			cells[s[2]][s[1]].BackgroundColor3 = (i == 1) and Color3.fromRGB(120, 255, 170) or GOOD
		end
		if alive then
			info.Text = "Score: " .. score
		end
	end

	local function reset()
		snake = { { 8, 8 }, { 7, 8 }, { 6, 8 } }
		dir = { 1, 0 }
		nextDir = dir
		score = 0
		alive = true
		placeFood()
		draw()
	end

	local function die()
		alive = false
		info.Text = "Game over: " .. score .. "\nPress to retry"
	end

	local function step()
		dir = nextDir
		local head = snake[1]
		local nx, ny = head[1] + dir[1], head[2] + dir[2]
		if nx < 1 or nx > N or ny < 1 or ny > N then
			die()
			return
		end
		for _, s in ipairs(snake) do
			if s[1] == nx and s[2] == ny then
				die()
				return
			end
		end
		table.insert(snake, 1, { nx, ny })
		if food and nx == food[1] and ny == food[2] then
			score += 1
			placeFood()
		else
			table.remove(snake)
		end
		draw()
	end

	local function setDir(dx, dy)
		if not alive then
			reset()
		end
		if dx == -dir[1] and dy == -dir[2] then
			return
		end
		nextDir = { dx, dy }
	end

	-- D-pad
	local dp = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.8),
		BackgroundTransparency = 1,
	}, right)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, dp)

	local function pb(txt, cx, cy, dx, dy)
		local b = button(dp, txt, {
			Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromScale(0.32, 0.32),
			TextSize = 22,
		})
		onPress(b, function()
			setDir(dx, dy)
		end)
	end
	pb("▲", 0.34, 0, 0, -1)
	pb("◀", 0, 0.34, -1, 0)
	pb("▶", 0.68, 0.34, 1, 0)
	pb("▼", 0.34, 0.68, 0, 1)

	local keys = UIS.InputBegan:Connect(function(input)
		if UIS:GetFocusedTextBox() then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Up then
			setDir(0, -1)
		elseif k == Enum.KeyCode.Down then
			setDir(0, 1)
		elseif k == Enum.KeyCode.Left then
			setDir(-1, 0)
		elseif k == Enum.KeyCode.Right then
			setDir(1, 0)
		end
	end)

	-- idle state until first press
	reset()
	alive = false
	info.Text = "Press a direction to start"

	task.spawn(function()
		while running do
			task.wait(math.max(0.07, 0.17 - score * 0.004))
			if running and alive then
				step()
			end
		end
	end)

	return function()
		running = false
		keys:Disconnect()
	end
end

------------------------------------------------------------------
-- GAME 2: FLAPPY (tap anywhere on the board / Space)
------------------------------------------------------------------
local function flappyGame(parent)
	local area = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, parent)
	pad(area, 8)

	local board = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(88, 170, 230),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, area)
	make("UIAspectRatioConstraint", { AspectRatio = 1.6 }, board)
	corner(board, 8)

	-- everything is in 0..1 board units
	local BIRD_X, BIRD_W, BIRD_H = 0.25, 0.06, 0.096
	local PIPE_W, GAP, SPEED, SPACING = 0.12, 0.36, 0.3, 0.55
	local GRAV, FLAP = 2.6, -0.9

	local bird = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(BIRD_W, BIRD_H),
		BackgroundColor3 = Color3.fromRGB(255, 215, 60),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, board)
	corner(bird, 6)

	local scoreLbl = label(board, "0", { Size = UDim2.fromScale(1, 0.2), TextSize = 26, ZIndex = 6 })
	local msgLbl = label(board, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.9, 0.4),
		TextSize = 18,
		ZIndex = 6,
	})
	local catcher = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10,
	}, board)

	local by, vy, score, state, spawnT, diedAt = 0.5, 0, 0, "ready", 0, 0
	local pipes = {}

	local function setBird()
		bird.Position = UDim2.fromScale(BIRD_X, by)
	end

	local function reset()
		for _, p in ipairs(pipes) do
			p.top:Destroy()
			p.bot:Destroy()
		end
		pipes = {}
		by, vy, score, spawnT = 0.5, 0, 0, 0
		state = "ready"
		scoreLbl.Text = "0"
		msgLbl.Text = "Tap to start"
		setBird()
	end

	local function spawnPipe()
		local gy = 0.3 + math.random() * 0.4
		local function pipe(y, h)
			return make("Frame", {
				Position = UDim2.fromScale(1, y),
				Size = UDim2.fromScale(PIPE_W, h),
				BackgroundColor3 = Color3.fromRGB(70, 190, 90),
				BorderSizePixel = 0,
				ZIndex = 2,
			}, board)
		end
		table.insert(pipes, {
			x = 1,
			gy = gy,
			scored = false,
			top = pipe(0, gy - GAP / 2),
			bot = pipe(gy + GAP / 2, 1 - (gy + GAP / 2)),
		})
	end

	local function die()
		state = "dead"
		diedAt = os.clock()
		msgLbl.Text = "Game over: " .. score .. "\nTap to retry"
	end

	local function update(dt)
		dt = math.min(dt, 0.05)
		vy += GRAV * dt
		by += vy * dt
		if by < BIRD_H / 2 then
			by = BIRD_H / 2
			vy = 0
		end

		spawnT += dt
		if spawnT >= SPACING / SPEED then
			spawnT = 0
			spawnPipe()
		end

		local bl, br = BIRD_X - BIRD_W / 2, BIRD_X + BIRD_W / 2
		local bt, bb = by - BIRD_H * 0.4, by + BIRD_H * 0.4
		for i = #pipes, 1, -1 do
			local p = pipes[i]
			p.x -= SPEED * dt
			p.top.Position = UDim2.fromScale(p.x, 0)
			p.bot.Position = UDim2.fromScale(p.x, p.gy + GAP / 2)

			if br > p.x and bl < p.x + PIPE_W then
				if bt < p.gy - GAP / 2 or bb > p.gy + GAP / 2 then
					die()
				end
			end
			if not p.scored and p.x + PIPE_W < bl then
				p.scored = true
				score += 1
				scoreLbl.Text = tostring(score)
			end
			if p.x + PIPE_W < 0 then
				p.top:Destroy()
				p.bot:Destroy()
				table.remove(pipes, i)
			end
		end

		if by + BIRD_H / 2 >= 1 then
			by = 1 - BIRD_H / 2
			die()
		end
		setBird()
	end

	local function flap()
		if state == "dead" then
			if os.clock() - diedAt > 0.4 then
				reset()
			end
			return
		end
		if state == "ready" then
			state = "run"
			msgLbl.Text = ""
			spawnT = SPACING / SPEED
		end
		vy = FLAP
	end

	onPress(catcher, flap)

	local hb = RunService.Heartbeat:Connect(function(dt)
		if state == "run" then
			update(dt)
		end
	end)
	local keys = UIS.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space and not UIS:GetFocusedTextBox() then
			flap()
		end
	end)

	reset()

	return function()
		hb:Disconnect()
		keys:Disconnect()
	end
end

------------------------------------------------------------------
-- GAME 3: IDLE CLICKER (keeps earning in the background)
------------------------------------------------------------------
local clicker = {
	coins = 0,
	power = 1,
	auto = 0,
	powerCost = 15,
	autoCost = 50,
	refresh = nil,
}

task.spawn(function()
	while true do
		task.wait(1)
		if clicker.auto > 0 then
			clicker.coins += clicker.auto
			if clicker.refresh then
				clicker.refresh()
			end
		end
	end
end)

local function clickerGame(parent)
	local left, right = split(parent)

	local coinsLbl = label(left, "", { Size = UDim2.fromScale(1, 0.25), TextSize = 16 })

	local big = button(left, "TAP\n💰", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.72),
		BackgroundColor3 = ACCENT,
		TextSize = 22,
	})
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, big)
	big.UICorner.CornerRadius = UDim.new(0.5, 0)

	local upPower = button(right, "", {
		Size = UDim2.new(1, 0, 0.48, 0),
		TextSize = 14,
	})
	local upAuto = button(right, "", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0.48, 0),
		TextSize = 14,
	})

	local function refresh()
		coinsLbl.Text = "💰 " .. fmt(clicker.coins) .. "\n+" .. fmt(clicker.power) .. "/tap · " .. fmt(clicker.auto) .. "/sec"
		upPower.Text = "Stronger tap\n+1/tap\n" .. fmt(clicker.powerCost)
		upAuto.Text = "Auto-clicker\n+1/sec\n" .. fmt(clicker.autoCost)
		upPower.BackgroundColor3 = (clicker.coins >= clicker.powerCost) and GOOD or CARD
		upAuto.BackgroundColor3 = (clicker.coins >= clicker.autoCost) and GOOD or CARD
	end
	clicker.refresh = refresh

	onPress(big, function()
		clicker.coins += clicker.power
		refresh()
	end)

	upPower.Activated:Connect(function()
		if clicker.coins >= clicker.powerCost then
			clicker.coins -= clicker.powerCost
			clicker.power += 1
			clicker.powerCost = math.ceil(clicker.powerCost * 1.35)
			refresh()
		end
	end)
	upAuto.Activated:Connect(function()
		if clicker.coins >= clicker.autoCost then
			clicker.coins -= clicker.autoCost
			clicker.auto += 1
			clicker.autoCost = math.ceil(clicker.autoCost * 1.4)
			refresh()
		end
	end)

	refresh()

	return function()
		clicker.refresh = nil
	end
end

------------------------------------------------------------------
-- MAIN WINDOW
------------------------------------------------------------------
local games = {
	{ icon = "🐍", name = "Snake", build = snakeGame },
	{ icon = "🐦", name = "Flappy", build = flappyGame },
	{ icon = "💰", name = "Idle Clicker", build = clickerGame },
}

local gui = make("ScreenGui", {
	Name = "MiniArcade",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local toggle = button(gui, "🎮", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.4, 0),
	Size = UDim2.fromOffset(52, 52),
	BackgroundColor3 = ACCENT,
	TextSize = 26,
})
toggle.UICorner.CornerRadius = UDim.new(0, 26)

local panel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.92, 0.85),
	BackgroundColor3 = BG,
	BorderSizePixel = 0,
}, gui)
corner(panel, 12)
make("UISizeConstraint", { MaxSize = Vector2.new(560, 420), MinSize = Vector2.new(280, 220) }, panel)

local header = make("Frame", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = CARD,
	BorderSizePixel = 0,
}, panel)
corner(header, 12)
makeDraggable(header, panel)

label(header, "Arcade", {
	Position = UDim2.fromOffset(12, 0),
	Size = UDim2.new(0, 90, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 18,
})

local statusLbl = label(header, "", {
	Position = UDim2.fromOffset(104, 0),
	Size = UDim2.new(1, -196, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 12,
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextColor3 = Color3.fromRGB(180, 185, 200),
})

local closeBtn = button(header, "✕", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -6, 0.5, 0),
	Size = UDim2.fromOffset(36, 32),
	BackgroundColor3 = BAD,
})
local backBtn = button(header, "←", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -48, 0.5, 0),
	Size = UDim2.fromOffset(36, 32),
	Visible = false,
})

local content = make("Frame", {
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, panel)

-- page switching
local currentCleanup = nil
local showMenu

local function clearContent()
	if currentCleanup then
		currentCleanup()
		currentCleanup = nil
	end
	for _, c in ipairs(content:GetChildren()) do
		c:Destroy()
	end
end

local function openGame(build)
	clearContent()
	backBtn.Visible = true
	currentCleanup = build(content)
end

function showMenu()
	clearContent()
	backBtn.Visible = false

	local list = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, content)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	pad(list, 10)

	for i, g in ipairs(games) do
		local b = button(list, g.icon .. "   " .. g.name, {
			Size = UDim2.new(1, 0, 0, 54),
			LayoutOrder = i,
			TextSize = 18,
		})
		b.Activated:Connect(function()
			openGame(g.build)
		end)
	end

	-- anti-AFK card
	local card = make("Frame", {
		Size = UDim2.new(1, 0, 0, 100),
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		LayoutOrder = 100,
	}, list)
	corner(card, 10)
	label(card, "Anti-AFK  ·  taps every 19 min", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
	})
	local onBtn = button(card, "", {
		Position = UDim2.new(0, 12, 0, 40),
		Size = UDim2.new(0.5, -18, 0, 48),
	})
	local nowBtn = button(card, "Tap now (test)", {
		Position = UDim2.new(0.5, 6, 0, 40),
		Size = UDim2.new(0.5, -18, 0, 48),
		BackgroundColor3 = ACCENT,
	})
	local function refreshOn()
		onBtn.Text = antiAfk.enabled and "Anti-AFK: ON" or "Anti-AFK: OFF"
		onBtn.BackgroundColor3 = antiAfk.enabled and GOOD or BAD
	end
	refreshOn()
	onBtn.Activated:Connect(function()
		antiAfk.enabled = not antiAfk.enabled
		if antiAfk.enabled then
			antiAfk.nextTap = os.clock() + ANTI_AFK_SECONDS
		end
		refreshOn()
	end)
	nowBtn.Activated:Connect(doTap)
end

backBtn.Activated:Connect(showMenu)
closeBtn.Activated:Connect(function()
	panel.Visible = false
end)
toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

-- header countdown
task.spawn(function()
	while gui.Parent do
		if antiAfk.enabled then
			local left = math.max(0, math.floor(antiAfk.nextTap - os.clock()))
			statusLbl.Text = string.format("AFK tap in %d:%02d", left // 60, left % 60)
		else
			statusLbl.Text = "Anti-AFK off"
		end
		task.wait(1)
	end
end)

showMenu()
