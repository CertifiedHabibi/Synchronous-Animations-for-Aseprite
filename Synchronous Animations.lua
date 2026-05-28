local sprite = app.activeSprite
if not sprite then
    local d = Dialog("Sync Timings")
    d:label{ text = "No active sprite! Please open a sprite first." }
    d:button{ id = "ok", text = "OK", focus = true }
    d:show()
    return
end

local nframes = #sprite.frames

local imageLayers = {}

local function collectGroupChildren(groupLayer)
    -- collect image layer indices for every layer in this group
    local indices = {}
    local function recurse(layers)
        for i = #layers, 1, -1 do   -- reverse order (displays layers from top to bottom)
            local l = layers[i]
            if l.isGroup then
                recurse(l.layers)
            elseif l.isImage then
                table.insert(imageLayers, l)
                table.insert(indices, #imageLayers)
            end
        end
    end
    recurse(groupLayer.layers)
    return indices
end

local entries = {}
for i = #sprite.layers, 1, -1 do
    local layer = sprite.layers[i]
    if layer.isGroup then
        local indices = collectGroupChildren(layer)
        if #indices > 0 then
            table.insert(entries, {
                type              = "group",
                name              = layer.name,
                imageLayerIndices = indices,
            })
        end
    elseif layer.isImage then
        table.insert(imageLayers, layer)
        table.insert(entries, {
            type              = "layer",
            name              = layer.name,
            imageLayerIndices = { #imageLayers },
        })
    end
end

if #imageLayers == 0 then
    local d = Dialog("Sync Timings")
    d:label{ text = "No image layers found in this sprite." }
    d:button{ id = "ok", text = "OK", focus = true }
    d:show()
    return
end

local lastX, lastY = nil, nil

local function showDlg(dlg)
    if lastX then
        dlg:show{ bounds = Rectangle(lastX, lastY, 0, 0) }
    else
        dlg:show()
    end
    lastX = dlg.bounds.x
    lastY = dlg.bounds.y
end

local LAYERS_PER_PAGE = 4
local totalPages1     = math.ceil(#entries / LAYERS_PER_PAGE)
local entryMode       = {}
local entryFrameCount = {}
local entryLoop       = {}

::restart::

-- Reset all entry state on each run/restart
for e = 1, #entries do
    entryMode[e]       = "fixed"
    entryFrameCount[e] = nframes
    entryLoop[e]       = "none"
end

local page = 1
while true do
    local startIdx = (page - 1) * LAYERS_PER_PAGE + 1
    local endIdx   = math.min(page * LAYERS_PER_PAGE, #entries)
    local isFirst  = (page == 1)
    local isLast   = (page == totalPages1)

    local title = "Sync Timings - Step 1/2"
    if totalPages1 > 1 then
        title = title .. "  (pg " .. page .. "/" .. totalPages1 .. ")"
    end

    local dlg = Dialog(title)
    dlg:label{ text = "Sprite: " .. nframes .. " frame(s)  |  Showing " .. startIdx .. "-" .. endIdx .. " of " .. #entries }
    dlg:separator()
    dlg:label{ text = "Set timing mode and active frames per layer or group." }
    dlg:separator()

    for e = startIdx, endIdx do
        local entry   = entries[e]
        local modeId  = "mode_"  .. e
        local countId = "count_" .. e
        local loopId  = "loop_"  .. e
        local isGroup = entry.type == "group"

        local sepLabel = entry.name
        if isGroup then
            sepLabel = sepLabel .. "  [group, " .. #entry.imageLayerIndices .. " layer(s)]"
        end

        dlg:separator{ text = sepLabel }
        dlg:combobox{
            id       = modeId,
            label    = "Mode:",
            option   = entryMode[e] == "fixed"  and "Fixed duration per frame" or
                    entryMode[e] == "custom" and "Custom duration per frame" or
                    "Static (Remains the same throughout)",
            options  = { "Fixed duration per frame", "Custom duration per frame", "Static (Remains the same throughout)" },
            onchange = function()
                local isStatic = dlg.data[modeId] == "Static (Remains the same throughout)"
                dlg:modify{ id = countId, enabled = not isStatic }
                dlg:modify{ id = loopId,  enabled = not isStatic }
            end
        }
        dlg:number{
            id       = countId,
            label    = "Active frames:",
            text     = tostring(entryFrameCount[e]),
            decimals = 0,
            enabled  = entryMode[e] ~= "static"
        }
        dlg:combobox{
            id      = loopId,
            label   = "Additional effects:",
            option  = entryLoop[e] == "loop"     and "Loop" or
                    entryLoop[e] == "pingpong" and "Ping-pong" or "None",
            options = { "None", "Loop", "Ping-pong" },
            enabled = entryMode[e] ~= "static"
        }
    end

    dlg:separator()
    if not isFirst then dlg:button{ id = "back",   text = "Back" } end
    dlg:button{ id = "next",   text = (isLast and "Next" or "Next page"), focus = true }
    dlg:button{ id = "cancel", text = "Cancel" }
    showDlg(dlg)

    if dlg.data.cancel or (not dlg.data.next and not dlg.data.back) then return end

    local valid = true
    for e = startIdx, endIdx do
        local modeStr = dlg.data["mode_" .. e]
        local mode    = modeStr == "Fixed duration per frame" and "fixed" or
                modeStr == "Custom duration per frame" and "custom" or "static"
        local count   = math.floor(dlg.data["count_" .. e] or entryFrameCount[e])

        if mode ~= "static" and count < 1 then
            local d = Dialog("Sync Timings")
            d:label{ text = entries[e].name .. ": active frames must be at least 1." }
            d:button{ id = "ok", text = "OK", focus = true }
            d:show()
            valid = false
            break
        end

        entryMode[e]       = mode
        entryFrameCount[e] = (mode == "static") and 1 or count
        local loopStr      = dlg.data["loop_" .. e] or "None"
        entryLoop[e]       = loopStr == "Loop" and "loop" or
                loopStr == "Ping-pong" and "pingpong" or "none"
    end

    if valid then
        if dlg.data.next then
            if isLast then break end
            page = page + 1
        elseif dlg.data.back then
            page = page - 1
        end
    end
end

local syncUnits = {}

for e = 1, #entries do
    local entry = entries[e]
    if entryMode[e] ~= "static" then
        table.insert(syncUnits, {
            name              = entry.type == "group" and (entry.name .. " [group]") or entry.name,
            mode              = entryMode[e],
            frameCount        = entryFrameCount[e],
            imageLayerIndices = entry.imageLayerIndices,
            loopMode          = entryLoop[e],
        })
    end
end

if #syncUnits == 0 then
    local d = Dialog("Sync Timings")
    d:label{ text = "All layers are set to Static - nothing to sync." }
    d:button{ id = "ok", text = "OK", focus = true }
    d:show()
    return
end

local savedDurations = {}
for u = 1, #syncUnits do
    savedDurations[u] = {}
    for f = 1, syncUnits[u].frameCount do
        savedDurations[u][f] = 500
    end
end

local MAX_INPUTS_PER_PAGE = 8
local step2Pages = {}
local curPage2   = {}
local curInputs  = 0

for u = 1, #syncUnits do
    local inputs = (syncUnits[u].mode == "fixed") and 1 or syncUnits[u].frameCount
    if #curPage2 > 0 and curInputs + inputs > MAX_INPUTS_PER_PAGE then
        table.insert(step2Pages, curPage2)
        curPage2  = {}
        curInputs = 0
    end
    table.insert(curPage2, u)
    curInputs = curInputs + inputs
end
if #curPage2 > 0 then table.insert(step2Pages, curPage2) end

local totalPages2 = #step2Pages

page = 1
while true do
    local pageUnits = step2Pages[page]
    local isFirst   = (page == 1)
    local isLast    = (page == totalPages2)

    local title = "Sync Timings - Step 2/2"
    if totalPages2 > 1 then
        title = title .. "  (pg " .. page .. "/" .. totalPages2 .. ")"
    end

    local dlg = Dialog(title)
    dlg:label{ text = "Enter frame durations (ms)." }
    dlg:separator()

    for _, u in ipairs(pageUnits) do
        local unit  = syncUnits[u]
        local mode  = unit.mode
        local count = unit.frameCount

        dlg:separator{ text = unit.name .. "  (" .. count .. " frame(s),  " .. mode .. ")" }

        if mode == "fixed" then
            dlg:number{
                id       = "u_" .. u .. "_f1",
                label    = "All frames:",
                text     = tostring(savedDurations[u][1]),
                decimals = 0
            }
        else
            for f = 1, count do
                dlg:number{
                    id       = "u_" .. u .. "_f" .. f,
                    label    = "Frame " .. f .. ":",
                    text     = tostring(savedDurations[u][f] or 500),
                    decimals = 0
                }
            end
        end
    end

    dlg:separator()
    if not isFirst then dlg:button{ id = "back",      text = "Back" } end
    dlg:button{ id = "startover", text = "Start Over" }
    dlg:button{ id = "next",      text = (isLast and "Preview & Apply" or "Next page"), focus = true }
    dlg:button{ id = "cancel",    text = "Cancel" }
    showDlg(dlg)

    if dlg.data.startover then goto restart end
    if dlg.data.cancel or (not dlg.data.next and not dlg.data.back) then return end

    for _, u in ipairs(pageUnits) do
        local mode  = syncUnits[u].mode
        local count = syncUnits[u].frameCount
        if mode == "fixed" then
            local val = math.max(1, math.floor(dlg.data["u_" .. u .. "_f1"] or 500))
            for f = 1, count do savedDurations[u][f] = val end
        else
            for f = 1, count do
                savedDurations[u][f] = math.max(1, math.floor(dlg.data["u_" .. u .. "_f" .. f] or 500))
            end
        end
        syncUnits[u].durations = savedDurations[u]
    end

    if dlg.data.next then
        if isLast then break end
        page = page + 1
    elseif dlg.data.back then
        page = page - 1
    end
end

local unitBoundaries = {}
for u = 1, #syncUnits do
    local bounds = { 0 }
    for _, d in ipairs(syncUnits[u].durations) do
        table.insert(bounds, bounds[#bounds] + d)
    end
    unitBoundaries[u] = bounds
end

-- Global total = max of non-looping units (total animation length)
local globalTotalMs = 0
for u = 1, #syncUnits do
    if syncUnits[u].loopMode == "none" then
        local t = unitBoundaries[u][#unitBoundaries[u]]
        if t > globalTotalMs then globalTotalMs = t end
    end
end
if globalTotalMs == 0 then  -- if all units loop use longest base
    for u = 1, #syncUnits do
        local t = unitBoundaries[u][#unitBoundaries[u]]
        if t > globalTotalMs then globalTotalMs = t end
    end
end

local extBounds   = {}
local extFrameMap = {}

for u = 1, #syncUnits do
    local baseBounds = unitBoundaries[u]
    local loopMode   = syncUnits[u].loopMode
    local n          = #baseBounds - 1  -- number of original frames

    -- Frame durations with their original indices
    local frameDurs = {}
    for i = 1, n do
        frameDurs[i] = { dur = baseBounds[i+1] - baseBounds[i], frame = i }
    end

    local bounds   = { 0 }
    local frameMap = {}
    local t        = 0

    if loopMode == "none" then
        for _, fd in ipairs(frameDurs) do
            t = math.min(t + fd.dur, globalTotalMs)
            table.insert(bounds, t)
            table.insert(frameMap, fd.frame)
            if t >= globalTotalMs then break end
        end
        if t < globalTotalMs then
            table.insert(bounds, globalTotalMs)
            table.insert(frameMap, n)  -- hold last frame
        end

    elseif loopMode == "loop" then
        local fi = 1
        while t < globalTotalMs do
            local fd  = frameDurs[fi]
            local newt = math.min(t + fd.dur, globalTotalMs)
            table.insert(bounds, newt)
            table.insert(frameMap, fd.frame)
            t  = newt
            fi = (fi % n) + 1
        end

    elseif loopMode == "pingpong" then
        local fi      = 1
        local forward = true
        while t < globalTotalMs do
            local fd   = frameDurs[fi]
            local newt = math.min(t + fd.dur, globalTotalMs)
            table.insert(bounds, newt)
            table.insert(frameMap, fd.frame)
            t = newt
            if t >= globalTotalMs then break end

            if forward then
                fi = fi + 1
                if fi > n then
                    fi      = n - 1
                    forward = false
                end
            else
                fi = fi - 1
                if fi < 1 then
                    fi      = 2
                    forward = true
                end
            end
        end
    end

    extBounds[u]   = bounds
    extFrameMap[u] = frameMap
end

-- Collect all split points
local splitSet = { [0] = true, [globalTotalMs] = true }
for u = 1, #syncUnits do
    for _, t in ipairs(extBounds[u]) do splitSet[t] = true end
end

local splitTimes = {}
for t in pairs(splitSet) do table.insert(splitTimes, t) end
table.sort(splitTimes)

local resultDurations = {}
for i = 1, #splitTimes - 1 do
    table.insert(resultDurations, splitTimes[i + 1] - splitTimes[i])
end

local resultFrameCount = #resultDurations

-- Find which original frame a unit shows at a given time (using precomputed map)
local function findOrigFrameForUnit(u, time)
    local bounds   = extBounds[u]
    local frameMap = extFrameMap[u]
    for fi = 1, #bounds - 1 do
        if time >= bounds[fi] and time < bounds[fi + 1] then
            return frameMap[fi]
        end
    end
    return frameMap[#frameMap]
end

-- Build per-image-layer frame map
local imageLayerFrameMap = {}

for u = 1, #syncUnits do
    local unitMap = {}
    for j = 1, resultFrameCount do
        local mid = (splitTimes[j] + splitTimes[j + 1]) / 2
        unitMap[j] = findOrigFrameForUnit(u, mid)
    end
    for _, idx in ipairs(syncUnits[u].imageLayerIndices) do
        imageLayerFrameMap[idx] = unitMap
    end
end

-- Static layers: map to first original frame that actually has a cel
for i = 1, #imageLayers do
    if not imageLayerFrameMap[i] then
        local firstFrame = 1
        for j = 1, nframes do
            if imageLayers[i]:cel(j) then
                firstFrame = j
                break
            end
        end
        local staticMap = {}
        for j = 1, resultFrameCount do
            staticMap[j] = firstFrame
        end
        imageLayerFrameMap[i] = staticMap
    end
end

local totalMs = globalTotalMs
local mins    = math.floor(totalMs / 60000)
local secs    = (totalMs % 60000) / 1000

local durStrs = {}
local showMax = math.min(resultFrameCount, 24)
for i = 1, showMax do table.insert(durStrs, tostring(resultDurations[i])) end
if resultFrameCount > showMax then
    table.insert(durStrs, "... +" .. (resultFrameCount - showMax) .. " more")
end

local staticNames = {}
for e = 1, #entries do
    if entryMode[e] == "static" then
        table.insert(staticNames, entries[e].name)
    end
end

local confirmDlg = Dialog("Preview - Sync Timings")
confirmDlg:separator{ text = "Summary" }
confirmDlg:label{ text = "Original frames : " .. nframes }
confirmDlg:label{ text = "Result frames   : " .. resultFrameCount }
confirmDlg:label{ text = "Total duration  : " ..
        (mins > 0 and (mins .. "m ") or "") ..
        string.format("%.3f", secs) .. "s  (" .. totalMs .. " ms)" }
if #staticNames > 0 then
    confirmDlg:separator{ text = "Static (excluded from sync)" }
    confirmDlg:label{ text = table.concat(staticNames, ", ") }
end
confirmDlg:separator{ text = "Frame durations (ms)" }
confirmDlg:label{ text = table.concat(durStrs, ", ") }
confirmDlg:separator()
confirmDlg:label{ text = "This will modify the sprite. Undo is available after." }
confirmDlg:button{ id = "startover", text = "Start Over" }
confirmDlg:button{ id = "apply",     text = "Apply",      focus = true }
confirmDlg:button{ id = "cancel",    text = "Cancel" }
showDlg(confirmDlg)

if confirmDlg.data.startover then goto restart end
if not confirmDlg.data.apply then return end

local originalCels = {}
for i, layer in ipairs(imageLayers) do
    originalCels[i] = {}
    for j = 1, nframes do
        local cel = layer:cel(j)
        if cel then
            originalCels[i][j] = {
                image    = cel.image:clone(),
                position = cel.position
            }
        end
    end
end

app.transaction(function()

    -- Step A: bring frame count to resultFrameCount
    while #sprite.frames < resultFrameCount do
        sprite:newFrame(#sprite.frames)
    end
    while #sprite.frames > resultFrameCount do
        sprite:deleteFrame(sprite.frames[#sprite.frames])
    end

    -- Step B: set durations
    for j = 1, resultFrameCount do
        sprite.frames[j].duration = resultDurations[j] / 1000
    end

    -- Step C: rebuild cels
    for i, layer in ipairs(imageLayers) do
        for j = 1, #sprite.frames do
            local cel = layer:cel(j)
            if cel then sprite:deleteCel(cel) end
        end
        for j = 1, resultFrameCount do
            local origIdx  = imageLayerFrameMap[i][j]
            local origData = originalCels[i][origIdx]
            if origData then
                sprite:newCel(layer, sprite.frames[j], origData.image, origData.position)
            end
        end
    end

end)

app.refresh()

-- Link cels that share the same original frame
app.transaction("Link Cels", function()
    for i, layer in ipairs(imageLayers) do
        local groups = {}
        for j = 1, resultFrameCount do
            local origIdx = imageLayerFrameMap[i][j]
            if not groups[origIdx] then groups[origIdx] = {} end
            table.insert(groups[origIdx], j)
        end
        for _, frameNums in pairs(groups) do
            if #frameNums > 1 then
                app.range.layers = { layer }
                app.range.frames = frameNums
                app.command.LinkCels()
            end
        end
    end
end)

app.refresh()

local doneDlg = Dialog("Sync Timings - Done")
doneDlg:separator{ text = "Complete" }
doneDlg:label{ text = "Original frames : " .. nframes }
doneDlg:label{ text = "Result frames   : " .. resultFrameCount }
doneDlg:label{ text = "Total duration  : " .. totalMs .. " ms" }
if #staticNames > 0 then
    doneDlg:separator{ text = "Static layers (unchanged)" }
    doneDlg:label{ text = table.concat(staticNames, ", ") }
end
doneDlg:separator()
doneDlg:label{ text = "Use Ctrl+Z twice to undo if needed. Once for the cel links, another time for the script execution." }
doneDlg:button{ id = "ok", text = "OK", focus = true }
doneDlg:show()