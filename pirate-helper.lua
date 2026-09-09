-- pirate-helper.lua
-- HexChat Lua script for game automation, alarms, and timers.
-- Place in your HexChat addons directory (e.g., ~/.config/hexchat/addons/)

hexchat.register("Pirate Helper", "1.5", "Channel-specific alarms and timers for game automation")

local tasks = {}
local task_id_counter = 1

-- Helper: Parse HH:MM:SS string into hours, minutes, seconds
local function parse_time(time_str)
    local h, m, s = string.match(time_str, "^(%d+):(%d+):(%d+)$")
    if h and m and s then
        return tonumber(h), tonumber(m), tonumber(s)
    end
    return nil, nil, nil
end

-- /palarm <HH:MM:SS>
local function cmd_palarm(word, word_eol)
    if not word[2] then
        hexchat.print("Usage: /palarm <HH:MM:SS>")
        return hexchat.EAT_ALL
    end
    
    local h, m, s = parse_time(word[2])
    if not h then
        hexchat.print("Invalid time format. Use HH:MM:SS (e.g., 14:30:00)")
        return hexchat.EAT_ALL
    end

    local now = os.date("*t")
    local target = os.date("*t")
    target.hour = h
    target.min = m
    target.sec = s

    local diff = os.difftime(os.time(target), os.time(now))
    if diff <= 0 then
        diff = diff + 86400 -- If time has passed today, set for tomorrow
    end

    local server = hexchat.get_info("server") or ""
    local channel = hexchat.get_info("channel") or ""
    local id = task_id_counter
    task_id_counter = task_id_counter + 1

    -- Declare hook_ref first so the closure can capture it and unhook itself
    local hook_ref 
    
    local function alarm_cb(userdata)
        local ctx = hexchat.find_context(server, channel)
        local my_nick = hexchat.get_info("nick") or "Pirate"
        
        -- Include the nick to satisfy visual mention
        local msg = string.format("\002\00304[ALARM]\003\002 %s: %s time has arrived!", my_nick, word[2])
        
        if ctx then
            -- Emitting a highlight event forces HexChat's GUI to process it as a mention
            ctx:emit_print("Channel Msg Hilight", "PirateHelper", msg)
        else
            -- Fallback if the channel was closed
            hexchat.emit_print("Channel Msg Hilight", "PirateHelper", msg .. " (Orig: " .. channel .. ")")
        end
        
        -- macOS specific sound trigger (non-blocking). MacPorts GTK bell is notoriously unreliable.
        os.execute("afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &")
        
        -- Clean up
        if tasks[id] then tasks[id] = nil end
        if hook_ref then hexchat.unhook(hook_ref) end -- Force unhook
        
        return hexchat.UNHOOK or 0
    end

    hook_ref = hexchat.hook_timer(diff * 1000, alarm_cb)
    tasks[id] = { id = id, type = "alarm", time_str = word[2], server = server, channel = channel, hook = hook_ref }

    hexchat.print(string.format("Pirate Helper: Alarm [\002%d\002] set for %s in %s.", id, word[2], channel))
    return hexchat.EAT_ALL
end

-- /ptimer <HH:MM:SS> <msg> [num]
local function cmd_ptimer(word, word_eol)
    if not word[2] or not word[3] then
        hexchat.print("Usage: /ptimer <HH:MM:SS> <message> [num]")
        return hexchat.EAT_ALL
    end
    
    local h, m, s = parse_time(word[2])
    if not h then
        hexchat.print("Invalid time format. Use HH:MM:SS (e.g., 00:05:00 for 5 minutes)")
        return hexchat.EAT_ALL
    end

    local duration_ms = (h * 3600 + m * 60 + s) * 1000
    if duration_ms == 0 then
        hexchat.print("Timer duration must be greater than 00:00:00.")
        return hexchat.EAT_ALL
    end

    local msg_str = word_eol[3]
    local num = 1
    local last_word = word[#word]
    
    -- Check if the last word is a number (the repetition counter)
    if #word > 3 and tonumber(last_word) then
        num = tonumber(last_word)
        -- Extract the message without the trailing number
        local extracted = string.match(word_eol[3], "^(.*)%s+%d+$")
        if extracted and extracted ~= "" then
            msg_str = extracted
        else
            num = 1 -- Fallback if match fails
        end
    end

    local server = hexchat.get_info("server") or ""
    local channel = hexchat.get_info("channel") or ""
    local id = task_id_counter
    task_id_counter = task_id_counter + 1

    local runs_left = num
    
    -- Declare hook_ref first so the closure can capture it and unhook itself
    local hook_ref 

    local function timer_cb(userdata)
        local ctx = hexchat.find_context(server, channel)
        if ctx then
            ctx:command("say " .. msg_str)
        else
            hexchat.command("msg " .. channel .. " " .. msg_str)
        end
        
        runs_left = runs_left - 1
        
        if runs_left > 0 then
            if tasks[id] then
                tasks[id].runs = runs_left
            end
            return hexchat.KEEP_HOOK or 1
        else
            -- Timer is finished, force unhook explicitly 
            if tasks[id] then tasks[id] = nil end
            if hook_ref then hexchat.unhook(hook_ref) end
            return hexchat.UNHOOK or 0
        end
    end

    hook_ref = hexchat.hook_timer(duration_ms, timer_cb)
    tasks[id] = { id = id, type = "timer", duration_str = word[2], msg = msg_str, runs = runs_left, server = server, channel = channel, hook = hook_ref }
    
    hexchat.print(string.format("Pirate Helper: Timer [\002%d\002] set for %s. Will send message \002%d\002 time(s) in %s.", id, word[2], num, channel))
    return hexchat.EAT_ALL
end

-- /plist
local function cmd_plist(word, word_eol)
    local current_chan = hexchat.get_info("channel")
    local is_server_win = (hexchat.get_info("type") == 1)
    
    hexchat.print("\002--- Active Pirate Alarms & Timers ---\002")
    local count = 0
    
    for id, task in pairs(tasks) do
        if is_server_win or task.channel == current_chan then
            if task.type == "alarm" then
                hexchat.print(string.format("[\002%d\002] ALARM @ %s (Channel: %s)", id, task.time_str, task.channel))
            elseif task.type == "timer" then
                hexchat.print(string.format("[\002%d\002] TIMER repeating every %s | Msg: %s | Runs left: %d (Channel: %s)", id, task.duration_str, task.msg, task.runs, task.channel))
            end
            count = count + 1
        end
    end
    
    if count == 0 then
        if is_server_win then
            hexchat.print("No active alarms or timers globally.")
        else
            hexchat.print("No active alarms or timers for this channel.")
        end
    end
    hexchat.print("\002---------------------------------------\002")
    return hexchat.EAT_ALL
end

-- /pdel <num>
local function cmd_pdel(word, word_eol)
    if not word[2] then
        hexchat.print("Usage: /pdel <num>")
        return hexchat.EAT_ALL
    end
    
    local id = tonumber(word[2])
    if not id or not tasks[id] then
        hexchat.print("Invalid ID. Use /plist to see active IDs.")
        return hexchat.EAT_ALL
    end
    
    local current_chan = hexchat.get_info("channel")
    local is_server_win = (hexchat.get_info("type") == 1)
    
    if not is_server_win and tasks[id].channel ~= current_chan then
        hexchat.print("Error: Cannot delete task from another channel. Switch to " .. tasks[id].channel .. " or the Server window.")
        return hexchat.EAT_ALL
    end
    
    hexchat.unhook(tasks[id].hook)
    tasks[id] = nil
    hexchat.print(string.format("Pirate Helper: Task [\002%d\002] successfully deleted.", id))
    return hexchat.EAT_ALL
end

-- /pclear
local function cmd_pclear(word, word_eol)
    local current_chan = hexchat.get_info("channel")
    local is_server_win = (hexchat.get_info("type") == 1)
    local count = 0
    
    for id, task in pairs(tasks) do
        if is_server_win or task.channel == current_chan then
            hexchat.unhook(task.hook)
            tasks[id] = nil
            count = count + 1
        end
    end
    
    if is_server_win then
        hexchat.print(string.format("Pirate Helper: Cleared \002%d\002 task(s) globally.", count))
    else
        hexchat.print(string.format("Pirate Helper: Cleared \002%d\002 task(s) for channel %s.", count, current_chan))
    end
    return hexchat.EAT_ALL
end

-- /phelp
local function cmd_phelp(word, word_eol)
    hexchat.print("\002--- Pirate Helper Commands ---\002")
    hexchat.print("\002/palarm <HH:MM:SS>\002 - Beeps the client when local time arrives")
    hexchat.print("\002/ptimer <HH:MM:SS> <msg> [num]\002 - Sends a channel message after delay, optionally repeating [num] times")
    hexchat.print("\002/plist\002 - Lists active alarms and timers (channel specific, or all if run in server window)")
    hexchat.print("\002/pdel <num>\002 - Deletes a timer or alarm by its ID")
    hexchat.print("\002/pclear\002 - Clears all active timers and alarms for the current channel (or globally from server window)")
    hexchat.print("\002/phelp\002 - Displays this help message")
    hexchat.print("\002/pabout\002 - Displays about and version information")
    hexchat.print("\002------------------------------\002")
    return hexchat.EAT_ALL
end

-- /pabout
local function cmd_pabout(word, word_eol)
    hexchat.print("\002Pirate Helper v1.5 (Lua)\002")
    hexchat.print("Automates game tasks with channel-specific timers and absolute alarms.")
    return hexchat.EAT_ALL
end

-- Register commands
hexchat.hook_command("palarm", cmd_palarm, "Usage: /palarm <HH:MM:SS>")
hexchat.hook_command("ptimer", cmd_ptimer, "Usage: /ptimer <HH:MM:SS> <msg> [num]")
hexchat.hook_command("ptime", cmd_ptimer, "Alias for /ptimer")
hexchat.hook_command("plist", cmd_plist, "Usage: /plist")
hexchat.hook_command("pdel", cmd_pdel, "Usage: /pdel <num>")
hexchat.hook_command("pclear", cmd_pclear, "Usage: /pclear")
hexchat.hook_command("phelp", cmd_phelp, "Usage: /phelp")
hexchat.hook_command("pabout", cmd_pabout, "Usage: /pabout")

hexchat.print("\002Pirate Helper v1.5\002 loaded successfully! Type \002/phelp\002 for commands.")
