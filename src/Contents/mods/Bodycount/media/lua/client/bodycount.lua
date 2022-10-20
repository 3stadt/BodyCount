BodyCount = {}
BodyCount.damageLog = { dead = false, xpEvent = false }

function BodyCount.getWeaponCategory(weapon)
    local categories = weapon:getCategories()
    local weaponCategory = "Unknown";
    for i = 0, categories:size() - 1 do
        -- return improvised early
        if categories:get(i) ~= "Improvised" then
            return categories:get(i)
        end
        weaponCategory = categories:get(i); -- get last category
    end
    if weaponCategory == "Unknown" then
        local subCategory = weapon:getSubCategory()
        if subCategory then
            weaponCategory = subCategory;
        end
    end
    return weaponCategory;
end

function BodyCount.killSucceeded(player, zed, weapon)
    if not player or not zed then
        return ;
    end

    local pd = player:getModData()
    if pd then
        if not pd.bodyCount then
            pd.bodyCount = {}
        end
        if weapon then
            local weaponCategory = BodyCount.getWeaponCategory(weapon)
            local weaponType = weapon:getType()

            if weaponType and weaponCategory then

                if not pd.bodyCount then
                    pd.bodyCount = {}
                end

                -- Add 1 to kill count for category
                if not pd.bodyCount.WeaponCategory then
                    pd.bodyCount.WeaponCategory = {}
                end
                if not pd.bodyCount.WeaponCategory[weaponCategory] then
                    pd.bodyCount.WeaponCategory[weaponCategory] = 0
                end
                pd.bodyCount.WeaponCategory[weaponCategory] = pd.bodyCount.WeaponCategory[weaponCategory] + 1;

                -- add 1 for the current type
                if not pd.bodyCount.WeaponType then
                    pd.bodyCount.WeaponType = {}
                end
                if not pd.bodyCount.WeaponType[weaponType] then
                    pd.bodyCount.WeaponType[weaponType] = 0
                end
                pd.bodyCount.WeaponType[weaponType] = pd.bodyCount.WeaponType[weaponType] + 1;

                -- write to file
                BodyCount.updateLogFiles(pd)
            end
        end
    end
end

function BodyCount.OnZombieDead(zed)
    local player = getPlayer()
    local m = getGameTime():getMonth()
    local d = getGameTime():getDay()
    local pd = player:getModData()

    if not pd.bodyCount.DailyStats then
        pd.bodyCount.DailyStats = {}
    end

    if not pd.bodyCount.DailyStats[m] then
        pd.bodyCount.DailyStats[m] = {}
    end

    if not pd.bodyCount.DailyStats[m][d] then
        pd.bodyCount.DailyStats[m][d] = 0
    end

    pd.bodyCount.DailyStats[m][d] = pd.bodyCount.DailyStats[m][d] + 1

    print(pd.bodyCount.DailyStats)

    local zedBurning = zed:isOnFire()
    if (pd.inVehicle or zedBurning) and not (BodyCount.damageLog.xpEvent) then
        local weaponCategory = "vehicle"
        local weaponType = "vehicle"

        if BodyCount.exploded(zed) or (not pd.inVehicle and zedBurning) then
            -- explosion priority for zed deaths
            weaponCategory = "explosives"
            weaponType = "explosives"
        end

        if not pd.bodyCount.WeaponCategory[weaponCategory] then
            pd.bodyCount.WeaponCategory[weaponCategory] = 0
        end
        pd.bodyCount.WeaponCategory[weaponCategory] = pd.bodyCount.WeaponCategory[weaponCategory] + 1;

        if not pd.bodyCount.WeaponType[weaponType] then
            pd.bodyCount.WeaponType[weaponType] = 0
        end
        pd.bodyCount.WeaponType[weaponType] = pd.bodyCount.WeaponType[weaponType] + 1;
    end
    local sZed = tostring(zed)
    local damageLog = BodyCount.damageLog[sZed]
    if damageLog then
        damageLog.timestampDead = getTimestampMs()
        damageLog.dead = true
    end
    BodyCount.xpEvent = false

    BodyCount.updateLogFiles(pd)
end

function BodyCount.updateLogFiles(pd)
    -- playerModData
    if not pd.bodyCount then
        pd.bodyCount = {}
    end
    if not pd.bodyCount.WeaponCategory then
        pd.bodyCount.WeaponCategory = {}
    end
    if not pd.bodyCount.WeaponType then
        pd.bodyCount.WeaponType = {}
    end
    if not pd.bodyCount.DailyStats then
        pd.bodyCount.DailyStats = {}
    end

    local catCountTotal = 0
    for cat, weaponCategoryCount in pairs(pd.bodyCount.WeaponCategory) do
        catCountTotal = catCountTotal + weaponCategoryCount
    end
    BodyCount.overwrite("mod_bodycount_total.txt", catCountTotal)
    local str = BodyCount.SerializeStatsJson(pd.bodyCount.WeaponCategory)
    BodyCount.overwrite("mod_bodycount_categories.json", str)
    str = BodyCount.SerializeStatsJson(pd.bodyCount.WeaponType)
    BodyCount.overwrite("mod_bodycount_types.json", str)
    str = BodyCount.SerializeChartStatsJson(pd.bodyCount.DailyStats)
    BodyCount.overwrite("mod_bodycount_per_day_data.txt", str)

    str = BodyCount.SerializeStatsString(pd.bodyCount.WeaponCategory)
    BodyCount.overwrite("mod_bodycount_categories.txt", str)
    str = BodyCount.SerializeStatsString(pd.bodyCount.WeaponType)
    BodyCount.overwrite("mod_bodycount_types.txt", str)
    local top5counter = 0
    local top5str = ""
    for line in str:gmatch("([^\n]*)\n?") do
        top5str = top5str .. line .. "\n"
        top5counter = top5counter + 1
        if top5counter >= 5 then
            break
        end
    end
    top5str = string.sub(top5str, 1, -2) -- remove trailing whitespace
    BodyCount.overwrite("mod_bodycount_types_top5.txt", top5str)
end

function BodyCount.overwrite(file, text)
    local w = getFileWriter(file, true, false)
    w:write(tostring(text))
    w:close()
end

function BodyCount.exploded(zed)
    if BodyCount.damageLog[tostring(zed)] ~= nil then
        return false
    end
    local damageLog = BodyCount.damageLog[tostring(zed)]
    return damageLog and not isClient() and damageLog.explosives and damageLog.timestampLastHit and (damageLog.timestampDead - damageLog.timestampLastHit < 100)
end

function BodyCount.OnWeaponHitCharacter(player, zed, weapon, damage)
    local damageLog = {}
    if (not player or not instanceof(player, "IsoPlayer") or not player:isLocalPlayer()) then
        if not isClient() and weapon and instanceof(weapon, "HandWeapon") and weapon:getSubCategory() == "Swinging" and weapon:isInstantExplosion() and getPlayer() then
            player = getPlayer()--vanilla returns some unknown IsoZombie as wielder in explosive case. cheat it with local player in solo mode
            damageLog.explosives = true
        else
            return false
        end
    end
    damageLog.weapon = weapon
    damageLog.damage = damage
    damageLog.timestampLastHit = getTimestampMs()
    BodyCount.damageLog[tostring(zed)] = damageLog;
end

function BodyCount.OnEnterVehicle(player)
    local pd = player:getModData()
    pd.inVehicle = true
end

function BodyCount.OnExitVehicle(player)
    local pd = player:getModData()
    pd.inVehicle = false
end

function BodyCount.SerializeChartStatsJson(stats)
    local jsonData = ""
    local jsonLabels = ""
    for m, data in pairs(stats) do
        for k, v in pairs(data) do
            jsonData = jsonData .."{x:'"..k.."."..m..".', y:".. v .. "},"
        end
    end
    jsonData = string.sub(jsonData, 1, -2) -- remove trailing comma
    return "[" .. jsonData .. "]"
end

function BodyCount.SerializeStatsJson(stats)
    local json = ""
    for k, v in pairs(stats) do
        json = json .. "{\"name\": \"" .. k:gsub("^%l", string.upper) .. "\", \"quantity\": " .. v .. "},"
    end
    json = string.sub(json, 1, -2) -- remove trailing comma
    return "[" .. json .. "]"
end

function BodyCount.SerializeStatsString(stats)
    local padlen = 0
    for k, v in pairs(stats) do
        if #k > padlen then
            padlen = #k
        end
    end
    padlen = padlen + 1 -- account for whitespace
    local statsTable = {}
    for k, v in pairs(stats) do
        table.insert(statsTable, { name = k, quantity = v })
    end
    table.sort(statsTable, function(a, b)
        return a.quantity > b.quantity
    end)
    local txt = ""
    for k, item in pairs(statsTable) do
        local name = item.name:gsub("^%l", string.upper) .. " "
        if #name < padlen then
            local pl = padlen
            if #tostring(item.quantity) > 1 then
                pl = pl - #tostring(item.quantity)
                if pl <= 0 then
                    pl = 0
                end
            end
            name = string.rpad(name, padlen, " ")
        end
        txt = txt .. name .. item.quantity .. "\n"
    end
    txt = string.sub(txt, 1, -2) -- remove trailing newline
    return txt
end

string.rpad = function(str, len, char)
    if char == nil then
        char = ' '
    end
    return str .. string.rep(char, len - #str)
end

function BodyCount.EveryDays()
    local m = getGameTime():getMonth()
    local d = getGameTime():getDay()
    local pd = player:getModData()

    if not pd.bodyCount.DailyStats then
        pd.bodyCount.DailyStats = {}
    end

    if not pd.bodyCount.DailyStats[m] then
        pd.bodyCount.DailyStats[m] = {}
    end

    if not pd.bodyCount.DailyStats[m][d] then
        pd.bodyCount.DailyStats[m][d] = 0
    end
end

function BodyCount.WriteStats()
    local player = getPlayer()
    local pd = player:getModData()
    BodyCount.updateLogFiles(pd)
end

-- check if an XP event lead to zombie dead
function BodyCount.OnWeaponHitXp(player, weapon, zed)
    BodyCount.damageLog.xpEvent = true
    local sZed = tostring(zed)
    local damageLog = BodyCount.damageLog[sZed]
    if damageLog then
        if player:isLocalPlayer() and damageLog.dead then
            BodyCount.killSucceeded(player, zed, weapon); -- killed by weapon
            BodyCount.damageLog.dead = false
        end
        BodyCount.damageLog[sZed] = nil
    end
end

Events.OnGameStart.Add(BodyCount.WriteStats)
Events.OnZombieDead.Add(BodyCount.OnZombieDead)
Events.OnWeaponHitCharacter.Add(BodyCount.OnWeaponHitCharacter)
Events.OnWeaponHitXp.Add(BodyCount.OnWeaponHitXp)
Events.OnPlayerUpdate.Add(BodyCount.OnPlayerUpdate)
Events.OnEnterVehicle.Add(BodyCount.OnEnterVehicle)
Events.OnExitVehicle.Add(BodyCount.OnExitVehicle)
Events.EveryDays.Add(BodyCount.EveryDays)