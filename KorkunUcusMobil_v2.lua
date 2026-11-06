-- LocalScript (SADECE MOBİL) - KORKUNÇ UÇUŞ v2
-- Yeri: StarterPlayer > StarterPlayerScripts
-- Joystick = yön | Kamera kaydırma = bakış (yukarı/aşağı bakınca karakter de eğilir)
-- Yukarı çıkmak için: kamerayı yukarı çevir + joystick'i ileri it
-- Butonlar: UÇ/İNİŞ, MAX, MIN, X (kapat) | ▲ hızı artır, ▼ hızı azalt (basılı tut = hızlı değişir), 😀 emote
-- Menüyü üstteki başlık çubuğundan tutup sürükleyebilirsin

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- AYARLAR --------------------------------------------------
local MAX_SPEED = 999999   -- MAX butonunun hızı
local MIN_SPEED = 10       -- MIN butonunun hızı
local START_SPEED = 100    -- uçmaya başlayınca hız
local SPEED_STEP = 1.2     -- ▲/▼ her basışta hızı bu kadar çarpar/böler
local SMOOTHNESS = 6       -- yüksek = daha keskin hızlanma
local MAX_LEAN = 70        -- ileri giderken öne eğilme açısı (derece)
local LOOK_PITCH = 1       -- kamera yukarı/aşağı bakınca karakter eğilme oranı (0 = kapalı)
local BASE_FOV = 70
local BOOST_FOV = 100      -- hızlanınca kamera açısı
local SHAKE = 0.9          -- kamera titremesi (0 = kapalı)
local CELL = 36            -- buton boyutu (menüyü küçültmek/büyütmek için)
-------------------------------------------------------------

-- EMOTELER (Roblox'un kendi emote animasyonları)
-- Sıra: dans, dans2, dans3, el salla, işaret et, kutla, gül
local EMOTES = {
	R15 = {
		{ "💃", 507771019 },
		{ "🕺", 507776043 },
		{ "🎵", 507777268 },
		{ "👋", 507770239 },
		{ "👉", 507770453 },
		{ "🎉", 507770677 },
		{ "😂", 507770818 },
	},
	R6 = {
		{ "💃", 182435998 },
		{ "🕺", 182491037 },
		{ "🎵", 182491065 },
		{ "👋", 128777973 },
		{ "👉", 128853357 },
		{ "🎉", 129423030 },
		{ "😂", 129423131 },
	},
}

local flying = false
local currentSpeed = START_SPEED
local velocity = Vector3.zero
local lastFlat = Vector3.new(0, 0, -1)
local fx = {}
local connections = {}
local loop, linearVel, align, trail
local gui, holder, flyButton, speedLabel, emotePanel
local emoteTrack, emoteIndex
local emoteButtons = {}

-- Joystick girdisi
local controls
task.spawn(function()
	local ok, result = pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		return require(module):GetControls()
	end)
	if ok then controls = result end
end)

local function getJoystick(hum)
	if controls then
		local v = controls:GetMoveVector()
		return Vector2.new(v.X, -v.Z) -- x: sağ/sol, y: ileri/geri
	end
	local dir = hum.MoveDirection
	local cf = camera.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	return Vector2.new(dir:Dot(right), dir:Dot(look))
end

local function getParts()
	local char = player.Character
	if not char then return end
	return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

-- EMOTE -----------------------------------------------------
local function refreshEmoteUI()
	for i, b in ipairs(emoteButtons) do
		b.BackgroundColor3 = (i == emoteIndex) and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(30, 30, 40)
	end
end

local function stopEmote()
	if emoteTrack then
		pcall(function()
			emoteTrack:Stop(0.2)
			emoteTrack:Destroy()
		end)
		emoteTrack = nil
	end
	emoteIndex = nil
	refreshEmoteUI()
end

-- Roblox'un kendi emote menüsü uçarken çalışmaz (PlatformStand engelliyor),
-- o yüzden animasyonu kendimiz oynatıyoruz. Aynı butona tekrar basınca durur.
local function playEmote(i)
	local hum = getParts()
	if not hum then return end

	local same = (emoteIndex == i)
	stopEmote()
	if same then return end

	local list = (hum.RigType == Enum.HumanoidRigType.R6) and EMOTES.R6 or EMOTES.R15
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. list[i][2]
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then return end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true
	track:Play(0.2)
	emoteTrack = track
	emoteIndex = i
	refreshEmoteUI()
end

-- HIZ / UI GÜNCELLEME ---------------------------------------
local function updateUI()
	if flyButton then
		flyButton.Text = flying and "İNİŞ" or "UÇ"
		flyButton.BackgroundColor3 = flying and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(190, 20, 40)
	end
	if speedLabel then
		speedLabel.Text = "Hız: " .. tostring(math.floor(currentSpeed))
	end
end

-- Hızı anında değiştirir
local function setSpeed(newSpeed)
	newSpeed = math.clamp(newSpeed, MIN_SPEED, MAX_SPEED)
	local old = math.max(currentSpeed, 1)
	currentSpeed = newSpeed
	if flying then
		velocity = velocity * (newSpeed / old)
	end
	updateUI()
end

local function changeSpeed(mult)
	setSpeed(math.floor(currentSpeed * mult + 0.5))
end

local function stopFlying()
	if not flying then return end
	flying = false

	if loop then loop:Disconnect() loop = nil end
	for _, obj in ipairs(fx) do obj:Destroy() end
	table.clear(fx)

	stopEmote()
	velocity = Vector3.zero
	camera.FieldOfView = BASE_FOV
	updateUI()

	local hum = getParts()
	if hum then
		hum.CameraOffset = Vector3.zero
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function startFlying()
	local hum, root = getParts()
	if not hum or not root or flying then return end
	flying = true
	camera = workspace.CurrentCamera
	hum.PlatformStand = true
	updateUI()

	local char = root.Parent

	-- Hareket
	local att = Instance.new("Attachment")
	att.Parent = root
	table.insert(fx, att)

	linearVel = Instance.new("LinearVelocity")
	linearVel.Attachment0 = att
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.MaxForce = math.huge
	linearVel.VectorVelocity = Vector3.zero
	linearVel.Parent = root
	table.insert(fx, linearVel)

	-- Dönüş / eğilme
	align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = math.huge
	align.Responsiveness = 25
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	table.insert(fx, align)

	-- Kan kırmızısı -> siyah iz
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0.5)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.2, 0.5)
	a1.Parent = root

	trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(220, 0, 0), Color3.fromRGB(0, 0, 0))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Enabled = false
	trail.Parent = root
	table.insert(fx, a0)
	table.insert(fx, a1)
	table.insert(fx, trail)

	-- Karakterin etrafında kırmızı parlayan çizgi (aura)
	local hl = Instance.new("Highlight")
	hl.Adornee = char
	hl.FillColor = Color3.fromRGB(0, 0, 0)
	hl.FillTransparency = 0.65
	hl.OutlineColor = Color3.fromRGB(255, 0, 0)
	hl.OutlineTransparency = 0.2
	hl.Parent = char
	table.insert(fx, hl)

	-- Kırmızı ışık
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 0, 0)
	light.Range = 20
	light.Brightness = 2
	light.Parent = root
	table.insert(fx, light)

	-- Arkada kalan siyah duman
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 8),
	})
	smoke.Lifetime = NumberRange.new(0.8, 1.6)
	smoke.Speed = NumberRange.new(0, 2)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.LightInfluence = 0
	smoke.Rate = 0
	smoke.Parent = root
	table.insert(fx, smoke)

	-- Kırmızı kıvılcımlar
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 30, 0))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Lifetime = NumberRange.new(0.4, 0.9)
	embers.Speed = NumberRange.new(2, 8)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Rate = 0
	embers.Parent = root
	table.insert(fx, embers)

	-- Ekran efektleri: soluk, kırmızımsı, bulanık görüntü
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = camera
	table.insert(fx, cc)

	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = camera
	table.insert(fx, blur)

	loop = RunService.RenderStepped:Connect(function(dt)
		if not root.Parent then
			stopFlying()
			return
		end

		local t = os.clock()
		local cf = camera.CFrame
		local stick = getJoystick(hum)

		-- Yön = kamera yönü x joystick (yukarı/aşağı bakınca yukarı/aşağı uçar)
		local move = cf.LookVector * stick.Y + cf.RightVector * stick.X
		if move.Magnitude > 1 then move = move.Unit end

		local target = move * currentSpeed
		velocity = velocity:Lerp(target, 1 - math.exp(-SMOOTHNESS * dt))
		linearVel.VectorVelocity = velocity

		local speed = velocity.Magnitude
		local power = math.clamp(speed / 150, 0, 1)   -- efektlerin şiddeti
		local intensity = 0.4 + 0.6 * power

		-- Karakter kameranın yönüne döner (sağ/sol)
		local look = cf.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.05 then lastFlat = flat.Unit end
		local base = CFrame.lookAt(Vector3.zero, lastFlat)

		local ref = math.max(currentSpeed, 1)
		local fwd = math.clamp(velocity:Dot(look) / ref, -1, 1)               -- kamera yönünde hız
		local side = math.clamp(velocity:Dot(base.RightVector) / ref, -1, 1)  -- yan hız
		local camPitch = math.asin(math.clamp(look.Y, -1, 1))                 -- kamera yukarı (+) / aşağı (-)

		-- Öne eğilme: ileri giderken öne yatar, yukarı bakınca dikleşir, aşağı bakınca dalışa geçer
		local tilt = math.rad(MAX_LEAN) * fwd - camPitch * LOOK_PITCH * (0.4 + 0.6 * math.abs(fwd))
		tilt = math.clamp(tilt, -math.rad(100), math.rad(170))

		local twitchP = math.noise(t * 14, 3.1) * math.rad(8) * power
		local twitchR = math.noise(t * 14, 9.7) * math.rad(12) * power
		align.CFrame = base * CFrame.Angles(
			-tilt + twitchP,
			0,
			-math.rad(MAX_LEAN * side) + twitchR
		)

		-- Kamera: açı, titreme
		local targetFov = BASE_FOV + (BOOST_FOV - BASE_FOV) * power
		camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(dt * 8, 1)
		hum.CameraOffset = Vector3.new(math.noise(t * 25, 1.3), math.noise(t * 25, 7.7), 0) * SHAKE * power

		-- Korku efektleri
		local pulse = (math.sin(t * 6) + 1) / 2
		hl.OutlineTransparency = 0.5 * (1 - pulse)
		light.Brightness = 1 + 3 * pulse

		cc.Saturation = -0.8 * intensity
		cc.Contrast = 0.35 * intensity
		cc.Brightness = -0.08 * intensity
		cc.TintColor = Color3.new(1, 1 - 0.55 * intensity, 1 - 0.55 * intensity)
		blur.Size = 8 * power

		smoke.Rate = 70 * power
		embers.Rate = 40 * power
		trail.Enabled = speed > 20
	end)
end

-- HER ŞEYİ KAPAT VE SİL
local function closeAll()
	stopFlying() -- uçuyorsa uçmayı kapatır, efektleri siler
	stopEmote()
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	camera.FieldOfView = BASE_FOV
	if gui then
		gui:Destroy()
		gui = nil
	end
end

-- YARDIMCILAR -----------------------------------------------
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

-- Basınca bir kez çalışır, basılı tutunca tekrar tekrar çalışır
local function bindRepeat(button, fn)
	local token = 0
	button.InputBegan:Connect(function(input)
		if not isPress(input) then return end
		token += 1
		local my = token
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End and token == my then
				token += 1
			end
		end)
		fn()
		task.spawn(function()
			task.wait(0.35)
			while token == my and button.Parent do
				fn()
				task.wait(0.07)
			end
		end)
	end)
end

-- Başlık çubuğundan tutup sürükleme (ekran dışına çıkmaz)
local function makeDraggable(handle, target, onMove)
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil

	handle.InputBegan:Connect(function(input)
		if not isPress(input) then return end
		dragging = true
		dragInput = input
		dragStart = input.Position
		startPos = target.AbsolutePosition - target.Parent.AbsolutePosition
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end)

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		local follow
		if dragInput.UserInputType == Enum.UserInputType.Touch then
			follow = (input == dragInput) -- sadece menüyü tutan parmak
		else
			follow = (input.UserInputType == Enum.UserInputType.MouseMovement)
		end
		if not follow then return end

		local delta = input.Position - dragStart
		local limit = target.Parent.AbsoluteSize - target.AbsoluteSize
		local x = math.clamp(startPos.X + delta.X, 0, math.max(limit.X, 0))
		local y = math.clamp(startPos.Y + delta.Y, 0, math.max(limit.Y, 0))
		target.Position = UDim2.fromOffset(x, y)
		if onMove then onMove() end
	end))
end

-- ARAYÜZ ----------------------------------------------------
gui = Instance.new("ScreenGui")
gui.Name = "UcmaKontrol"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100 -- diğer arayüzlerin üstünde görünsün
gui.Parent = player:WaitForChild("PlayerGui")

local COLS, GAP, PAD = 4, 4, 6
local TITLE_H, LABEL_H = 18, 16
local WIDTH = COLS * CELL + (COLS - 1) * GAP + PAD * 2
local GRID_H = 2 * CELL + GAP
local GRID_Y = TITLE_H + 4 + LABEL_H + 4
local HEIGHT = GRID_Y + GRID_H + PAD

local function addCorner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
end

holder = Instance.new("Frame")
holder.Name = "Holder"
holder.Size = UDim2.fromOffset(WIDTH, HEIGHT)
holder.Position = UDim2.new(1, -(WIDTH + 150), 1, -(HEIGHT + 24)) -- zıplama butonunun yanı
holder.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
holder.BackgroundTransparency = 0.25
holder.BorderSizePixel = 0
holder.Active = true
holder.Parent = gui
addCorner(holder, 8)

-- Başlık çubuğu (buradan sürükle)
local titleBar = Instance.new("TextLabel")
titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundColor3 = Color3.fromRGB(150, 15, 30)
titleBar.BackgroundTransparency = 0.1
titleBar.BorderSizePixel = 0
titleBar.Text = "≡  UÇUŞ"
titleBar.Font = Enum.Font.GothamBold
titleBar.TextSize = 11
titleBar.TextColor3 = Color3.new(1, 1, 1)
titleBar.Active = true
titleBar.Parent = holder
addCorner(titleBar, 8)

speedLabel = Instance.new("TextLabel")
speedLabel.Position = UDim2.fromOffset(PAD, TITLE_H + 4)
speedLabel.Size = UDim2.fromOffset(WIDTH - PAD * 2, LABEL_H)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 12
speedLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
speedLabel.TextStrokeTransparency = 0.5
speedLabel.Parent = holder

local grid = Instance.new("Frame")
grid.Position = UDim2.fromOffset(PAD, GRID_Y)
grid.Size = UDim2.fromOffset(WIDTH - PAD * 2, GRID_H)
grid.BackgroundTransparency = 1
grid.Parent = holder

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(CELL, CELL)
gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.FillDirectionMaxCells = COLS
gridLayout.Parent = grid

local function makeButton(parent, text, color, order)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.15
	b.Parent = parent
	addCorner(b, CELL // 2)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 7)
	pad.PaddingRight = UDim.new(0, 7)
	pad.PaddingTop = UDim.new(0, 9)
	pad.PaddingBottom = UDim.new(0, 9)
	pad.Parent = b

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 40, 40)
	stroke.Transparency = 0.3
	stroke.Thickness = 1.5
	stroke.Parent = b
	return b
end

-- Emote paneli (menünün üstünde açılır, ekranın üstüne yakınsa altında)
local emoteRows = math.ceil(#EMOTES.R15 / COLS)
local panelH = emoteRows * CELL + (emoteRows - 1) * GAP + PAD * 2

emotePanel = Instance.new("Frame")
emotePanel.Size = UDim2.fromOffset(WIDTH, panelH)
emotePanel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
emotePanel.BackgroundTransparency = 0.25
emotePanel.BorderSizePixel = 0
emotePanel.Active = true
emotePanel.Visible = false
emotePanel.Parent = holder
addCorner(emotePanel, 8)

local panelPad = Instance.new("UIPadding")
panelPad.PaddingLeft = UDim.new(0, PAD)
panelPad.PaddingRight = UDim.new(0, PAD)
panelPad.PaddingTop = UDim.new(0, PAD)
panelPad.PaddingBottom = UDim.new(0, PAD)
panelPad.Parent = emotePanel

local panelLayout = Instance.new("UIGridLayout")
panelLayout.CellSize = UDim2.fromOffset(CELL, CELL)
panelLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.FillDirectionMaxCells = COLS
panelLayout.Parent = emotePanel

local function placePanel()
	local topSpace = holder.AbsolutePosition.Y - gui.AbsolutePosition.Y
	if topSpace < panelH + 8 then
		emotePanel.Position = UDim2.fromOffset(0, HEIGHT + 4)
	else
		emotePanel.Position = UDim2.fromOffset(0, -(panelH + 4))
	end
end

for i, e in ipairs(EMOTES.R15) do
	local b = makeButton(emotePanel, e[1], Color3.fromRGB(30, 30, 40), i)
	b.Activated:Connect(function()
		playEmote(i)
	end)
	emoteButtons[i] = b
end

-- Üst sıra: UÇ | MAX | MIN | X
flyButton = makeButton(grid, "UÇ", Color3.fromRGB(190, 20, 40), 1)
flyButton.Activated:Connect(function()
	if flying then stopFlying() else startFlying() end
end)

makeButton(grid, "MAX", Color3.fromRGB(120, 0, 0), 2).Activated:Connect(function()
	setSpeed(MAX_SPEED)
end)

makeButton(grid, "MIN", Color3.fromRGB(40, 40, 50), 3).Activated:Connect(function()
	setSpeed(MIN_SPEED)
end)

makeButton(grid, "X", Color3.fromRGB(0, 0, 0), 4).Activated:Connect(closeAll)

-- Alt sıra: ▲ hız artır | ▼ hız azalt | 😀 emote
bindRepeat(makeButton(grid, "▲", Color3.fromRGB(30, 30, 40), 5), function()
	changeSpeed(SPEED_STEP)
end)
bindRepeat(makeButton(grid, "▼", Color3.fromRGB(30, 30, 40), 6), function()
	changeSpeed(1 / SPEED_STEP)
end)
makeButton(grid, "😀", Color3.fromRGB(30, 30, 40), 7).Activated:Connect(function()
	placePanel()
	emotePanel.Visible = not emotePanel.Visible
end)

makeDraggable(titleBar, holder, placePanel)

table.insert(connections, player.CharacterRemoving:Connect(function()
	stopFlying()
	stopEmote()
end))

updateUI()
print("Uçuş menüsü v2 yüklendi")
