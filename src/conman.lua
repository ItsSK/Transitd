
--- @module conman
local conman = {}

local config = require("config")
local db = require("db")
local cjdns = require("rpc-interface.cjdns")
local threadman = require("threadman")
local rpc = require("rpc")

local conManTs = 0

local subscriberManager = function()
	
	local sinceTimestamp = conManTs
	conManTs = os.time()
	
	local subscribers, err = db.getTimingOutSubscribers(sinceTimestamp)
	if err == nil and subscribers == nil then
		err = "Unexpected subscriber list query result"
	end
	if err then
		threadman.notify({type = "error", module = "conman", error = err})
		return
	end
	
	for k,subscriber in pairs(subscribers) do
		local at = ""
		if subscriber.meshIP ~= nil then
			at = at..subscriber.method.."::"..subscriber.meshIP.." "
		end
		local addr = ""
		if subscriber.internetIPv4 ~= nil then
			addr = addr..subscriber.internetIPv4.." "
		end
		if subscriber.internetIPv6 ~= nil then
			addr = addr..subscriber.internetIPv6.." "
		end
		
		if subscriber.method == "cjdns" then
			cjdns.releaseConnection(subscriber.sid)
		else
			threadman.notify({type = "error", module = "conman", error = "Unknown method", method = subscriber.method})
		end
		
		threadman.notify({type = "subscriberSessionTimedOut", ["sid"] = subscriber.sid})
	end
end

local gatewayManager = function()
	
	local currentTimestamp = os.time()
	local gracePeriod = 10;
	
	local sessions, err = db.getLastActiveSessions()
	if err == nil and sessions == nil then
		err = "Unexpected session list query result"
	end
	if err then
		threadman.notify({type = "error", module = "conman", error = err})
		return
	end
	
	for k, session in pairs(sessions) do
		if session.subscriber == 0 and session.active == 1 then
			if currentTimestamp > session.timeout_timestamp then
				
				db.deactivateSession(session.sid)
				threadman.notify({type = "gatewaySessionTimedOut", ["sid"] = session.sid})
				
			elseif currentTimestamp > session.timeout_timestamp-gracePeriod then
				
				local gateway = rpc.getProxy(session.meshIP, session.port)
				
				local result, err = gateway.renewConnection(session.sid)
				if err then
					threadman.notify({type = "error", module = "conman", ["error"] = err})
				elseif not result then
					threadman.notify({type = "error", module = "conman", ["error"] = "Unknown error"})
				elseif result.success == false and result.errorMsg then
					threadman.notify({type = "error", module = "conman", ["error"] = result.errorMsg})
				elseif result.success == false then
					threadman.notify({type = "error", module = "conman", ["error"] = "Unknown error"})
				else
					db.updateSessionTimeout(session.sid, result.timeout)
					threadman.notify({type = "renewedGatewaySession", ["sid"] = session.sid, ["timeout"] = result.timeout})
				end
			end
		end
	end
end

function conman.connectToGateway(ip, port, method, sid)
	
	local gateway = rpc.getProxy(ip, port)
	
	print("[conman] Checking " .. ip .. "...")
	local info, err = gateway.nodeInfo()
	if err then
		return nil, "Failed to connect to " .. ip .. ": " .. err
	else
		db.registerNode(info.name, ip, port)
	end
	
	if info.methods then
		-- check to make sure method is supported
		local supported = false
		for k, m in pairs(info.methods) do
			if m == method then
				supported = true
			end
			-- register methods
			if m and m.name then
				db.registerGateway(info.name, ip, port, m.name)
			end
		end
	else
		method = nil
	end
	
	if method == nil then
		return nil, "No supported connection methods at " .. ip
	end
	
	print("[conman] Connecting to gateway '" .. info.name .. "' at " .. ip)
	
	local result
	
	if method == "cjdns" then
		print("[conman] Connecting to " .. ip .. " port " .. port)
		db.registerGatewaySession(sid, info.name, method, ip, port)
		result = cjdns.connectTo(ip, port, method, sid)
		if result.success then
			print("Registered with gateway at " .. ip .. " port "..port.."!")
			if result.timeout then
				if result.ipv4        then print("IPv4:" .. result.ipv4)                        end
				if result.ipv4gateway then print("IPv4 gateway:" .. result.ipv4gateway)         end
				if result.ipv6        then print("IPv6:" .. result.ipv6)                        end
				if result.ipv6gateway then print("IPv6 gateway:" .. result.ipv6gateway)         end
				if result.dns         then print("IPv6 DNS:" .. result.dns)                     end
				if result.timeout     then print("Timeout is " .. result.timeout .. " seconds") end
			end
			db.updateGatewaySession(sid, true, result.ipv4, result.ipv6, result.timeout)
		end
		return result, nil
	else
		return nil, "Unsupported method"
	end
	
	if result.success then
		return true
	else
		return nil, result.errorMsg
	end
end

local connectionManager = function()
	subscriberManager()
	gatewayManager()
end

function conman.startConnectionManager()
	local socket = require("socket")
	local listener = threadman.registerListener("conman")
	while true do
		socket.sleep(2)
		connectionManager()
		local msg = {};
		while msg ~= nil do
			msg = listener:listen(true)
			if msg ~= nil then
				if msg["type"] == "exit" then
					threadman.unregisterListener(listener)
					return
				end
			end
		end
	end
	
end

return conman
