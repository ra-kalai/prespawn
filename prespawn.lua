#!/usr/bin/env lem
-- prespawn.lua is free software: you can redistribute it and/or modify it
-- under the terms of the GNU Lesser General Public License as
-- published by the Free Software Foundation, either version 3 of
-- the License, or (at your option) any later version.
--
-- prespawn.lua is distributed in the hope that it will be useful, but
-- WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Lesser General Public License for more details.
--
-- You should have received a copy of the GNU Lesser General Public
-- License along with prespawn.lua.  If not, see <http://www.gnu.org/licenses/>.
--

local cmd = require 'lem.cmd'
local io = require 'lem.io'
local os = require 'lem.os'
local utils = require 'lem.utils'
local hathaway = require 'lem.hathaway'

local urldecode =  hathaway.urldecode
local parseform = hathaway.parseform

local spawn = utils.spawn
local format = string.format

local function sleep(t)
  local sleeper = utils.newsleeper()
  sleeper:sleep(t)
end

local args = {
  last_arg = "[cmd to run]",
  intro = "Available options are:",
  possible = {
    {'h', 'help', {desc="Display this", type='counter'}},
    {'t', 'tcp-listen', {desc="tcp control port", default_value='*:1984'}},
    {'w', 'http-listen', {desc="http control port", default_value='*:8080'}},
    {'m', 'min-instance', {desc="min number of instance", default_value=4}},
    {'k', 'keep-around', {desc="keep around *n* read entry of stdout, stdin", default_value=100}},
    {'r', 'respawn-delay', {desc="set the minimum respawn delay in second", default_value=0.1}},
    {'d', 'debug', {desc="debug / verbose mode", type='counter'}},
  },
}

local parg = cmd.parse_arg(args, arg)

if parg.err then
  cmd.display_usage(args, parg)
end

if parg:is_flag_set('help') then
  cmd.display_usage(args, {self_exe=arg[0]})
end

local g_respawn_delay = parg:get_last_val('respawn-delay')
local g_http_listen = parg:get_last_val('http-listen')
local g_debug = parg:is_flag_set('debug')
local g_keep_around = tonumber(parg:get_last_val('keep-around'))
local g_keep_around_2 = g_keep_around * 2
local g_http_host, g_http_port = g_http_listen:match('([^:]*):([0-9]+)$')

if g_http_listen ~= '' and (g_http_host == nil or g_http_port == nil) then
  io.stderr:write(format("http-listen parameter: '%s' is invalid", g_http_listen))
  cmd.display_usage(args, {self_exe=arg[0]})
end

local g_tcp_listen = parg:get_last_val('tcp-listen')
local g_tcp_host, g_tcp_port = g_tcp_listen:match('([^:]*):([0-9]+)$')

if parg.last_arg[0] == nil then
  cmd.display_usage(args, parg)
end

local instance_list = {}

local g_spawn_instance_per_second = 0

local function drain_fd(pipe, fdname, ret, instance)
  local r
  local out = ret[fdname]
  while true do
    r = pipe[fdname]:read()
    if r == nil then
      break
    end
    out[#out+1] = r

    if #out > g_keep_around_2 then
      local out_b = {}
      for i=g_keep_around, #out do
        out_b[#out_b + 1] = out[i]
      end
      ret[fdname] = out_b
      out = ret[fdname]
    end
    if instance[4] then
      if instance[4][fdname] then
        instance[4][fdname]:write(r)
      end
    end
  end
end

local function find_instance_id(pid)
  pid = tonumber(pid)
  local id
  for i, v in ipairs(instance_list) do
    if v[2] == pid then
      id = i
      break
    end
  end
  return id
end

local function remove_instance(pid)
  local id = find_instance_id(pid)
  table.remove(instance_list, id)
end

local function spawn_instance(cmd)
  local ret = {stderr = {}, stdout = {}}
  local instance_pipe, pid = io.popen(cmd, '3s')

  local instance = {instance_pipe, pid, ret}

  spawn(function () 
    drain_fd(instance_pipe, 'stderr', ret, instance)
  end)
  spawn(function () 
    drain_fd(instance_pipe, 'stdout', ret, instance)
  end)
  spawn(function () 
    os.waitpid(pid, 0)
    remove_instance(pid)
  end)

  instance_list[#instance_list+1] = instance
end


local g_min_instance = tonumber(parg:get_last_val('min-instance'))
local g_cmd = parg.last_arg[0] ..' '.. table.concat(parg.last_arg, ' ')
local g_spawn_instance = 0

local function spawn_min_number_of_instance()
  while #instance_list < g_min_instance do
    spawn_instance(g_cmd)
    g_spawn_instance = g_spawn_instance + 1
  end
end

-- the main part of the program, keep at least n instance alive
spawn(function ()
  while true do
    spawn_min_number_of_instance()
    sleep(g_respawn_delay)
  end
end)

-- keep and a update a spawned instance per second stats
spawn(function ()
  local old_count = 0
  while true do
    old_count = g_spawn_instance
    sleep(1)
    g_spawn_instance_per_second = g_spawn_instance - old_count
  end
end)


-- http process controller
if g_http_listen ~= '' then -- --%{

  if g_debug then
    hathaway.debug = print
  else
    hathaway.debug = function () end
  end
  
  hathaway.import()
  
  GET('/', function(req, res)
  local page = {
  [[
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<body>
]],
  
  format("cmd <div id=cmd>%s</div>", g_cmd),
  format("number of instance spawned <div id=g_spawn_instance>%d</div>", g_spawn_instance),
  format("spawn per second <div id=g_spawn_instance_per_second>%d</div>", g_spawn_instance_per_second),
  format("current number of instance <div id=current_number_of_instance>%d</div>", #instance_list),
  (function ()
    local ret = {'<h3> proc list: </h1>','<ul>'}
    for i, v in ipairs(instance_list) do
      ret[#ret+1] = '<li>'
      ret[#ret+1] = format('<a href=/proc/%d/stdout>/proc/%d/stdout</a> ', v[2], v[2])
      ret[#ret+1] = format('<a href=/proc/%d/stderr>/proc/%d/stderr</a> ', v[2], v[2])
      ret[#ret+1] = format('<a href=/proc/%d/stdin>/proc/%d/stdin</a>', v[2], v[2])
      ret[#ret+1] = '</li>'
    end
    ret[#ret+1] = '</ul>'
    return table.concat(ret)
  end)(),
  '<a href=/quit>quit</a>'
  }
    res:add(table.concat(page))
  end)
  
  GET('/quit', function (req, res)
    os.exit(0)
  end)
  
  GETM('^/proc/([0-9]+)/(.*)$', function(req, res, pid, stdwhat)
    local id = find_instance_id(pid)
  
    if (stdwhat == 'stdin') then
      res.headers['Content-Type'] = 'text/html'
      res:add([[
<form method=post>
<textarea name=data></textarea>
<input type=submit>
</form>
]])
      return
    end
  
    if id == nil or instance_list[id] == nil then
      res.status = 410
      res:add('gone')
      return
    end
  
    local ret = instance_list[id][3]
    res:add(table.concat(ret[stdwhat],'\n'))
  end)
  
  POSTM('^/proc/([0-9]+)/stdin$', function(req, res, pid, stdwhat)
    local form = parseform(req:body())
    local id = find_instance_id(pid)
  
    if id == nil or instance_list[id][1] == nil then
      res.status = 410
      res:add('gone')
      return
    end
  
    local ret = instance_list[id][1]
  
    form.data  = form.data or ''
    ret.stdin:write(form.data)
  
    res:add('ok')
  end)
  
  spawn(function ()
    Hathaway(g_http_host, g_http_port)
  end)
end -- }%--

-- tcp process controller
-- we expect one line like:
--  > stdin stdout close-after-dc
--  < pid: 3123
--  < the stdout strean of the process 3123 will be sent over the socket
--  > and anything received over the socket will go to the stdin of the process with pid 3123
--  > in case of disconnect, the stdin, stdout, stderr file descriptor of the (PID 3123)process
--  > will be close as we specified a *close-after-dc* option
if g_tcp_listen ~= '' then
  spawn(function ()
    sock = io.tcp.listen4(g_tcp_host, g_tcp_port)
    sock:autospawn(function (client)
      local todo = client:read("*l")

      if todo:match('exit') then os.exit(0) end

      local id
  
      for i, v in ipairs(instance_list) do
        if v[4] == nil then
          v[4] = {}
          id = i
          break ;
        end
      end
  
      if id ~= nil  then
        client:write(format('pid: %d\n', instance_list[id][2]))
      else
        client:write('no client available')
        client:close()
        return 
      end

  
      local pipe = instance_list[id][1]
  
      if todo:match('stdout') then instance_list[id][4].stdout = client end
      if todo:match('stderr') then instance_list[id][4].stderr = client end
  
      if todo:match('stdin') then
        local r
        while true do
          r = client:read()
          if r == nil then
            break
          else
            pipe.stdin:write(r)
          end
        end
      end

      instance_list[id][4] = {}

      if todo:match('close-after-dc') then
        instance_list[id][1].stdin:close()
        instance_list[id][1].stdout:close()
        instance_list[id][1].stderr:close()
      end
  
      client:close()
    end)
  end)
end
