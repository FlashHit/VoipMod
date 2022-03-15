if not Voip then
	print("[WARNING] Please add '-updateBranch dev' to your launch arguments to use the Voip feature.")
	return
end

---@class PlayerVoipLevel
local PlayerVoipLevel = {
	Team = 1,
	Squad = 2,
	Disabled = 3
}

local m_IsEmitting = false

---@type table<string, boolean>
local m_MutedPlayers = {}

---@return ModSetting
local function _GetDefaultVolume()
	local s_AsTable = { value = 5.0 }

	if not SettingsManager then
		return s_AsTable
	end

	local s_ModSetting = SettingsManager:GetSetting("DefaultVoipVolume")

	if not s_ModSetting then
		s_ModSetting = SettingsManager:DeclareNumber("DefaultVoipVolume", 5.0, 0.001, 100.0, { displayName = "Default Voip Volume", showInUi = true })
		s_ModSetting.value = 5.0
	end

	if not s_ModSetting then
		return s_AsTable
	end

	return s_ModSetting
end

---@type ModSetting
local m_DefaultVolumeModSetting = _GetDefaultVolume()

---@return ModSetting
local function _GetPlayerVoipLevel()
	local s_AsTable = { value = "Squad" }

	if not SettingsManager then
		return s_AsTable
	end

	local s_ModSetting = SettingsManager:GetSetting("PlayerVoipLevel")

	if not s_ModSetting then
		s_ModSetting = SettingsManager:DeclareOption("PlayerVoipLevel", "Squad", { "Team", "Squad", "Disabled" }, false, { displayName = "PlayerVoipLevel", showInUi = true })
		s_ModSetting.value = "Squad"
	end

	if not s_ModSetting then
		return s_AsTable
	end

	return s_ModSetting
end

---@return ModSetting
local function _GetPushToTalkKey()
	local s_AsTable = { value = InputDeviceKeys.IDK_LeftAlt }

	if not SettingsManager then
		return s_AsTable
	end

	local m_ModSetting = SettingsManager:GetSetting("VoipPushToTalk")

	if not m_ModSetting then
		m_ModSetting = SettingsManager:DeclareKeybind("VoipPushToTalk", InputDeviceKeys.IDK_LeftAlt, { displayName = "Voip Push To Talk key", showInUi = true })
		m_ModSetting.value = InputDeviceKeys.IDK_LeftAlt
	end

	if not m_ModSetting then
		return s_AsTable
	end

	return m_ModSetting
end

---@type ModSetting
local m_PlayerVoipLevelModSetting = _GetPlayerVoipLevel()

Events:Subscribe('Level:Loaded', function()
	NetEvents:SendLocal('Player:VoipLevel', PlayerVoipLevel[m_PlayerVoipLevelModSetting.value])
	Events:Dispatch("FromVoipMod:DefaultVoipVolume", m_DefaultVolumeModSetting.value)
	Events:Dispatch("FromVoipMod:PlayerVoipLevel", m_PlayerVoipLevelModSetting.value)
end)

---@type ModSetting
local m_PushToTalkModSetting = _GetPushToTalkKey()

---@param p_Channel VoipChannel
Events:Subscribe('Voip:ChannelOpened', function(p_Channel)
	p_Channel.transmissionMode = VoipTransmissionMode.PushToTalk
end)

---@param p_Enable boolean
local function _SquadLRBalance(p_Enable)
	local s_LocalPlayer = PlayerManager:GetLocalPlayer()

	if not s_LocalPlayer then
		return
	end

	local s_SquadChannel = Voip:GetChannel("Team" .. s_LocalPlayer.teamId .. "_Squad" .. s_LocalPlayer.squadId)

	if not s_SquadChannel then
		return
	end

	local s_TeamChannel = Voip:GetChannel('Team' .. s_LocalPlayer.teamId)

	for _, l_Emitter in pairs(s_SquadChannel.emitters) do
		if l_Emitter.player ~= s_LocalPlayer then
			if p_Enable then
				l_Emitter.leftBalance = 1.0
				l_Emitter.rightBalance = 1.0
			else
				-- check if we are in a team channel
				if s_TeamChannel then
					-- get all players in that team channel
					for _, l_Player in pairs(s_TeamChannel.players) do
						-- check if this squad mate is in this team channel as well
						if l_Player == l_Emitter.player then
							l_Emitter.leftBalance = 0.0
							l_Emitter.rightBalance = 0.0
							break
						end
					end
				end
			end
		end
	end
end

---@param p_Channel VoipChannel
---@param p_Player Player
---@param p_Emitter VoipEmitter
Events:Subscribe('VoipChannel:PlayerJoined', function(p_Channel, p_Player, p_Emitter)
	--print('Player ' .. p_Player.name .. ' joined voip channel ' .. p_Channel.name)

	p_Emitter.emitterType = VoipEmitterType.Local
	p_Emitter.muted = false

	if m_MutedPlayers[p_Player.name] then
		p_Emitter.volume = 0.0
	else
		p_Emitter.volume = m_DefaultVolumeModSetting.value
	end

	-- We don't want to hear ourselves.
	if p_Player == PlayerManager:GetLocalPlayer() then
		if PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Team then
			_SquadLRBalance(false)
		elseif PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Squad then
			_SquadLRBalance(true)
		end

		p_Emitter.leftBalance = 0.0
		p_Emitter.rightBalance = 0.0
		return
		-- We don't want to hear mates in squad and team voipchannel at the same time
	elseif PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Team then
		if p_Channel.name:match("Squad") then
			local s_TeamChannel = Voip:GetChannel('Team' .. p_Player.teamId)

			-- check if we are in a team channel (we should be in one)
			if s_TeamChannel then
				-- get all players in that team channel
				for _, l_Player in pairs(s_TeamChannel.players) do
					-- check if this squad mate is in this team channel as well
					if l_Player == p_Player then
						-- mute in squad
						p_Emitter.leftBalance = 0.0
						p_Emitter.rightBalance = 0.0
						return
					end
				end
			end
		elseif p_Channel.name:match("Team") then
			local s_SquadChannel = Voip:GetChannel("Team" .. p_Player.teamId .. "_Squad" .. p_Player.squadId)

			-- check if we are in a squad channel
			if s_SquadChannel then
				-- get all emitters + players in that squad channel
				for _, l_Emitter in pairs(s_SquadChannel.emitters) do
					-- check if this squad mate is in this team channel as well
					if l_Emitter.player == p_Player then
						-- mute in squad
						l_Emitter.leftBalance = 0.0
						l_Emitter.rightBalance = 0.0
						return
					end
				end
			end
		end
	end

	p_Emitter.leftBalance = 1.0
	p_Emitter.rightBalance = 1.0
end)

Events:Subscribe('Client:UpdateInput', function()
	if InputManager:WentKeyDown(m_PushToTalkModSetting.value) and not m_IsEmitting then
		local s_LocalPlayer = PlayerManager:GetLocalPlayer()

		if s_LocalPlayer == nil then
			return
		end

		if PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Squad then
			local s_Channel = Voip:GetChannel('Team' .. s_LocalPlayer.teamId .. '_Squad' .. s_LocalPlayer.squadId)

			if s_Channel ~= nil then
				m_IsEmitting = true
				s_Channel:StartTransmitting()
			end
		elseif PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Team then
			local s_Channel = Voip:GetChannel('Team' .. s_LocalPlayer.teamId)

			if s_Channel ~= nil then
				m_IsEmitting = true
				s_Channel:StartTransmitting()
			end

			local s_SquadChannel = Voip:GetChannel('Team' .. s_LocalPlayer.teamId .. '_Squad' .. s_LocalPlayer.squadId)

			if s_SquadChannel ~= nil then
				m_IsEmitting = true
				s_SquadChannel:StartTransmitting()
			end
		end
	elseif InputManager:WentKeyUp(m_PushToTalkModSetting.value) then
		local s_LocalPlayer = PlayerManager:GetLocalPlayer()

		if s_LocalPlayer == nil then
			return
		end

		if PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Squad then
			local s_Channel = Voip:GetChannel('Team' .. tostring(s_LocalPlayer.teamId) .. '_Squad' .. tostring(s_LocalPlayer.squadId))

			if s_Channel ~= nil then
				m_IsEmitting = false
				s_Channel:StopTransmitting()
			end
		elseif PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Team then
			local s_Channel = Voip:GetChannel('Team' .. tostring(s_LocalPlayer.teamId))

			if s_Channel ~= nil then
				m_IsEmitting = false
				s_Channel:StopTransmitting()
			end

			local s_SquadChannel = Voip:GetChannel('Team' .. s_LocalPlayer.teamId .. '_Squad' .. s_LocalPlayer.squadId)

			if s_SquadChannel ~= nil then
				m_IsEmitting = false
				s_SquadChannel:StopTransmitting()
			end
		end
	end
end)

---@param p_String '"Team"'|'"Squad"'|'"Disabled"'
local function _SetPlayerVoipLevel(p_String)
	m_PlayerVoipLevelModSetting.value = p_String
	NetEvents:SendLocal('Player:VoipLevel', PlayerVoipLevel[p_String])
	Events:Dispatch("BIA:PlayerVoipLevel", m_PlayerVoipLevelModSetting.value)

	if PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Team then
		_SquadLRBalance(false)
	elseif PlayerVoipLevel[m_PlayerVoipLevelModSetting.value] == PlayerVoipLevel.Squad then
		_SquadLRBalance(true)
	end
end

---@param p_Args string[]
Console:Register("playerVoipLevel", "Sets the Player Voip Level ('Team', 'Squad', 'Disabled')", function(p_Args)
	if p_Args and p_Args[1] and PlayerVoipLevel[p_Args[1]] ~= nil then
		_SetPlayerVoipLevel(p_Args[1])

		print("PlayerVoipLevel: " .. p_Args[1])
	else
		print("InvalidArguments")
	end
end)

---@param p_Args string[]
Console:Register("pushToTalkKey", "Sets the Voip push-to-talk key (https://docs.veniceunleashed.net/vext/ref/fb/inputdevicekeys/)", function(p_Args)
	if p_Args and p_Args[1] and tonumber(p_Args[1]) then
		local s_Number = tonumber(p_Args[1])

		if s_Number >= 0 and s_Number <= 255 then
			m_PushToTalkModSetting.value = s_Number
			print("PlayerVoipLevel: " .. p_Args[1])
		else
			print("InvalidArguments")
		end
	else
		print("InvalidArguments")
	end
end)

---@param p_NewVolume number
local function _SetDefaultEmitterVolume(p_NewVolume)
	for _, l_Emitter in pairs(Voip:GetEmitters()) do
		-- Example: 0.5 = 2.5 / 5.0
		local s_Multiplier = l_Emitter.volume / m_DefaultVolumeModSetting.value

		-- Example: 2.0 = 4.0 * 0.5
		l_Emitter.volume = p_NewVolume * s_Multiplier
	end

	Events:Dispatch("BIA:DefaultVoipVolume", p_NewVolume)
end

---@param p_Args string[]
Console:Register("defaultVolume", "Sets the new default volume (default 5.0)", function(p_Args)
	if p_Args and p_Args[1] and tonumber(p_Args[1]) then
		local s_Number = tonumber(p_Args[1])

		if s_Number > 0.0 and s_Number <= 100.0 then
			_SetDefaultEmitterVolume(s_Number)
			m_DefaultVolumeModSetting.value = s_Number
			print("Updated default volume to " .. m_DefaultVolumeModSetting.value)
		else
			print("InvalidArguments")
		end
	else
		print("InvalidArguments")
	end
end)

---@param p_Player Player
---@param p_Mute boolean
local function _MutePlayer(p_Player, p_Mute)
	NetEvents:SendLocal("VoipMod:MutedByPlayer", p_Player.name, p_Mute)

	for _, l_Emitter in pairs(Voip:GetEmitters()) do
		if l_Emitter.player == p_Player and not l_Emitter.muted then
			if p_Mute then
				l_Emitter.volume = 0.0
			else
				l_Emitter.volume = m_DefaultVolumeModSetting.value
			end
		end
	end
end

---@param p_Args string[]
Console:Register("mutePlayer", "Mutes a player by name", function(p_Args)
	if p_Args and p_Args[1] then
		local s_Player = PlayerManager:GetPlayerByName(p_Args[1])

		if s_Player then
			_MutePlayer(s_Player, true)
			m_MutedPlayers[s_Player.name] = true
			print("Muted player " .. s_Player.name)
		else
			print("PlayerNotFound")
		end
	else
		print("InvalidArguments")
	end
end)

---@param p_Args string[]
Console:Register("unmutePlayer", "Unmutes a player by name", function(p_Args)
	if p_Args and p_Args[1] then
		local s_Player = PlayerManager:GetPlayerByName(p_Args[1])

		if s_Player then
			_MutePlayer(s_Player, false)
			m_MutedPlayers[s_Player.name] = nil
			print("Unmuted player " .. s_Player.name)
		else
			print("PlayerNotFound")
		end
	else
		print("InvalidArguments")
	end
end)

---@param p_Player Player
---@param p_NewVolume number
local function _SetPlayerEmitterVolume(p_Player, p_NewVolume)
	for _, l_Emitter in pairs(Voip:GetEmitters()) do
		if l_Emitter.player == p_Player then
			l_Emitter.volume = p_NewVolume
		end
	end
end

---@param p_Args string[]
Console:Register("setVolumeOfPlayer", "Sets the new volume of this player by name + new volume (default 5.0)", function(p_Args)
	if p_Args and p_Args[1] and p_Args[2] and tonumber(p_Args[2]) then
		local s_Player = PlayerManager:GetPlayerByName(p_Args[1])

		if s_Player then
			local s_Number = tonumber(p_Args[2])

			if s_Number > 0.0 and s_Number <= 100.0 then
				_SetPlayerEmitterVolume(s_Player, s_Number)
				print("Updated volume of player " .. s_Player.name .. " to " .. s_Number)
			else
				print("InvalidArguments")
			end
		else
			print("PlayerNotFound")
		end
	else
		print("InvalidArguments")
	end
end)

---@param p_NewVolume number
Events:Subscribe("VoipMod:SetDefaultVolume", function(p_NewVolume)
	_SetDefaultEmitterVolume(p_NewVolume)
end)

---@param p_PlayerName string
---@param p_NewVolume number
Events:Subscribe("VoipMod:SetVolumeOfPlayer", function(p_PlayerName, p_NewVolume)
	if p_NewVolume <= 0.0 then
		p_NewVolume = 0.001
	end

	local s_Player = PlayerManager:GetPlayerByName(p_PlayerName)

	if s_Player then
		_SetPlayerEmitterVolume(s_Player, p_NewVolume)
	end
end)

---@param p_PlayerName string
---@param p_Mute boolean
Events:Subscribe("VoipMod:MutePlayer", function(p_PlayerName, p_Mute)
	local s_Player = PlayerManager:GetPlayerByName(p_PlayerName)

	if s_Player then
		_MutePlayer(s_Player, p_Mute)

		if p_Mute then
			m_MutedPlayers[s_Player.name] = true
		else
			m_MutedPlayers[s_Player.name] = nil
		end
	end
end)

---@param p_String string
Events:Subscribe("VoipMod:PlayerVoipLevel", function(p_String)
	_SetPlayerVoipLevel(p_String)
end)

---@param p_Player Player
---@param p_Mute boolean
local function _MutedByPlayer(p_Player, p_Mute)
	for _, l_Emitter in pairs(Voip:GetEmitters()) do
		if l_Emitter.player == p_Player then
			if p_Mute then
				l_Emitter.volume = 0.0
			else
				l_Emitter.volume = m_DefaultVolumeModSetting.value
			end

			l_Emitter.muted = p_Mute
		end
	end
end

---@param p_PlayerName string
---@param p_Mute boolean
NetEvents:Subscribe("VoipMod:MutedByPlayer", function(p_PlayerName, p_Mute)
	local s_Player = PlayerManager:GetPlayerByName(p_PlayerName)

	if s_Player then
		_MutedByPlayer(s_Player, p_Mute)
	end
end)
