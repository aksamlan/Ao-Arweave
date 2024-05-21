-- Yeni renkler eklendi
local terminalColors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  darkGray = "\27[90m"
}

-- Koordinatlar arasındaki mesafeyi kontrol eder
local function isWithinRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Sonraki hareketi belirler
local function determineNextMove()
  local player = gameState.Players[ao.id]
  local targetInRange = false
  local bestTarget = nil
  
  -- Hedefe doğru ilerleme kararı al
  for target, state in pairs(gameState.Players) do
    if target ~= ao.id and isWithinRange(player.x, player.y, state.x, state.y, 1) then
      targetInRange = true
      if not bestTarget or state.health < bestTarget.health or 
        (state.health == bestTarget.health and isWithinRange(player.x, player.y, state.x, state.y, 1) < isWithinRange(player.x, player.y, bestTarget.x, bestTarget.y, 1)) then
        bestTarget = state
      end
    end
  end

  if player.energy > 5 and targetInRange then
    print(terminalColors.red .. "Attack is imminent. Preparing to strike." .. terminalColors.reset)
    ao.send({
      Target = Game,
      Action = "PlayerAttack",
      Player = ao.id,
      AttackEnergy = tostring(player.energy),
    })
  else
    print(terminalColors.red .. "No immediate threat detected. Proceeding cautiously." .. terminalColors.reset)
    local directions = {"Up", "Down", "Left", "Right"}
    local randomDirection = directions[math.random(#directions)]
    ao.send({
      Target = Game,
      Action = "PlayerMove",
      Player = ao.id,
      Direction = randomDirection
    })
  end
end

-- Oyun durumunu günceller
local function updateGameState(msg)
    local json = require("json")
    gameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "GameStateUpdated"})
    print("Game state has been updated. Type 'gameState' to view the details.")
end

-- Yeni bir saldırı yapıldığında tetiklenir
local function initiateCounterAttack()
    if not inAction then
      inAction = true
      local playerEnergy = gameState.Players[ao.id].energy
      if playerEnergy == undefined then
        print(terminalColors.red .. "Unable to determine energy levels." .. terminalColors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Energy level detection failed."})
      elseif playerEnergy == 0 then
        print(terminalColors.red .. "Insufficient energy to retaliate." .. terminalColors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Energy depletion."})
      else
        print(terminalColors.red .. "Launching counterattack." .. terminalColors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      inAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Awaiting completion of previous action. Hold on...")
    end
end

-- Oyun durumu güncellendiğinde sonraki adımı belirler
Handlers.add(
  "DetermineNextMove",
  Handlers.utils.hasMatchingTag("Action", "GameStateUpdated"),
  function ()
    if gameState.GameMode ~= "Playing" then
      inAction = false
      return
    end
    print("Planning next move.")
    determineNextMove()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Saldırıya uğrandığında karşılık verir
Handlers.add(
  "CounterAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function ()
    initiateCounterAttack()
  end
)
