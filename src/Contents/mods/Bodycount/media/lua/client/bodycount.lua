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
    local pd = player:getModData()

    local zedBurning = zed:isOnFire()
    if pd.inVehicle or zedBurning then
        -- If player is in vehicle or zombie burned the XP event is not triggered
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

function BodyCount.updateLogFiles(pd) -- playerModData
    if not pd.bodyCount then
        pd.bodyCount = {}
    end
    if not pd.bodyCount.WeaponCategory then
        pd.bodyCount.WeaponCategory = {}
    end
    if not pd.bodyCount.WeaponType then
        pd.bodyCount.WeaponType = {}
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

    str = BodyCount.SerializeStatsString(pd.bodyCount.WeaponCategory)
    BodyCount.overwrite("mod_bodycount_categories.txt", str)
    str = BodyCount.SerializeStatsString(pd.bodyCount.WeaponType)
    BodyCount.overwrite("mod_bodycount_types.txt", str)
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

function BodyCount.SerializeStatsJson(table)
    local json = ""
    for k, v in pairs(table) do
        json = json .. "{\"name\": \"" .. k:gsub("^%l", string.upper) .."\", \"quantity\": " .. v .. "},"
    end
    json = string.sub(json, 1, -2) -- remove trailing comma
    return "[" .. json .. "]"
end

function BodyCount.SerializeStatsString(table)
    local padlen = 0
    for k, v in pairs(table) do
        if #k > padlen then
            padlen = #k
        end
    end
    padlen = padlen +2 -- add colon and single whitespace
    local txt = ""
    for k, v in pairs(table) do
        local name = k:gsub("^%l", string.upper) .. ": "
        if #name < padlen then
            name = string.rpad(name, padlen, " ")
        end
        txt = txt .. name .. v .. "\n"
    end
    txt = string.sub(txt, 1, -2) -- remove trailing newline
    return txt
end

string.rpad = function(str, len, char)
    if char == nil then char = ' ' end
    return str .. string.rep(char, len - #str)
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