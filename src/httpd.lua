--- @module httpd
local httpd = {}

local xavante = require("xavante")
local filehandler = require("xavante.filehandler")
local redirecthandler = require("xavante.redirecthandler")
local wsapixavante = require("wsapi.xavante")

local config = require("config")
local threadman = require("threadman")

-- Define here where Xavante HTTP documents scripts are located
local webDir = "./www"

local rules = {}

-- index (redirect)
table.insert(rules, {
	match  = "^[^%./]*/$",
	with   = redirecthandler,
	params = { "index.html" }
})

-- rpc (redirect)
table.insert(rules, {
	match  = "^[^%./]*/jsonrpc/?$",
	with   = redirecthandler,
	params = { "jsonrpc.lua" }
})

local sapi = require "wsapi.sapi"

local launcher_params = {
  isolated = false,
  reload = true,
  period = ONE_HOUR,
  ttl = ONE_DAY
}

-- custom lua handler that executes lua scripts within the same lua state as the main daemon process
function lua_handler(env)
	local lfs = require('lfs')
	lfs.chdir(webDir)
	local sapi = require "wsapi.sapi"
	env["PATH_TRANSLATED"] = lfs.currentdir()..env["PATH_INFO"]
	env["SCRIPT_FILENAME"] = lfs.currentdir()..env["PATH_INFO"]
	return sapi.run(env)
end

-- lua cgi
table.insert(rules, {
	match = "%.lua$",
	with = wsapixavante.makeHandler(lua_handler, nil, webDir, nil, nil)
})

-- static content
table.insert(rules, {
	match  = ".",
	with   = filehandler,
	params = { baseDir = webDir }
})

local listenOn = {}

local function xavante_params(addr, port)
	return { host = addr, port = port }
end

if (config.daemon.listenIpv6) then
	table.insert(listenOn, xavante_params('::', config.daemon.rpcport))
end

if (config.daemon.listenIpv4) then
	table.insert(listenOn, xavante_params('0.0.0.0', config.daemon.rpcport))
end


function httpd.run()
	
	for ifs, server in pairs(listenOn) do
	
	print('[xavante]', 'listening on '..server.host..' port '..server.port)
	
	xavante.HTTP {
		defaultHost = { rules = rules },
		server = server
	  }
	
	end
	
	local listener = threadman.registerListener("xavante")
	
	xavante.start(function()
		local msg = "";
		while msg ~= nil do
			msg = listener:listen(true)
			if msg ~= nil then
				if msg["type"] == "exit" then
					return true
				end
			end
		end
		return false
	end, 1);
	
	threadman.unregisterListener(listener)
	
end

return httpd
