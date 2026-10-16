-- WordChain Helper | v3.0 (Updated: used-word tracker from table history log) | Large Dynamic Island UI

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local UIS           = game:GetService("UserInputService")
local LP            = Players.LocalPlayer
local PGui          = LP:WaitForChild("PlayerGui")

local CFG = {
    SCAN_RATE   = 0.4,
    MIN_TXTSIZE = 14,
    MIN_LEN     = 1,
    MAX_LEN     = 40,
    MAX_SUGGEST = 30,

    -- ความยาวคำแนะนำขั้นต่ำ (หน่วย: ตัวอักษรไทย) ปรับได้จาก UI ด้วยปุ่ม -/+
    MIN_SUGGEST_CHARS = 6,

    -- ตั้งค่าคีย์ลัดที่นี่ (Keyboard Shortcuts)
    KEY_REMOVE  = Enum.KeyCode.LeftAlt, -- แนะนำใช้ Alt ซ้าย จะกดง่ายสุดตอนกำลังพิมพ์
    KEY_RESET   = Enum.KeyCode.Delete,

    -- ═══ ระบบเก็บคำที่ถูกใช้ไปแล้ว (Used-word tracker) ═══
    TRACK_USED           = true,  -- เปิด/ปิดระบบ
    HISTORY_VISIBLE_ONLY = true,  -- นับเฉพาะ label ที่มองเห็นอยู่จริง (ไม่นับ UI ที่ซ่อนอยู่)
    CLEAR_AFTER_EMPTY    = 8,     -- history log ว่างต่อเนื่องกี่วินาที = จบรอบ → ล้างคำที่ใช้แล้ว (0 = ไม่ล้างอัตโนมัติ)
    LOG_STRIP_PREFIX     = true,  -- บรรทัดที่มี ":" ให้เอาเฉพาะข้างหลัง (ตัดชื่อผู้เล่นใน "ชื่อ: คำ")
    KEY_DUMP             = Enum.KeyCode.Insert, -- dump path/ข้อความของ label ภาษาไทยทั้งหมด (print + copy ลง clipboard)
}

local PATH_WHITELIST = { "InputBar", "Match", "GameWord", "CurrentWord", "WordDisplay" }
local PATH_BLACKLIST = { "Menu", "Settings", "Lobby", "Profile", "Button", "Mode", "Code" }

-- ═══ HISTORY LOG (ประวัติคำบนโต๊ะ) ═══
-- บอกสคริปต์ว่า TextLabel ตัวไหนคือ history log และเป็นของใคร
--   match = ข้อความที่ต้องอยู่ใน GetFullName() ของ label (เทียบตรง ๆ ไม่ใช่ pattern)
--   owner = "me" หรือ "other" (ใช้แยกสถิติ/ดีบัก — คำจากทั้งสองฝั่งถูกกรองออกเหมือนกัน)
-- กดปุ่ม KEY_DUMP (Insert) ในเกมเพื่อดู path จริง แล้วคัดลอกมาใส่ตรงนี้
local HISTORY_SOURCES = {
    -- { owner = "me",    match = "PlayerGui.Game.Table.MyHistory" },
    -- { owner = "other", match = "PlayerGui.Game.Table.OpponentHistory" },
}
-- ถ้า HISTORY_SOURCES ว่าง จะเดาจาก keyword เหล่านี้แทน (owner = "unknown")
local HISTORY_KEYWORDS = { "History", "UsedWords", "WordLog", "WordList" }

-- ════════════════════════════════════════════
--  WORD DB
-- ════════════════════════════════════════════
local SOURCE_URL = "https://raw.githubusercontent.com/PyThaiNLP/pythainlp/dev/pythainlp/corpus/words_th.txt"
local CACHE_PATH = "WordDB_ptnlp.txt"

-- คลังความถี่คำ (Thai National Corpus) ใช้จัดลำดับว่าคำไหน "คนรู้จัก" มากกว่ากัน
local FREQ_SOURCE_URL = "https://raw.githubusercontent.com/PyThaiNLP/pythainlp/dev/pythainlp/corpus/tnc_freq.txt"
local FREQ_CACHE_PATH = "WordFreq_tnc.txt"

local function firstChar(str)
    if #str == 0 then return nil end
    local b = str:byte(1)
    if     b >= 0xF0 then return str:sub(1, 4)
    elseif b >= 0xE0 then return str:sub(1, 3)
    elseif b >= 0xC0 then return str:sub(1, 2)
    else                   return str:sub(1, 1) end
end

-- เช็คว่าทั้งคำประกอบด้วยอักขระไทยล้วน ๆ (บล็อก U+0E00–U+0E7F เท่านั้น)
-- ตัดคำที่มีจุด (.), เว้นวรรค, ตัวเลข, เครื่องหมายขีด ฯลฯ ปนอยู่ทิ้งไปเลย
local function isThaiOnlyWord(word)
    local len = #word
    if len == 0 or len % 3 ~= 0 then return false end
    for i = 1, len, 3 do
        local b1, b2, b3 = word:byte(i, i + 2)
        if b1 ~= 0xE0 or (b2 ~= 0xB8 and b2 ~= 0xB9) or not b3 or b3 < 0x80 or b3 > 0xBF then
            return false
        end
    end
    return true
end

local function buildDB(text)
    local db = {}
    for line in text:gmatch("[^\n\r]+") do
        local word = line:match("^%s*(.-)%s*$")
        if word and #word >= 2 and isThaiOnlyWord(word) then
            local fc = firstChar(word)
            if fc then
                if not db[fc] then db[fc] = {} end
                table.insert(db[fc], word)
            end
        end
    end
    return db
end

-- แปลงไฟล์ tnc_freq.txt (รูปแบบ "คำ<TAB>จำนวนครั้ง") เป็นตาราง word -> count
local function buildFreqDB(text)
    local freq = {}
    for line in text:gmatch("[^\n\r]+") do
        local word, countStr = line:match("^(.-)\t(%d+)%s*$")
        if word and countStr then
            freq[word] = tonumber(countStr)
        end
    end
    return freq
end

local WORD_DB
local WORD_FREQ

local function loadWordDB()
    if isfile and isfile(CACHE_PATH) then
        local ok, cached = pcall(readfile, CACHE_PATH)
        if ok and cached and #cached > 500 then
            local db = buildDB(cached)
            local n = 0
            for _, v in pairs(db) do n = n + #v end
            if n > 1000 then return db end
        end
    end
    local ok, body = pcall(function() return game:HttpGet(SOURCE_URL) end)
    if not ok or not body or #body < 500 then
        warn("[WC Helper] โหลด WordDB ไม่สำเร็จ")
        return {}
    end
    if writefile then pcall(writefile, CACHE_PATH, body) end
    return buildDB(body)
end

local function loadFreqDB()
    if isfile and isfile(FREQ_CACHE_PATH) then
        local ok, cached = pcall(readfile, FREQ_CACHE_PATH)
        if ok and cached and #cached > 500 then
            local freq = buildFreqDB(cached)
            local n = 0
            for _ in pairs(freq) do n = n + 1 end
            if n > 1000 then return freq end
        end
    end
    local ok, body = pcall(function() return game:HttpGet(FREQ_SOURCE_URL) end)
    if not ok or not body or #body < 500 then
        warn("[WC Helper] โหลด WordFreq ไม่สำเร็จ (จะเรียงคำตามความยาวแทนความถี่)")
        return {}
    end
    if writefile then pcall(writefile, FREQ_CACHE_PATH, body) end
    return buildFreqDB(body)
end

WORD_DB   = loadWordDB()
WORD_FREQ = loadFreqDB()

-- ════════════════════════════════════════════
--  BLACKLIST
-- ════════════════════════════════════════════
local blacklisted = {}

-- คำที่ถูกใช้ไปแล้วในเกม (set: คำ -> owner) — เติมโดย tracker, กรองออกใน getSuggestions
local usedWords = {}
local usedCount = 0

-- ════════════════════════════════════════════
--  UTF-8 HELPERS
-- ════════════════════════════════════════════
local function lastChar(str)
    local i = #str
    while i >= 1 do
        local b = str:byte(i)
        if b < 0x80 or b >= 0xC0 then
            if b >= 0xE0 then return str:sub(i, i + 2)
            else return str:sub(i, i) end
        end
        i = i - 1
    end
    return nil
end

-- นับจำนวน "ตัวอักษร" (code point) จริง ๆ ไม่ใช่จำนวนไบต์
local function utf8Len(str)
    local n = 0
    for i = 1, #str do
        local b = str:byte(i)
        if b < 0x80 or b >= 0xC0 then
            n = n + 1
        end
    end
    return n
end

-- ════════════════════════════════════════════
--  SUGGESTION ENGINE
-- ════════════════════════════════════════════
local function getSuggestions(prefix)
    local plen = #prefix
    local out  = {}
    local fc   = firstChar(prefix)
    if not fc then return out end
    local bucket = WORD_DB[fc]
    if not bucket then return out end

    local minChars = CFG.MIN_SUGGEST_CHARS

    for _, w in ipairs(bucket) do
        if #w > plen and w:sub(1, plen) == prefix and not blacklisted[w] and not usedWords[w] and utf8Len(w) >= minChars then
            table.insert(out, w)
        end
    end

    -- เรียงคำที่ "คนรู้จักเยอะกว่า" (ความถี่ใน TNC สูงกว่า) ไว้ก่อน
    -- ถ้าความถี่เท่ากัน (หรือไม่มีข้อมูลความถี่เลย) ให้คำที่สั้นกว่ามาก่อนเหมือนเดิม
    table.sort(out, function(a, b)
        local fa = WORD_FREQ[a] or 0
        local fb = WORD_FREQ[b] or 0
        if fa ~= fb then
            return fa > fb
        end
        return #a < #b
    end)

    local result = {}
    for i = 1, math.min(#out, CFG.MAX_SUGGEST) do
        result[i] = out[i]
    end
    return result
end

-- ════════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════════
local lastWord           = ""
local currentSuggestions = {}
local currentIndex       = 1

-- ════════════════════════════════════════════
--  GUI — DYNAMIC ISLAND
-- ════════════════════════════════════════════
local COLORS = {
    bg        = Color3.fromHex("0D0D0D"),
    border    = Color3.fromHex("2A2A2A"),
    accent    = Color3.fromHex("4CFFE8"),
    text      = Color3.fromHex("EAEAEA"),
    dim       = Color3.fromHex("888888"),
    del_bg    = Color3.fromHex("1E1010"),
    del_txt   = Color3.fromHex("FF6B6B"),
    rst_bg    = Color3.fromHex("101E1A"),
    rst_txt   = Color3.fromHex("4CFFE8"),
    lastchar  = Color3.fromHex("FFB347"),
    set_bg    = Color3.fromHex("14181C"),
    set_txt   = Color3.fromHex("AEB4BA"),
}

-- ลบ UI เก่าทิ้งถ้ามี
if PGui:FindFirstChild("WC_Helper") then
    PGui:FindFirstChild("WC_Helper"):Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name           = "WC_Helper"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent         = PGui

-- Dynamic Island container
local island = Instance.new("Frame")
island.Name             = "DynamicIsland"
island.AnchorPoint      = Vector2.new(0.5, 0)
island.Position         = UDim2.new(0.5, 0, 0, -100)
island.Size             = UDim2.new(0, 0, 0, 52)
island.AutomaticSize    = Enum.AutomaticSize.X
island.BackgroundColor3 = COLORS.bg
island.BorderSizePixel  = 0
island.Parent           = gui

local islandCorner = Instance.new("UICorner", island)
islandCorner.CornerRadius = UDim.new(0, 26)

local islandStroke = Instance.new("UIStroke", island)
islandStroke.Color     = COLORS.border
islandStroke.Thickness = 1

local islandPadding = Instance.new("UIPadding", island)
islandPadding.PaddingLeft   = UDim.new(0, 14)
islandPadding.PaddingRight  = UDim.new(0, 14)

local islandLayout = Instance.new("UIListLayout", island)
islandLayout.FillDirection      = Enum.FillDirection.Horizontal
islandLayout.VerticalAlignment  = Enum.VerticalAlignment.Center
islandLayout.Padding            = UDim.new(0, 12)
islandLayout.SortOrder          = Enum.SortOrder.LayoutOrder

-- badge (left)
local badge = Instance.new("Frame")
badge.Size             = UDim2.new(0, 36, 0, 36)
badge.BackgroundColor3 = COLORS.accent
badge.BorderSizePixel  = 0
badge.LayoutOrder      = 1
badge.Parent           = island
Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)

local badgeScale = Instance.new("UIScale", badge)

local badgeLabel = Instance.new("TextLabel")
badgeLabel.Size              = UDim2.new(1, 0, 1, 0)
badgeLabel.BackgroundTransparency = 1
badgeLabel.Font              = Enum.Font.GothamBold
badgeLabel.TextSize          = 16
badgeLabel.TextColor3        = COLORS.bg
badgeLabel.Text              = "W"
badgeLabel.Parent            = badge

-- text stack (middle)
local textStack = Instance.new("Frame")
textStack.BackgroundTransparency = 1
textStack.Size           = UDim2.new(0, 0, 0, 42)
textStack.AutomaticSize  = Enum.AutomaticSize.X
textStack.LayoutOrder    = 2
textStack.Parent         = island

local stackLayout = Instance.new("UIListLayout", textStack)
stackLayout.FillDirection     = Enum.FillDirection.Vertical
stackLayout.SortOrder         = Enum.SortOrder.LayoutOrder
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Size              = UDim2.new(0, 0, 0, 14)
subtitleLabel.AutomaticSize     = Enum.AutomaticSize.X
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Font              = Enum.Font.Gotham
subtitleLabel.TextSize          = 11
subtitleLabel.TextColor3        = COLORS.dim
subtitleLabel.TextXAlignment    = Enum.TextXAlignment.Left
subtitleLabel.Text              = "สถานะ"
subtitleLabel.LayoutOrder       = 1
subtitleLabel.Parent            = textStack

local wordRow = Instance.new("Frame")
wordRow.BackgroundTransparency = 1
wordRow.Size            = UDim2.new(0, 0, 0, 24)
wordRow.AutomaticSize   = Enum.AutomaticSize.X
wordRow.LayoutOrder     = 2
wordRow.Parent          = textStack

local wordRowLayout = Instance.new("UIListLayout", wordRow)
wordRowLayout.FillDirection     = Enum.FillDirection.Horizontal
wordRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
wordRowLayout.Padding           = UDim.new(0, 6)

local wordLabel = Instance.new("TextLabel")
wordLabel.Size              = UDim2.new(0, 0, 1, 0)
wordLabel.AutomaticSize      = Enum.AutomaticSize.X
wordLabel.BackgroundTransparency = 1
wordLabel.Font              = Enum.Font.GothamBold
wordLabel.TextSize          = 18
wordLabel.TextColor3        = COLORS.text
wordLabel.TextXAlignment    = Enum.TextXAlignment.Left
wordLabel.Text              = "รอคำจากเกม..."
wordLabel.LayoutOrder       = 1
wordLabel.Parent            = wordRow

local lastCharChip = Instance.new("TextLabel")
lastCharChip.Size              = UDim2.new(0, 0, 1, 0)
lastCharChip.AutomaticSize      = Enum.AutomaticSize.X
lastCharChip.BackgroundTransparency = 1
lastCharChip.Font              = Enum.Font.GothamBold
lastCharChip.TextSize          = 14
lastCharChip.TextColor3        = COLORS.lastchar
lastCharChip.TextXAlignment    = Enum.TextXAlignment.Left
lastCharChip.Text              = ""
lastCharChip.LayoutOrder       = 2
lastCharChip.Parent            = wordRow

-- icon button factory with Animations
local function makeIconButton(iconAssetId, fallbackText, bgColor, iconColor, order)
    local btn = Instance.new("ImageButton")
    btn.Size             = UDim2.new(0, 34, 0, 34)
    btn.BackgroundColor3 = bgColor
    btn.BorderSizePixel  = 0
    btn.AutoButtonColor  = false
    btn.LayoutOrder      = order
    btn.Visible          = false
    btn.Parent           = island
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

    local btnScale = Instance.new("UIScale", btn)

    local stroke = Instance.new("UIStroke", btn)
    stroke.Color        = Color3.new(1, 1, 1)
    stroke.Transparency = 0.9
    stroke.Thickness    = 1

    if iconAssetId and iconAssetId ~= "" then
        local img = Instance.new("ImageLabel")
        img.Size                   = UDim2.new(0, 16, 0, 16)
        img.AnchorPoint            = Vector2.new(0.5, 0.5)
        img.Position               = UDim2.new(0.5, 0, 0.5, 0)
        img.BackgroundTransparency = 1
        img.Image                  = iconAssetId
        img.ImageColor3            = iconColor
        img.Parent                 = btn
    else
        local txt = Instance.new("TextLabel")
        txt.Size                   = UDim2.new(1, 0, 1, 0)
        txt.BackgroundTransparency = 1
        txt.Font                   = Enum.Font.GothamBold
        txt.TextSize               = 14
        txt.TextColor3             = iconColor
        txt.Text                   = fallbackText
        txt.Parent                 = btn
    end

    btn.MouseEnter:Connect(function()
        TweenService:Create(btnScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.1}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btnScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.0}):Play()
    end)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btnScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.9}):Play()
    end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btnScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.1}):Play()
    end)

    return btn, btnScale
end

-- ตัวปรับความยาวคำขั้นต่ำ (แสดงตลอดเวลา ไม่ผูกกับสถานะมีคำ/ไม่มีคำ)
local lenMinusBtn, lenMinusScale = makeIconButton("", "-", COLORS.set_bg, COLORS.set_txt, 3)
lenMinusBtn.Visible = true

local lenLabel = Instance.new("TextLabel")
lenLabel.Size              = UDim2.new(0, 20, 0, 34)
lenLabel.BackgroundTransparency = 1
lenLabel.Font              = Enum.Font.GothamBold
lenLabel.TextSize          = 14
lenLabel.TextColor3        = COLORS.text
lenLabel.TextXAlignment    = Enum.TextXAlignment.Center
lenLabel.Text              = tostring(CFG.MIN_SUGGEST_CHARS)
lenLabel.LayoutOrder       = 4
lenLabel.Parent            = island

local lenPlusBtn, lenPlusScale = makeIconButton("", "+", COLORS.set_bg, COLORS.set_txt, 5)
lenPlusBtn.Visible = true

local resetBtn, resetScale   = makeIconButton("rbxassetid://10747373176", "↺", COLORS.rst_bg, COLORS.rst_txt, 6)
local removeBtn, removeScale = makeIconButton("rbxassetid://10747384394", "✕", COLORS.del_bg, COLORS.del_txt, 7)

-- ════════════════════════════════════════════
--  DISPLAY / PULSE / ANIMATION
-- ════════════════════════════════════════════
local function pulse(scaleObj)
    scaleObj.Scale = 0.8
    TweenService:Create(
        scaleObj,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()
end

local function toggleButtons(visible)
    if visible and not resetBtn.Visible then
        resetBtn.Visible = true
        removeBtn.Visible = true
        resetScale.Scale = 0
        removeScale.Scale = 0
        TweenService:Create(resetScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
        task.wait(0.05)
        TweenService:Create(removeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
    elseif not visible and resetBtn.Visible then
        resetBtn.Visible = false
        removeBtn.Visible = false
    end
end

local function showCurrent()
    local word = currentSuggestions[currentIndex]
    local hasWord = (lastWord ~= "" and lastWord ~= "__none__")

    if hasWord then
        subtitleLabel.Text = "ต่อจาก " .. lastWord .. "  ·  ใช้แล้ว " .. usedCount

        if word then
            wordLabel.Text     = word
            lastCharChip.Text  = "→" .. (lastChar(word) or "?")
        else
            wordLabel.Text     = "ไม่มีคำแนะนำ"
            lastCharChip.Text  = ""
        end

        toggleButtons(true)
    else
        subtitleLabel.Text = "สถานะ"
        wordLabel.Text     = "รอคำจากเกม..."
        lastCharChip.Text  = ""

        toggleButtons(false)
    end

    pulse(badgeScale)
end

local function refreshSuggestions(prefix)
    currentSuggestions = getSuggestions(prefix)
    currentIndex       = 1
    showCurrent()
end

-- ════════════════════════════════════════════
--  CORE FUNCTIONS (REMOVE & RESET)
-- ════════════════════════════════════════════
local function doRemove()
    local word = currentSuggestions[currentIndex]
    if word then
        blacklisted[word] = true
        refreshSuggestions(lastWord)
        pulse(removeScale)
    end
end

local function doReset()
    blacklisted = {}
    if lastWord ~= "" and lastWord ~= "__none__" then
        refreshSuggestions(lastWord)
    else
        currentSuggestions = {}
        currentIndex        = 1
        showCurrent()
    end
    pulse(resetScale)
end

local function setMinSuggestChars(delta)
    CFG.MIN_SUGGEST_CHARS = math.clamp(CFG.MIN_SUGGEST_CHARS + delta, 1, 15)
    lenLabel.Text = tostring(CFG.MIN_SUGGEST_CHARS)
    if lastWord ~= "" and lastWord ~= "__none__" then
        refreshSuggestions(lastWord)
    end
end

-- ════════════════════════════════════════════
--  INPUT HANDLERS (BUTTONS & HOTKEYS)
-- ════════════════════════════════════════════
removeBtn.MouseButton1Click:Connect(doRemove)
resetBtn.MouseButton1Click:Connect(doReset)
lenMinusBtn.MouseButton1Click:Connect(function()
    setMinSuggestChars(-1)
    pulse(lenMinusScale)
end)
lenPlusBtn.MouseButton1Click:Connect(function()
    setMinSuggestChars(1)
    pulse(lenPlusScale)
end)

UIS.InputBegan:Connect(function(input, gameProcessedEvent)
    -- ลบเงื่อนไข if gameProcessedEvent then return end ออก
    -- ทำให้ถึงแม้กำลังพิมพ์ข้อความอยู่ก็สามารถกดปุ่ม Alt หรือ Delete เพื่อใช้งานได้เลย
    if input.KeyCode == CFG.KEY_REMOVE then
        doRemove()
    elseif input.KeyCode == CFG.KEY_RESET then
        doReset()
    end
end)

-- ════════════════════════════════════════════
--  SCANNER
-- ════════════════════════════════════════════
local function isValidWord(str)
    if str:match("[%a%d]") then return true end
    for i = 1, #str do
        local b = str:byte(i)
        if b == 0xE0 then
            local b2 = str:byte(i + 1)
            if b2 == 0xB8 or b2 == 0xB9 then return true end
        end
    end
    return false
end

local function pathAllowed(path)
    for _, kw in ipairs(PATH_BLACKLIST) do
        if path:find(kw, 1, true) then return false end
    end
    for _, kw in ipairs(PATH_WHITELIST) do
        if path:find(kw, 1, true) then return true end
    end
    return false
end

-- ════════════════════════════════════════════
--  USED-WORD TRACKER (history log → set)
-- ════════════════════════════════════════════
local lastHistorySeen = os.clock()

-- ดึง "ชุดอักขระไทยที่ติดกัน" ออกจากข้อความ (ตัดชื่อ/ตัวเลข/เครื่องหมายทิ้ง)
local function extractThaiRuns(text)
    local runs, buf = {}, {}
    local i, n = 1, #text
    while i <= n do
        local b1, b2, b3 = text:byte(i, i + 2)
        if b1 == 0xE0 and (b2 == 0xB8 or b2 == 0xB9) and b3 and b3 >= 0x80 and b3 <= 0xBF then
            buf[#buf + 1] = text:sub(i, i + 2)
            i = i + 3
        else
            if #buf > 0 then
                runs[#runs + 1] = table.concat(buf)
                buf = {}
            end
            i = i + 1
        end
    end
    if #buf > 0 then runs[#runs + 1] = table.concat(buf) end
    return runs
end

-- แปลงข้อความใน history label เป็นรายการคำ (รองรับทั้ง 1 label = 1 คำ และ 1 label = หลายบรรทัด)
local function extractWords(text)
    local words = {}
    text = text:gsub("<[^>]*>", "") -- ตัด RichText tag
    for rawLine in text:gmatch("[^\n\r]+") do
        local line = rawLine
        if CFG.LOG_STRIP_PREFIX then
            local after = line:match(".*:%s*(.*)$")
            if after then line = after end
        end
        for _, run in ipairs(extractThaiRuns(line)) do
            if utf8Len(run) >= 2 then
                words[#words + 1] = run
            end
        end
    end
    return words
end

-- label (และ parent ทุกชั้น) มองเห็นอยู่จริงไหม
local function isShown(obj)
    local cur = obj
    while cur do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("LayerCollector") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

-- path นี้เป็น history log ของใคร (nil = ไม่ใช่ history log)
local function classifyHistory(path)
    if #HISTORY_SOURCES > 0 then
        for _, src in ipairs(HISTORY_SOURCES) do
            if path:find(src.match, 1, true) then return src.owner end
        end
        return nil
    end
    for _, kw in ipairs(PATH_BLACKLIST) do
        if path:find(kw, 1, true) then return nil end
    end
    for _, kw in ipairs(HISTORY_KEYWORDS) do
        if path:find(kw, 1, true) then return "unknown" end
    end
    return nil
end

local function clearUsed()
    usedWords = {}
    usedCount = 0
end

-- เติมคำจาก history ที่สแกนได้ลง set — คืน true ถ้า set เปลี่ยน
local function updateUsedWords(hits)
    if #hits == 0 then
        if CFG.CLEAR_AFTER_EMPTY > 0 and usedCount > 0
            and os.clock() - lastHistorySeen >= CFG.CLEAR_AFTER_EMPTY then
            clearUsed()
            return true
        end
        return false
    end

    lastHistorySeen = os.clock()
    local changed = false
    for _, h in ipairs(hits) do
        for _, w in ipairs(extractWords(h.text)) do
            if not usedWords[w] then
                usedWords[w] = h.owner
                usedCount = usedCount + 1
                changed = true
            end
        end
    end
    return changed
end

-- ════════════════════════════════════════════
--  SCAN (คำปัจจุบัน + history log ในรอบเดียว)
-- ════════════════════════════════════════════
local function scanAll()
    local candidates, history = {}, {}
    local function recurse(root)
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextBox") then
                local txt = obj.Text or ""
                if txt ~= "" and not obj:IsDescendantOf(gui) then
                    local path = obj:GetFullName()

                    -- (1) คำปัจจุบันที่ต้องต่อ (ตรรกะเดิม)
                    local ts = obj.TextSize or 0
                    if #txt >= CFG.MIN_LEN and #txt <= CFG.MAX_LEN
                        and ts >= CFG.MIN_TXTSIZE
                        and isValidWord(txt)
                        and pathAllowed(path)
                    then
                        table.insert(candidates, { text = txt, size = ts, path = path })
                    end

                    -- (2) history log บนโต๊ะ
                    if CFG.TRACK_USED then
                        local owner = classifyHistory(path)
                        if owner and (not CFG.HISTORY_VISIBLE_ONLY or isShown(obj)) then
                            table.insert(history, { text = txt, owner = owner, path = path })
                        end
                    end
                end
            end
        end
    end
    recurse(game:GetService("Workspace"))
    recurse(LP.PlayerGui)
    table.sort(candidates, function(a, b) return a.size > b.size end)
    return candidates, history
end

-- ════════════════════════════════════════════
--  DUMP (ช่วยหา path ของ history log)
-- ════════════════════════════════════════════
local function clip(s, n)
    local len = utf8.len(s)
    if len and len > n then
        return s:sub(1, utf8.offset(s, n + 1) - 1) .. "…"
    end
    return s
end

local function dumpReport()
    local lines = {}
    local MAX_LINES = 150

    local counts = {}
    for _, owner in pairs(usedWords) do
        counts[owner] = (counts[owner] or 0) + 1
    end
    local parts = {}
    for owner, n in pairs(counts) do parts[#parts + 1] = owner .. "=" .. n end
    lines[#lines + 1] = ("[WC Helper] used=%d (%s) | sources=%s"):format(
        usedCount,
        #parts > 0 and table.concat(parts, ", ") or "-",
        #HISTORY_SOURCES > 0 and "config" or "keyword-guess"
    )

    local function addRoot(root)
        for _, obj in ipairs(root:GetDescendants()) do
            if #lines >= MAX_LINES then return end
            if (obj:IsA("TextLabel") or obj:IsA("TextBox"))
                and not obj:IsDescendantOf(gui)
                and #extractThaiRuns(obj.Text or "") > 0
                and isShown(obj)
            then
                local t = clip((obj.Text:gsub("[\n\r]+", " ⏎ ")), 40)
                lines[#lines + 1] = ("%s | size=%d | %s | \"%s\""):format(
                    obj.ClassName, obj.TextSize or 0, obj:GetFullName(), t
                )
            end
        end
    end
    addRoot(game:GetService("Workspace"))
    addRoot(LP.PlayerGui)
    if #lines >= MAX_LINES then lines[#lines + 1] = "... (ตัดที่ " .. MAX_LINES .. " บรรทัด)" end

    for _, l in ipairs(lines) do print(l) end
    if setclipboard then pcall(setclipboard, table.concat(lines, "\n")) end
end

UIS.InputBegan:Connect(function(input)
    if input.KeyCode == CFG.KEY_DUMP then
        dumpReport()
    end
end)

-- ════════════════════════════════════════════
--  STARTUP ANIMATION & MAIN LOOP
-- ════════════════════════════════════════════
TweenService:Create(
    island,
    TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Position = UDim2.new(0.5, 0, 0, 16) }
):Play()

task.spawn(function()
    while true do
        task.wait(CFG.SCAN_RATE)
        local results, history = scanAll()
        local top         = results[1]
        local usedChanged = updateUsedWords(history)

        if top and top.text ~= lastWord then
            lastWord = top.text
            refreshSuggestions(top.text)

        elseif not top and lastWord ~= "__none__" then
            lastWord            = "__none__"
            currentSuggestions  = {}
            currentIndex        = 1
            showCurrent()

        elseif usedChanged and lastWord ~= "" and lastWord ~= "__none__" then
            -- มีคำใหม่เข้า set ระหว่างที่คำปัจจุบันยังเหมือนเดิม → คำนวณคำแนะนำใหม่
            refreshSuggestions(lastWord)
        end
    end
end)

print("[WC Helper] v3.0 | used-word tracker + Thai-only filter + common-word sort + length stepper | PyThaiNLP + TNC | online")
