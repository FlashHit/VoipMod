if not Voip then
	error("Please add '-updateBranch dev' to your launch arguments to use this Voip mod. ")
	return
end

local m_TeamChannels = {}
local m_SquadChannels = {}

---@class PlayerVoipLevel
local PlayerVoipLevel = {
	Team = 1,
	Squad = 2,
	Disabled = 3
}

local m_PlayerSettings = {}
local m_PlayerLastTeam = {}

---@param p_Player Player
Events:Subscribe('Player:Authenticated', function(p_Player)
	-- by default the player can only talk to his squad
	if m_PlayerSettings[p_Player.name] == nil then
		m_PlayerSettings[p_Player.name] = PlayerVoipLevel.Squad
	end
end)

---@param p_Player Player
---@param p_TeamId TeamId|integer
local function _RemovePlayerFromTeamChannels(p_Player, p_TeamId)
	if m_TeamChannels[p_TeamId] ~= nil then
		m_TeamChannels[p_TeamId]:RemovePlayer(p_Player)

		if #m_TeamChannels[p_TeamId].players == 0 then
			m_TeamChannels[p_TeamId]:Close()
			m_TeamChannels[p_TeamId] = nil
		end
	end
end

---@param p_Player Player
---@param p_TeamId TeamId|integer
---@param p_SquadId SquadId|integer
local function _RemovePlayerFromSquadChannels(p_Player, p_TeamId, p_SquadId)
	if m_SquadChannels[p_TeamId] ~= nil and m_SquadChannels[p_TeamId][p_SquadId] ~= nil then
		m_SquadChannels[p_TeamId][p_SquadId]:RemovePlayer(p_Player)

		if #m_SquadChannels[p_TeamId][p_SquadId].players == 0 then
			m_SquadChannels[p_TeamId][p_SquadId]:Close()
			m_SquadChannels[p_TeamId][p_SquadId] = nil
		end
	end
end

---@param p_Player Player
local function _RemovePlayerFromChannels(p_Player)
	_RemovePlayerFromTeamChannels(p_Player, p_Player.teamId)
	_RemovePlayerFromSquadChannels(p_Player, p_Player.teamId, p_Player.squadId)
end

---@param p_Player Player
---@param p_TeamId TeamId|integer
local function _AddPlayerToTeamChannel(p_Player, p_TeamId)
	if m_TeamChannels[p_TeamId] == nil then
		m_TeamChannels[p_TeamId] = Voip:CreateChannel("Team" .. tostring(p_TeamId), VoipEmitterType.Local)
	end

	m_TeamChannels[p_TeamId]:AddPlayer(p_Player)
	m_PlayerLastTeam[p_Player.name] = p_TeamId
end

---@param p_Player Player
---@param p_TeamId TeamId|integer
---@param p_SquadId SquadId|integer
local function _AddPlayerToSquadChannel(p_Player, p_TeamId, p_SquadId)
	if p_SquadId ~= SquadId.SquadNone then
		if m_SquadChannels[p_TeamId] == nil then
			m_SquadChannels[p_TeamId] = {}
		end

		if m_SquadChannels[p_TeamId][p_SquadId] == nil then
			m_SquadChannels[p_TeamId][p_SquadId] = Voip:CreateChannel('Team' .. p_TeamId .. '_Squad' .. p_SquadId, VoipEmitterType.Local)
		end

		m_SquadChannels[p_TeamId][p_SquadId]:AddPlayer(p_Player)
	end
end

---@param p_Player Player
---@param p_TeamId TeamId|integer
---@param p_SquadId SquadId|integer
local function _UpdatePlayerChannels(p_Player, p_TeamId, p_SquadId)
	if p_TeamId == TeamId.TeamNeutral then
		return
	end

	-- add the player back to the relevant channels
	if m_PlayerSettings[p_Player.name] == PlayerVoipLevel.Squad then
		_AddPlayerToSquadChannel(p_Player, p_TeamId, p_SquadId)
	elseif m_PlayerSettings[p_Player.name] == PlayerVoipLevel.Team then
		_AddPlayerToTeamChannel(p_Player, p_TeamId)
		_AddPlayerToSquadChannel(p_Player, p_TeamId, p_SquadId)
	end
end

---@param p_Player Player
---@param p_VoipLevel PlayerVoipLevel|integer
NetEvents:Subscribe('Player:VoipLevel', function(p_Player, p_VoipLevel)
	if m_PlayerSettings[p_Player.name] == p_VoipLevel then
		return
	end

	-- switching from PlayerVoipLevel.Team -> Squad|Disabled
	if m_PlayerSettings[p_Player.name] == PlayerVoipLevel.Team then
		_RemovePlayerFromTeamChannels(p_Player, p_Player.teamId)
	end

	if p_VoipLevel == PlayerVoipLevel.Disabled then
		_RemovePlayerFromSquadChannels(p_Player, p_Player.teamId, p_Player.squadId)
	end

	-- update voip level
	m_PlayerSettings[p_Player.name] = p_VoipLevel

	_UpdatePlayerChannels(p_Player, p_Player.teamId, p_Player.squadId)
end)

---@param p_Player Player
Events:Subscribe('Player:Left', function(p_Player)
	_RemovePlayerFromChannels(p_Player)
	m_PlayerSettings[p_Player.name] = nil
end)

---@param p_Player Player
---@param p_TeamId TeamId|integer
Events:Subscribe('Player:TeamChange', function(p_Player, p_TeamId)
	if m_PlayerLastTeam[p_Player.name] ~= nil then
		_RemovePlayerFromTeamChannels(p_Player, m_PlayerLastTeam[p_Player.name])
	end

	if m_PlayerSettings[p_Player.name] == PlayerVoipLevel.Team then
		_AddPlayerToTeamChannel(p_Player, p_TeamId)
	end
end)

---@param p_Player Player
---@param p_NewSquadId SquadId|integer
Events:Subscribe('Player:SetSquad', function(p_Player, p_NewSquadId)
	_RemovePlayerFromSquadChannels(p_Player, p_Player.teamId, p_Player.squadId)

	if m_PlayerSettings[p_Player.name] ~= PlayerVoipLevel.Disabled then
		_AddPlayerToSquadChannel(p_Player, p_Player.teamId, p_NewSquadId)
	end
end)

---@param p_Player Player
---@param p_MutedPlayerName string
---@param p_Mute boolean
NetEvents:Subscribe("VoipMod:MutedByPlayer", function(p_Player, p_MutedPlayerName, p_Mute)
	local s_MutedPlayer = PlayerManager:GetPlayerByName(p_MutedPlayerName)

	if s_MutedPlayer then
		NetEvents:SendTo("VoipMod:MutedByPlayer", s_MutedPlayer, p_Player.name, p_Mute)
	end
end)
