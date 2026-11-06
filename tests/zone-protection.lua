-- Appended to a disposable test ZIP by run.py, in the mod's own Lua context.
local function test_flags(entity)
  return {minable_flag=entity.minable_flag, destructible=entity.destructible, rotatable=entity.rotatable}
end

local function expect_flags(entity, expected, label)
  assert(entity.valid, label .. ": entity was destroyed")
  for key,value in pairs(expected) do
    assert(entity[key] == value, label .. ": incorrect " .. key)
  end
end

local blocked = {minable_flag=false, destructible=false, rotatable=false}

local function find_button(element, name)
  if element.name == name then return element end
  for _,child in pairs(element.children) do
    local found = find_button(child, name)
    if found then return found end
  end
end

local function click(player, action, id)
  gui(player)
  local button = find_button(player.gui.screen.zone_gui, action .. "_" .. id)
  assert(button, "Missing GUI button: " .. action .. "_" .. id)
  script.get_event_handler(defines.events.on_gui_click){
    name=defines.events.on_gui_click, player_index=player.index, element=button
  }
end

local function zone(player, x1, x2, y1, y2)
  player.clear_cursor()
  player.cursor_stack.set_stack{name="zone-selector", count=1}
  script.get_event_handler(defines.events.on_player_selected_area){
    name=defines.events.on_player_selected_area, player_index=player.index,
    item="zone-selector", area={left_top={x=x1,y=y1 or 3}, right_bottom={x=x2,y=y2 or 7}}
  }
  return "zone_" .. storage.zone_counter
end

local function entity(surface, name, x, y, extra)
  local definition = {name=name, position={x=x,y=y}, force="player"}
  for key,value in pairs(extra or {}) do definition[key] = value end
  local result = surface.create_entity(definition)
  assert(result, "Cannot create fixture: " .. name)
  return result
end

local function prepare_tests(player)
  local surface = game.create_surface("zone-protection-regression", {width=256, height=128})
  local tiles = {}
  for x=0,110 do for y=0,16 do
    tiles[#tiles+1] = {name="grass-1", position={x=x,y=y}}
  end end
  surface.set_tiles(tiles)
  player.teleport({2,2}, surface)

  local belt = entity(surface, "transport-belt", 10, 5)
  local custom = entity(surface, "transport-belt", 14, 5)
  custom.minable_flag=false; custom.destructible=false; custom.rotatable=false
  local fixtures = {belt, custom, entity(surface,"wooden-chest",18,5),
    entity(surface,"iron-ore",10,10,{amount=100}), entity(surface,"tree-01",18,10),
    entity(surface,"entity-ghost",14,10,{inner_name="wooden-chest"})}
  local originals = {}
  for index,e in ipairs(fixtures) do originals[index] = test_flags(e) end
  local first = zone(player,8,22,3,12)
  for _,e in ipairs(fixtures) do expect_flags(e,blocked,"zone creation") end
  -- Existing action handlers must not overwrite the original snapshot.
  script.get_event_handler(defines.events.on_gui_opened){
    name=defines.events.on_gui_opened, player_index=player.index, entity=belt
  }
  click(player,"protect",first)
  for index,e in ipairs(fixtures) do expect_flags(e,originals[index],"zone disabled") end
  custom.minable_flag=true; custom.destructible=true; custom.rotatable=true
  originals[2] = test_flags(custom)
  click(player,"protect",first)
  for _,e in ipairs(fixtures) do expect_flags(e,blocked,"zone enabled again") end
  click(player,"delete",first)
  for index,e in ipairs(fixtures) do expect_flags(e,originals[index],"active zone deleted") end
  assert(not storage.zones[first], "Deleted zone still exists")
  local inactive = zone(player,8,22,3,12)
  click(player,"protect",inactive)
  click(player,"delete",inactive)
  for index,e in ipairs(fixtures) do expect_flags(e,originals[index],"inactive zone deleted") end
  log("ZONE TEST PASS: toggle/delete, mixed entity types, original properties, repeated events")

  local left = entity(surface,"transport-belt",30,5)
  local middle = entity(surface,"transport-belt",35,5)
  local right = entity(surface,"transport-belt",40,5)
  local left_flags, middle_flags, right_flags = test_flags(left), test_flags(middle), test_flags(right)
  local a, b = zone(player,28,37), zone(player,33,42)
  click(player,"protect",a)
  expect_flags(left,left_flags,"A-only object released")
  expect_flags(middle,blocked,"overlap retained by B")
  expect_flags(right,blocked,"B-only object retained")
  click(player,"protect",a)
  click(player,"delete",b)
  expect_flags(right,right_flags,"B-only object released")
  expect_flags(middle,blocked,"overlap retained by A")
  click(player,"delete",a)
  expect_flags(left,left_flags,"A-only object restored")
  expect_flags(middle,middle_flags,"overlap original restored")
  log("ZONE TEST PASS: overlapping zones in both removal orders")

  local late_a, late_b = zone(player,50,59), zone(player,53,62)
  local late = entity(surface,"wooden-chest",55,5)
  local late_flags = test_flags(late)
  script.get_event_handler(defines.events.on_gui_opened){
    name=defines.events.on_gui_opened, player_index=player.index, entity=late
  }
  expect_flags(late,blocked,"late object protected")
  click(player,"delete",late_a)
  expect_flags(late,blocked,"late object keeps second zone")
  click(player,"protect",late_b)
  expect_flags(late,late_flags,"late object original restored")
  click(player,"delete",late_b)

  local car = entity(surface,"car",75,5)
  local car_flags = test_flags(car)
  local moving = zone(player,73,80)
  assert(car.teleport({85,5}),"Cannot move protected fixture")
  click(player,"delete",moving)
  expect_flags(car,car_flags,"object moved outside zone restored")
  local doomed = entity(surface,"transport-belt",90,5)
  local doomed_zone = zone(player,88,93)
  doomed.destroy()
  click(player,"delete",doomed_zone)
  log("ZONE TEST PASS: late objects, moved objects, destroyed objects")

  log("ZONE TEST PASS: initial regression run completed")
  script.finish_test(true)
end

local function reload_tests(player)
  local state = assert(storage.zone_regression,"Regression save state missing")
  expect_flags(state.entity,blocked,"protection survived save/load")
  click(player,"delete",state.a)
  expect_flags(state.entity,blocked,"overlap survived save/load")
  click(player,"protect",state.b)
  expect_flags(state.entity,state.original,"original properties survived save/load")
  click(player,"protect",state.b)
  click(player,"delete",state.b)
  expect_flags(state.entity,state.original,"delete after reload and re-enable")
  log("ZONE TEST PASS: save/load and restoration after reload")
  script.finish_test(true)
end

-- Native --create writes a real save after on_init. The test-mode runner does
-- not process normal autosave requests, so persistence uses this separate phase.
if not script.test_arg then
  script.on_init(function()
    initialize_storage()
    local surface = game.create_surface("zone-save-regression", {width=32,height=32})
    surface.set_tiles{{name="grass-1",position={0,0}}}
    local saved = entity(surface,"transport-belt",0,0)
    saved.destructible=false
    local original = test_flags(saved)
    for _,id in ipairs{"saved_a","saved_b"} do
      storage.zones[id] = {surface=surface.name, protected=true,
        area={left_top={x=-2,y=-2},right_bottom={x=2,y=2}}}
      protect(id)
    end
    storage.zone_regression = {entity=saved,original=original,a="saved_a",b="saved_b"}
    expect_flags(saved,blocked,"protection before save")
    log("ZONE TEST PASS: persistence fixture created")
  end)
end

script.on_event(defines.events.on_tick,function()
  local player = assert(game.get_player(1),"Headless test player missing")
  if script.test_arg == "prepare" then
    prepare_tests(player)
  elseif script.test_arg == "reload" then
    reload_tests(player)
  else
    error("Expected test argument prepare or reload")
  end
end)
