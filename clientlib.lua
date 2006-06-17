--[[

    Copyright (c) 2006 Florian Wesch <fw@dividuum.de>. All Rights Reserved.
    
    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    59 Temple Place - Suite 330, Boston, MA  02111-1307, USA

]]--

-----------------------------------------------------------
-- Klassen fuer Clientverbindung bauen
-----------------------------------------------------------

clients= {}

Client = {}

function Client.create(fd, addr)
    local obj = {}
    setmetatable(obj, {
        __index = function(self, what)
            -- Nach Klassenmethode suchen
            if Client[what] then
                return Client[what]
            end
            -- Nix? Dann per default in Objekttabelle suchen
        end
    })
    clients[fd] = obj
    obj.fd   = fd
    obj:on_new_client(addr)
end

function Client.check_accept(addr) 
    return true
end

function Client:readln()
    return coroutine.yield(self.thread)
end

function Client:on_new_client(addr) 
    self.addr = addr
    self.finished = false
    print(self.addr .. " accepted")
    add_to_scroller(self.addr .. " joined")
    self.thread = coroutine.create(self.handler)
    local ok, msg = coroutine.resume(self.thread, self)
    if not ok then
        self:writeln(msg)
    end
end

function Client:on_destroy(reason)
    print(self.addr .. " closed: " .. reason)
    add_to_scroller(self.addr .. " disconnected: " .. reason)
end


function Client:on_input(line)
    local ok, msg = coroutine.resume(self.thread, line)
    if not ok then
        self:writeln(msg)
        self:writeln("restarting mainloop...")
        self.thread = coroutine.create(self.handler)
        local ok, msg = coroutine.resume(self.thread, self)
        if not ok then
            self:writeln(msg)
            return false
        end
    end
    return not self.finished
end

function Client:disconnect()
    self.finished = true
end

function Client:write(data) 
    write_to_client(self.fd, data)
end

function Client:turn_into_guiclient()
    turn_into_guiclient(self.fd)
end

function Client:attach_to_player(playerno, pass)
    local ok, ret = pcall(attach_client_to_player, self.fd, playerno, pass)
    if not ok then
        return ret
    elseif not ret then
        return "attach failed. password wrong?"
    else
        return nil
    end
end

function Client:detach()
    local playerno = self:get_player()
    if playerno then
        detach_client_from_player(self.fd, playerno)
    end
end

function Client:get_player()
    return player_number(self.fd)
end

function Client:set_player_name(name)
    local playerno = self:get_player()
    if playerno and get_player_name(playerno) ~= name and name ~= '' then
        local oldname = get_player_name(playerno)
        set_player_name(playerno, name)
        local newname = get_player_name(playerno)
        add_to_scroller(oldname .. " renamed to " .. newname)
        return true
    else
        return false
    end
end

function Client:kill()
    if self:get_player() then
        player_kill(self:get_player())
        return true
    else
        return false
    end
end

function Client:execute(code)
    player_execute(self.fd, code)
end

function Client:writeln(line)
    if line then 
        self:write(line .. "\n")
    else
        self:write("\n")
    end
end

function Client.writeAll(line)
    table.foreach(clients, function (fd, obj)
                               obj:write(line)
                           end)
end

function Client.writelnAll(line)
    table.foreach(clients, function (fd, obj)
                               obj:writeln(line)
                           end)
end

wall = Client.writelnAll

-----------------------------------------------------------
-- C Callbacks
-----------------------------------------------------------

function on_new_client(addr) 
    return Client.check_accept(addr)
end

function on_client_accepted(fd, addr) 
    Client.create(fd, addr)
end

function on_client_input(fd, line)
    if clients[fd].kill_me then 
        return false
    else
        return clients[fd]:on_input(line)
    end
end

function on_client_close(fd, reason)
    clients[fd]:on_destroy(reason)
    clients[fd] = nil
end


function server_tick()
    server_tick = coroutine.wrap(ServerMain)
end

-----------------------------------------------------------
-- Praktisches?
-----------------------------------------------------------

function p(x) 
    if type(x) == "table" then
        print("+--- Table: " .. tostring(x))
        for key, val in x do
            print("| " .. tostring(key) .. " " .. tostring(val))
        end
        print("+-----------------------")
    else
        print(type(x) .. " - " .. tostring(x))
    end
end

function clientlist(adminfd)
    table.foreach(clients, function (fd, obj)
                               write_to_client(adminfd, fd .. " - " .. obj.addr .. "\n")
                           end)
end

function kick(fd, msg)
    -- XXX: momentan bis zur naechsten eingabe delayed...
    write_to_client(fd, msg .. "\n")
    clients[fd].kill_me = true
end

function killall()
    for n = 0, MAXPLAYERS - 1 do
        pcall(player_kill_all_creatures, n)
    end
end

function reset()
    killall()
    for n = 0, MAXPLAYERS - 1 do
        pcall(set_player_score, n, 0)
    end
    wall("Game restarted")
end

function kickall()
    table.foreach(clients, function (fd, obj)
                               clients[fd].kill_me = true
                           end)
end
