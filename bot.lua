-- Initialize global variables to store the latest game state and game host process.
LatestGameState = {}  -- Stores all game data
InAction = false     -- Prevents the bot from performing multiple actions simultaneously

-- Color codes for terminal output
colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

-- Check if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Calculate the distance between two points.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @return: The Euclidean distance between the points.
function calculateDistance(x1, y1, x2, y2)
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2)
end

-- Decide the next action based on player proximity, energy, health, and game map analysis.
-- Prioritize targets based on health (weaker first), distance (closer first), and strategic positions.
-- Analyze the map for chokepoints or advantageous positions.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange = false
  local bestTarget = nil  -- Stores the ID of the best target player (considering health, distance)
  
  -- Find closest and weakest target within attack range
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
      targetInRange = true
      if not bestTarget or state.health < bestTarget.health or 
        (state.health == bestTarget.health and calculateDistance(player.x, player.y, state.x, state.y) < calculateDistance(player.x, player.y, bestTarget.x, bestTarget.y)) then
        bestTarget = state
      end
    end
  end

  -- Attack logic if energy is sufficient and a target is in range
  if player.energy > 10 and targetInRange then
    print(colors.red .. "Player in range. Attacking." .. colors.reset)
    ao.send({
      Target = Game,
      Action = "PlayerAttack",
      Player = ao.id,
      AttackEnergy = tostring(math.floor(player.energy / 2)),
    })
  else
    -- Move towards the center of the arena or towards clusters of players
    local centerX, centerY = LatestGameState.MapWidth / 2, LatestGameState.MapHeight / 2
    local moveDirection = ""

    if calculateDistance(player.x, player.y, centerX, centerY) > 1 then
      if player.x < centerX then moveDirection = "Right"
      elseif player.x > centerX then moveDirection = "Left"
      elseif player.y < centerY then moveDirection = "Up"
      elseif player.y > centerY then moveDirection = "Down"
      end
    else
      -- If already near the center, move towards the nearest cluster of players
      local nearestPlayer = nil
      for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
          if not nearestPlayer or calculateDistance(player.x, player.y, state.x, state.y) < calculateDistance(player.x, player.y, nearestPlayer.x, nearestPlayer.y) then
            nearestPlayer = state
          end
        end
      end

      if nearestPlayer then
        if player.x < nearestPlayer.x then moveDirection = "Right"
        elseif player.x > nearestPlayer.x then moveDirection = "Left"
        elseif player.y < nearestPlayer.y then moveDirection = "Up"
        elseif player.y > nearestPlayer.y then moveDirection = "Down"
        end
      else
        -- If no other players are found, move randomly
        local directions = {"Up", "Down", "Left", "Right"}
        moveDirection = directions[math.random(#directions)]
      end
    end

    print(colors.blue .. "Moving " .. moveDirection .. "." .. colors.reset)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = moveDirection})
  end

  InAction = false -- Reset the "InAction" flag
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print 'LatestGameState' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({
          Target = Game,
          Action = "PlayerAttack",
          Player = ao.id,
          AttackEnergy = tostring(math.floor(playerEnergy / 2))
        })
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
