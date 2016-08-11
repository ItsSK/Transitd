function clearSessionList() {
	$("#sessions").empty();
}

function insertSession(sid, name, meshIP, port, method, internetIPv4, internetIPv6, timeout_timestamp)
{
	var row = $( "<tr>"
				+"<td class='sid'></td>"
				+"<td class='name'></td>"
				+"<td class='meshIP'></td>"
				+"<td class='port'></td>"
				+"<td class='method'></td>"
				+"<td class='internetIPv4'></td>"
				+"<td class='internetIPv6'></td>"
				+"<td class='timeout_timestamp'></td>"
				+"<button class='disconnect' id='disconnect'>Disconnect</button></td>"
				+"</tr>");
	row.find(".sid").text(sid);
	row.find(".name").text(name);
	row.find(".meshIP").text(meshIP);
	row.find(".port").text(port);
	row.find(".method").text(method);
	row.find(".internetIPv4").text(internetIPv4);
	row.find(".internetIPv6").text(internetIPv6);
	row.find(".timeout_timestamp").text(timeout_timestamp);
	row.find(".disconnect").click(function(e) {
		e.preventDefault();
		// todo: trigger disconnection
		
	});
 
	$("#sessions").append(row);
}

function reloadSessions()
{
	service.listSessions({
		params: [],
		onSuccess: function(result) {
			clearSessionList();
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					var activeSessions = result.sessions;
					for (index = 0; index < activeSessions.length; ++index)
					{
						var activeSession = activeSessions[index];
						insertSession(activeSession.sid,
									  activeSession.name,
									  activeSession.meshIP,
									  activeSession.port,
									  activeSession.method,
									  activeSession.internetIPv4,
									  activeSession.internetIPv6,
									  activeSession.timeout_timestamp);
					}
				}
				else
					logAppendMessage('danger', result.errorMsg);
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			return true;
		}
	});
	
}
