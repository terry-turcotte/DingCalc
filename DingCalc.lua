-- DingCalc: kills and quests to next level, by mob level and quest level.
-- Mirrors the Wowhead "WoW Forever experience calculator" tables, live, in game.

local ADDON = ...
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

------------------------------------------------------------------------
-- XP formulas (Classic rules; match Wowhead's Forever calculator)
------------------------------------------------------------------------

-- Zero-difference value: how fast XP drops for lower-level mobs.
local function ZeroDiff(p)
    if p <= 7 then return 5
    elseif p <= 9 then return 6
    elseif p <= 11 then return 7
    elseif p <= 15 then return 8
    elseif p <= 19 then return 9
    elseif p <= 29 then return 11
    elseif p <= 39 then return 12
    elseif p <= 44 then return 13
    elseif p <= 49 then return 14
    elseif p <= 54 then return 15
    elseif p <= 59 then return 16
    else return 17 end
end

-- Highest mob level that is gray (gives no XP).
local function GrayLevel(p)
    if p <= 5 then return 0
    elseif p <= 39 then return p - floor(p / 10) - 5
    elseif p <= 59 then return p - floor(p / 5) - 1
    else return p - 9 end
end

-- Base XP for one solo kill of a normal mob.
local function MobXP(p, m)
    if m <= GrayLevel(p) then return 0 end
    if m >= p then
        local d = min(m - p, 4)
        -- base * (1 + 0.05*d), rounded with ties down (integer math, matches Wowhead)
        return ceil(((p * 5 + 45) * (20 + d) - 10) / 20)
    end
    return floor((m * 5 + 45) * (1 - (p - m) / ZeroDiff(p)) + 0.5)
end

-- Quest XP penalty once you are 6+ levels above the quest.
-- Turn-ins with a penalty below this are not learned from: working back to
-- full XP from x0.4 or less multiplies the reward's rounding error 2.5-10x.
local MIN_LEARN_MULT = 0.6

local function QuestMult(p, q)
    local d = p - q
    if d <= 5 then return 1
    elseif d == 6 then return 0.8
    elseif d == 7 then return 0.6
    elseif d == 8 then return 0.4
    elseif d == 9 then return 0.2
    else return 0.1 end
end

-- Quests are averaged separately by type: normal, elite (group) and dungeon
-- (raid quests count as dungeon), since elite and dungeon quests give more XP.
local QUEST_TYPES = { "normal", "elite", "dungeon" }
local TYPE_LABEL = { normal = "Normal", elite = "Elite", dungeon = "Dungeon" }

-- Typical normal quest XP by quest level (Wowhead Forever calculator).
-- Other levels and types are learned from your own turn-ins, or estimated ("~").
local SEED_QUEST_XP = {
    [5] = 450, [6] = 540, [7] = 630, [8] = 700, [9] = 780,
    [10] = 840, [11] = 880, [12] = 910, [13] = 910, [14] = 980,
}

local function MobBase(l) return l * 5 + 45 end

local DB      -- account-wide (DingCalcDB): learned quest XP, window position, tooltip toggle
local CharDB  -- per character (DingCalcCharDB): buff checkboxes

-- Learned turn-ins per type and level: { n = count, sum = total,
-- hist = { [full XP rounded to 5] = count } }. The typical value is the
-- median (P50) of hist: quest XP comes in a few fixed amounts, and the median
-- lands on the normal one, while the mean is dragged down by small quest-chain
-- steps (talk to X, deliver a letter) that give only a few hundred XP.
local function HistMedian(hist, n)
    if not hist or not n or n <= 0 then return nil end
    local vals = {}
    for v in pairs(hist) do vals[#vals + 1] = v end
    table.sort(vals)
    -- Values at sorted positions lo and hi (equal when n is odd).
    local lo, hi = floor((n + 1) / 2), floor(n / 2) + 1
    local seen, a, b = 0, nil, nil
    for _, v in ipairs(vals) do
        seen = seen + hist[v]
        if not a and seen >= lo then a = v end
        if not b and seen >= hi then b = v; break end
    end
    return floor((a + b) / 2 + 0.5)
end

local function KnownQuestXP(t, q)
    local l = DB and DB.quest and DB.quest[t] and DB.quest[t][q]
    local seed = t == "normal" and SEED_QUEST_XP[q]
    if l and l.n >= 3 then return HistMedian(l.hist, l.n) end
    if seed then return seed end
    if l and l.n > 0 then return HistMedian(l.hist, l.n) end
    return nil
end

-- Returns typical full XP for a quest of type t and level q, and whether it
-- is an estimate. Returns nil for elite/dungeon until one has been turned in.
local function TypicalQuestXP(t, q)
    local xp = KnownQuestXP(t, q)
    if xp then return xp, false end
    -- Scale from the nearest known level of the same type.
    for d = 1, 60 do
        for _, k in ipairs({ q - d, q + d }) do
            if k >= 1 then
                local kxp = KnownQuestXP(t, k)
                if kxp then
                    return floor(kxp * MobBase(q) / MobBase(k) / 5 + 0.5) * 5, true
                end
            end
        end
    end
    if t == "normal" then return MobBase(q) * 9, true end
    return nil
end

-- Kills needed, counting rested XP (doubles kill XP until the pool runs out).
local function KillsNeeded(xp, remain, rested)
    if xp <= 0 then return nil end
    if remain <= 0 then return 0 end
    local n = 0
    if rested and rested > 0 then
        local k = floor(rested / xp)
        if k * 2 * xp >= remain then return ceil(remain / (2 * xp)) end
        remain = remain - k * 2 * xp
        n = k
        local r = rested - k * xp
        if r > 0 then
            n = n + 1
            remain = remain - (xp + r)
            if remain <= 0 then return n end
        end
    end
    return n + ceil(remain / xp)
end

-- Difficulty bands shown in the window, by mob or quest level. Red is left
-- out (rarely fought or quested); gray is left out (no kill XP).
local BANDS = {
    { name = "Green",  color = "40c040", lo = function(p) return GrayLevel(p) + 1 end, hi = function(p) return p - 3 end },
    { name = "Yellow", color = "ffff00", lo = function(p) return p - 2 end,            hi = function(p) return p + 2 end },
    { name = "Orange", color = "ff8040", lo = function(p) return p + 3 end,            hi = function(p) return p + 4 end },
}

local function DiffColor(p, l)
    local d = l - p
    if d >= 5 then return "ff2020"
    elseif d >= 3 then return "ff8040"
    elseif d >= -2 then return "ffff00"
    elseif l > GrayLevel(p) then return "40c040"
    else return "808080" end
end

------------------------------------------------------------------------
-- Player state
------------------------------------------------------------------------

local function State()
    local p = UnitLevel("player")
    local cur, maxXP = UnitXP("player"), UnitXPMax("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    return p, cur, maxXP, max(0, maxXP - cur), rested or 0
end

local function Mult(forKills)
    local m = 1
    if CharDB.wellRested then m = m * 1.03 end
    if forKills and CharDB.wellFed then m = m * 1.05 end
    return m
end

------------------------------------------------------------------------
-- Quest log helpers (works with Classic-style and retail-style APIs)
------------------------------------------------------------------------

local questLevels, questTypes = {}, {}

-- fn(questID, level, isComplete, suggestedGroup, title)
local function ForEachQuest(fn)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                fn(info.questID, info.level, info.isComplete, info.suggestedGroup, info.title)
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local title, level, group, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if not isHeader and questID then fn(questID, level, isComplete, group, title) end
        end
    end
end

-- Quest tag ids (Enum.QuestTag): 1 Elite/Group, 41 PvP, 62 Raid, 81 Dungeon,
-- 85 Heroic, 88/89 Raid 10/25.
local TAG_TYPE = { [1] = "elite", [62] = "dungeon", [81] = "dungeon", [85] = "dungeon",
                   [88] = "dungeon", [89] = "dungeon" }

local function QuestTag(id)
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
        if ok and type(info) == "table" then return info.tagID, info.tagName end
    end
    if GetQuestTagInfo then
        local ok, tagID, tagName = pcall(GetQuestTagInfo, id)
        if ok and tagID then return tagID, tagName end
    end
    return nil
end

-- Returns the quest's type and how it was found ("tag", "group" or "none").
local function QuestType(id, group)
    local tagID = QuestTag(id)
    if tagID and TAG_TYPE[tagID] then return TAG_TYPE[tagID], "tag" end
    if tagID then return "normal", "tag" end
    -- No tag API or no tag: a suggested group size means a group quest. This
    -- can't tell elite from dungeon, so it counts as elite.
    if type(group) == "number" and group > 1 then return "elite", "group" end
    return "normal", "none"
end

local function CacheQuestLog()
    ForEachQuest(function(id, level, _, group)
        questLevels[id] = level
        questTypes[id] = QuestType(id, group)
    end)
end

local function QuestLogXP()
    if not GetQuestLogRewardXP then return nil end
    local total, count = 0, 0
    ForEachQuest(function(id)
        local ok, xp = pcall(GetQuestLogRewardXP, id)
        if ok and type(xp) == "number" and xp > 0 then
            total = total + xp
            count = count + 1
        end
    end)
    if count == 0 then return nil end
    return total, count
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------

local f = CreateFrame("Frame", "DingCalcFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(340, 325)
f:SetPoint("CENTER")
f:SetFrameStrata("MEDIUM")
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    DB.pos = { point, rel, x, y }
end)
if f.SetBackdrop then
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
end
f:Hide()

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 0, 0)
close:SetScript("OnClick", function() f:Hide(); DB.shown = false end)

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", size or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local title = Text(f, "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("DingCalc")

local header = Text(f, "GameFontHighlight")
header:SetPoint("TOPLEFT", 12, -30)

local sub = Text(f)
sub:SetPoint("TOPLEFT", 12, -48)

local barBG = f:CreateTexture(nil, "ARTWORK")
barBG:SetColorTexture(0.15, 0.15, 0.15, 1)
barBG:SetPoint("TOPLEFT", 12, -64)
barBG:SetSize(316, 10)
local barRested = f:CreateTexture(nil, "ARTWORK", nil, 1)
barRested:SetColorTexture(0.2, 0.4, 0.9, 0.6)
barRested:SetPoint("LEFT", barBG, "LEFT")
local bar = f:CreateTexture(nil, "ARTWORK", nil, 2)
bar:SetColorTexture(0.6, 0.2, 0.8, 1)
bar:SetPoint("LEFT", barBG, "LEFT")

local targetLine = Text(f)
targetLine:SetPoint("TOPLEFT", 12, -80)

local function Check(label, key, x, y)
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, y)
    local t = Text(f)
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetScript("OnClick", function(self)
        CharDB[key] = self:GetChecked() and true or false
        f:Refresh()
    end)
    return cb
end
local cbRested = Check("Well-Rested (+3%)", "wellRested", 8, -96)
local cbFed = Check("Well Fed (+5% kills)", "wellFed", 172, -96)

-- Table builder
local function MakeTable(top, heads, widths, nrows)
    local t = { rows = {} }
    local x = 12
    for i, h in ipairs(heads) do
        local fs = Text(f, "GameFontNormalSmall", i == 1 and "LEFT" or "RIGHT")
        fs:SetWidth(widths[i])
        fs:SetPoint("TOPLEFT", x, top)
        fs:SetText(h)
        x = x + widths[i]
    end
    for r = 1, nrows do
        local row = {}
        x = 12
        for i = 1, #heads do
            local fs = Text(f, "GameFontHighlightSmall", i == 1 and "LEFT" or "RIGHT")
            fs:SetWidth(widths[i])
            fs:SetPoint("TOPLEFT", x, top - 4 - r * 15)
            row[i] = fs
            x = x + widths[i]
        end
        t.rows[r] = row
    end
    return t
end

local killsTitle = Text(f, "GameFontNormal")
killsTitle:SetPoint("TOPLEFT", 12, -124)
killsTitle:SetText("Kills (solo)")
local kills = MakeTable(-142, { "Mob lvl", "XP", "Kills", "Elite kills" }, { 104, 70, 70, 72 }, #BANDS)

local questsTitle = Text(f, "GameFontNormal")
questsTitle:SetPoint("TOPLEFT", 12, -206)
questsTitle:SetText("Quests")

-- Quest type selector: click to cycle Normal -> Elite -> Dungeon.
local typeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
typeBtn:SetSize(90, 20)
typeBtn:SetPoint("LEFT", questsTitle, "RIGHT", 10, 0)
typeBtn:SetScript("OnClick", function()
    local cur = DB.questType or "normal"
    for i, t in ipairs(QUEST_TYPES) do
        if t == cur then DB.questType = QUEST_TYPES[i % #QUEST_TYPES + 1]; break end
    end
    f:Refresh()
end)
local quests = MakeTable(-224, { "Quest lvl", "XP per quest", "Quests" }, { 104, 110, 102 }, #BANDS)

local logLine = Text(f)
logLine:SetPoint("TOPLEFT", 12, -292)
logLine:SetWidth(316)

local function Fmt(n)
    if not n then return "-" end
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^ ", ""))
end

-- "a" or "a–b" (smallest to largest); "-" when there is no value.
local function Range(a, b)
    if not a then return "-" end
    if a > b then a, b = b, a end
    if a == b then return Fmt(a) end
    return Fmt(a) .. "–" .. Fmt(b)
end

-- First cell of a band row: colored band name and its level range.
local function BandLabel(band, lo, hi)
    local levels = lo > hi and "" or (lo == hi and (" " .. lo) or (" " .. lo .. "–" .. hi))
    return "|cff" .. band.color .. band.name .. "|r" .. levels
end

function f:Refresh()
    if not CharDB then return end
    local p, cur, maxXP, remain, rested = State()
    local pct = maxXP > 0 and cur / maxXP * 100 or 0
    header:SetFormattedText("Level %d  —  %s XP to level %d", p, Fmt(remain), p + 1)
    sub:SetFormattedText("%s / %s XP (%.1f%%)   Rested: %s", Fmt(cur), Fmt(maxXP), pct, Fmt(rested))
    local w = 316
    bar:SetWidth(max(1, w * (maxXP > 0 and cur / maxXP or 0)))
    barRested:SetWidth(max(1, w * min(1, maxXP > 0 and (cur + rested) / maxXP or 0)))
    cbRested:SetChecked(CharDB.wellRested)
    cbFed:SetChecked(CharDB.wellFed)

    -- One row per difficulty band: level range, then XP and counts as
    -- "least–most" over the levels in the band.
    local km = Mult(true)
    for r, band in ipairs(BANDS) do
        local lo, hi = max(1, band.lo(p)), band.hi(p)
        local row = kills.rows[r]
        local xlo, xhi
        for m = lo, hi do
            local xp = floor(MobXP(p, m) * km)
            if xp > 0 then
                xlo, xhi = min(xlo or xp, xp), max(xhi or xp, xp)
            end
        end
        row[1]:SetText(BandLabel(band, lo, hi))
        row[2]:SetText(Range(xlo, xhi))
        if xlo then
            row[3]:SetText(Range(KillsNeeded(xhi, remain, rested), KillsNeeded(xlo, remain, rested)))
            row[4]:SetText(Range(KillsNeeded(xhi * 2, remain, rested), KillsNeeded(xlo * 2, remain, rested)))
        else
            row[3]:SetText("-")
            row[4]:SetText("-")
        end
    end

    local qt = DB.questType or "normal"
    typeBtn:SetText(TYPE_LABEL[qt])
    local qm = Mult(false)
    local anyData = false
    for r, band in ipairs(BANDS) do
        local lo, hi = max(1, band.lo(p)), band.hi(p)
        local row = quests.rows[r]
        local xlo, xhi, anyEst
        for q = lo, hi do
            local base, est = TypicalQuestXP(qt, q)
            if base then
                local xp = floor(base * QuestMult(p, q) * qm)
                if xp > 0 then
                    xlo, xhi = min(xlo or xp, xp), max(xhi or xp, xp)
                    anyEst = anyEst or est
                end
            end
        end
        row[1]:SetText(BandLabel(band, lo, hi))
        if xlo then
            anyData = true
            row[2]:SetText((anyEst and "~" or "") .. Range(xlo, xhi))
            row[3]:SetText(Range(ceil(remain / xhi), ceil(remain / xlo)))
        else
            row[2]:SetText("-")
            row[3]:SetText("-")
        end
    end

    local total, count = QuestLogXP()
    if not anyData then
        logLine:SetFormattedText("|cff808080No %s quest turned in yet: no data|r", TYPE_LABEL[qt]:lower())
    elseif total then
        logLine:SetFormattedText("Quest log: %d quests worth %s XP (%.0f%% of what you need)",
            count, Fmt(total), remain > 0 and total / remain * 100 or 0)
    else
        logLine:SetText("|cff808080~ = estimate until you turn in quests of that level|r")
    end

    self:RefreshTarget()
end

function f:RefreshTarget()
    local n, text = nil, nil
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsPlayer("target") then
        local p, _, _, remain, rested = State()
        local m = UnitLevel("target")
        if m and m > 0 then
            local cls = UnitClassification("target")
            local elite = cls == "elite" or cls == "rareelite" or cls == "worldboss"
            local xp = floor(MobXP(p, m) * Mult(true)) * (elite and 2 or 1)
            n = KillsNeeded(xp, remain, rested)
            text = string.format("Target: |cff%s%d%s|r  %s XP  →  %s kills to ding",
                DiffColor(p, m), m, elite and " elite" or "", Fmt(xp), n and Fmt(n) or "gray")
        end
    end
    targetLine:SetText(text or "|cff808080Target a mob to see kills to ding|r")
end

------------------------------------------------------------------------
-- Tooltip: "Kills to ding: N" on enemy mobs
------------------------------------------------------------------------

local function OnTooltipUnit(tt)
    if not CharDB or DB.tooltip == false then return end
    local _, unit = tt:GetUnit()
    if not unit or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
    local p, _, _, remain, rested = State()
    if p >= 60 then return end
    local m = UnitLevel(unit)
    if not m or m <= 0 then return end
    local cls = UnitClassification(unit)
    local elite = cls == "elite" or cls == "rareelite" or cls == "worldboss"
    local xp = floor(MobXP(p, m) * Mult(true)) * (elite and 2 or 1)
    local n = KillsNeeded(xp, remain, rested)
    if n then
        tt:AddLine(string.format("Kills to ding: %s  (%s XP each)", Fmt(n), Fmt(xp)), 0.6, 0.8, 1)
        tt:Show()
    end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt == GameTooltip then OnTooltipUnit(tt) end
    end)
else
    GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipUnit)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("UPDATE_EXHAUSTION")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_TURNED_IN")

ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        DingCalcDB = DingCalcDB or {}
        DB = DingCalcDB
        DB.quest = DB.quest or {}
        if not DB.quest.normal then
            -- Before 1.0.0-beta.3 learned XP was one table keyed by quest level,
            -- with all quest types mixed. Keep it as the normal-quest table.
            DB.quest = { normal = DB.quest }
        end
        for _, t in ipairs(QUEST_TYPES) do
            DB.quest[t] = DB.quest[t] or {}
            -- Before 1.0.0-beta.4 only sum and count were saved. Keep those
            -- turn-ins as n samples of their old average.
            for _, l in pairs(DB.quest[t]) do
                if not l.hist and l.n and l.n > 0 then
                    l.hist = { [floor(l.sum / l.n / 5 + 0.5) * 5] = l.n }
                end
            end
        end
        if not DingCalcCharDB then
            -- First load on this character. Before 1.0.0-beta.2 the checkboxes
            -- were account-wide: hand them to the first character that logs in
            -- and clear them, so other characters start unticked.
            DingCalcCharDB = { wellRested = DB.wellRested, wellFed = DB.wellFed }
            DB.wellRested, DB.wellFed = nil, nil
        end
        CharDB = DingCalcCharDB
        if DB.pos then
            f:ClearAllPoints()
            f:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
        end
        if DB.shown then f:Show() end
        return
    end
    if not CharDB then return end

    if event == "QUEST_LOG_UPDATE" then
        CacheQuestLog()
    elseif event == "QUEST_TURNED_IN" then
        -- Learn typical quest XP per quest level from your own turn-ins.
        local id, xp = a1, a2
        local q, t = questLevels[id], questTypes[id] or "normal"
        local p = UnitLevel("player")
        local qmult = q and QuestMult(p, q)
        if q and q > 0 and type(xp) == "number" and xp > 0 and p < 60 and qmult >= MIN_LEARN_MULT then
            local full = xp / qmult / (CharDB.wellRested and 1.03 or 1)
            local v = floor(full / 5 + 0.5) * 5
            local l = DB.quest[t][q] or { sum = 0, n = 0, hist = {} }
            l.hist = l.hist or {}
            l.sum, l.n = l.sum + v, l.n + 1
            l.hist[v] = (l.hist[v] or 0) + 1
            DB.quest[t][q] = l
        end
    end

    if f:IsShown() then
        if event == "PLAYER_TARGET_CHANGED" then f:RefreshTarget() else f:Refresh() end
    end
end)

f:SetScript("OnShow", function(self) self:Refresh() end)

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------

SLASH_DINGCALC1 = "/ding"
SLASH_DINGCALC2 = "/dingcalc"
SlashCmdList.DINGCALC = function(msg)
    msg = (msg or ""):lower()
    if msg == "tooltip" then
        DB.tooltip = DB.tooltip == false
        print("|cff9966ffDingCalc|r: tooltip line " .. (DB.tooltip and "on" or "off"))
    elseif msg == "quests" then
        -- Show how each quest in the log is classified (to check the client's API).
        print("|cff9966ffDingCalc|r: quest types in your log (type / found by):")
        local n = 0
        ForEachQuest(function(id, level, _, group, title)
            local t, how = QuestType(id, group)
            local tagID, tagName = QuestTag(id)
            print(string.format("  [%s] %s: %s / %s (tag %s%s, group %s)", tostring(level),
                tostring(title or id), TYPE_LABEL[t], how, tostring(tagID),
                tagName and (" " .. tagName) or "", tostring(group)))
            n = n + 1
        end)
        if n == 0 then print("  (quest log is empty)") end
    elseif msg == "stats" then
        -- Learned quest XP for the type shown in the window, per quest level.
        local t = DB.questType or "normal"
        print(string.format("|cff9966ffDingCalc|r: learned %s quest XP (full XP, before penalties):", TYPE_LABEL[t]:lower()))
        local levels = {}
        for q in pairs(DB.quest[t]) do levels[#levels + 1] = q end
        table.sort(levels)
        for _, q in ipairs(levels) do
            local l = DB.quest[t][q]
            local lo, hi
            for v in pairs(l.hist or {}) do lo, hi = min(lo or v, v), max(hi or v, v) end
            print(string.format("  lvl %d: %d turn-ins, median %s, mean %s, range %s-%s", q, l.n,
                Fmt(HistMedian(l.hist, l.n)), Fmt(floor(l.sum / l.n + 0.5)), Fmt(lo), Fmt(hi)))
        end
        if #levels == 0 then print("  (no turn-ins yet)") end
    elseif msg == "resetquests" then
        DB.quest = { normal = {}, elite = {}, dungeon = {} }
        print("|cff9966ffDingCalc|r: learned quest XP cleared (all characters)")
        if f:IsShown() then f:Refresh() end
    elseif msg == "reset" then
        DB.pos = nil
        f:ClearAllPoints()
        f:SetPoint("CENTER")
    else
        if f:IsShown() then f:Hide(); DB.shown = false else f:Show(); DB.shown = true end
    end
end
