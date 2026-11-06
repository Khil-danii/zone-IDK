-- Runs native player/blueprint builds and real robot construction in a test ZIP.
local build_handler = script.get_event_handler(defines.events.on_built_entity)
local robot_handler = script.get_event_handler(defines.events.on_robot_built_entity)
script.on_event(defines.events.on_built_entity,function(ev)
  storage.refund_tests.manual_events = storage.refund_tests.manual_events + 1
  build_handler(ev)
end)
script.on_event(defines.events.on_robot_built_entity,function(ev)
  local state = storage.refund_tests
  if state.phase == "native" and ev.robot.surface == state.surface then
    local built = ev.entity
    local cargo = ev.robot.get_inventory(defines.inventory.robot_cargo)
    local item = {name=ev.stack.name,quality=ev.stack.quality.name}
    local before, spent = cargo.get_item_count(item), ev.stack.count
    robot_handler(ev)
    assert(not built.valid,"Robot building was not blocked")
    assert(cargo.get_item_count(item) == before + spent,"Robot refund lost quality or count")
    state.robot_events = state.robot_events + 1
  else
    robot_handler(ev)
  end
end)

local function ground_count(surface, name, quality)
  local count = 0
  for _,item in pairs(surface.find_entities_filtered{type="item-entity"}) do
    if item.stack.valid_for_read and item.stack.name == name and item.stack.quality.name == quality then
      count = count + item.stack.count
    end
  end
  return count
end

local function player_count(player, name, quality)
  local count = player.get_main_inventory().get_item_count{name=name,quality=quality}
  local cursor = player.cursor_stack
  if cursor.valid_for_read and cursor.name == name and cursor.quality.name == quality then
    count = count + cursor.count
  end
  return count
end

local function flat_surface(name)
  local surface = game.create_surface(name,{width=256,height=64})
  surface.request_to_generate_chunks({16,0},2)
  surface.force_generate_chunk_requests()
  for _,existing in pairs(surface.find_entities()) do existing.destroy() end
  local tiles = {}
  for x=-12,48 do for y=-8,8 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
  surface.set_tiles(tiles)
  game.forces.player.chart(surface,{{-12,-8},{48,8}})
  return surface
end

local function zone(player, x1, x2)
  player.clear_cursor()
  player.cursor_stack.set_stack{name="zone-selector",count=1}
  script.get_event_handler(defines.events.on_player_selected_area){
    player_index=player.index,area={left_top={x=x1,y=-6},right_bottom={x=x2,y=6}}}
end

local function fill_inventory(inventory)
  inventory.clear()
  for i=1,#inventory do inventory[i].set_stack{name="iron-plate",count=100} end
end

local function initial_tests(player)
  storage.refund_tests={manual_events=0,robot_events=0,start=game.tick}
  local surface = flat_surface("refund-player-regression")
  player.teleport({7,0},surface)
  local inventory = player.get_main_inventory()
  player.force.technologies["construction-robotics"].researched=true
  zone(player,8,30)
  player.cursor_stack.set_stack{name="blueprint",count=1}
  player.cursor_stack.set_blueprint_entities{
    {entity_number=1,name="assembling-machine-1",position={0,0}},
    {entity_number=2,name="wooden-chest",position={4,0}}
  }
  local before = storage.refund_tests.manual_events
  local blueprint_results = player.cursor_stack.build_blueprint{surface=surface,force=player.force,by_player=player,position={14,0}}
  assert(storage.refund_tests.manual_events >= before+2,"Blueprint events=" .. storage.refund_tests.manual_events .. ", result count=" .. #blueprint_results)
  assert(#surface.find_entities_filtered{type="entity-ghost"} == 0,"Blueprint ghosts were not rejected")
  assert(player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint_setup(),"Blueprint was lost")
  assert(player_count(player,"assembling-machine-1","normal") == 0,"Ghost created an unpaid refund")
  log("ZONE TEST PASS: native blueprint placement, no entity-ghost crash or free items")

  player.clear_cursor(); inventory.clear()
  player.teleport({14,4},surface)
  player.cursor_stack.set_stack{name="assembling-machine-1",count=2,quality="rare"}
  before = storage.refund_tests.manual_events
  player.build_from_cursor{position={14,0}}
  assert(storage.refund_tests.manual_events == before+1,"Manual build event missing")
  assert(#surface.find_entities_filtered{name="assembling-machine-1"} == 0,"Manual building was not blocked")
  assert(player_count(player,"assembling-machine-1","rare") == 2,"Manual refund lost count or quality")
  assert(player_count(player,"assembling-machine-1","normal") == 0,"Manual refund downgraded quality")
  log("ZONE TEST PASS: native manual construction preserves rare item quality and count")

  player.cursor_stack.clear()
  fill_inventory(inventory)
  player.teleport({20,4},surface)
  player.cursor_stack.set_stack{name="assembling-machine-1",count=2,quality="rare"}
  before = storage.refund_tests.manual_events
  player.build_from_cursor{position={20,0}}
  assert(storage.refund_tests.manual_events == before+1,"Full-inventory native build event missing")
  assert(player_count(player,"assembling-machine-1","rare") + ground_count(surface,"assembling-machine-1","rare") == 2,
    "Full player inventory lost a refund")
  log("ZONE TEST PASS: full player inventory preserves the rare item refund")

  -- Standard event data with multiple consumed stacks exercises partial overflow.
  player.cursor_stack.clear()
  local ground_before = ground_count(surface,"assembling-machine-1","rare")
  local maximum = prototypes.item["assembling-machine-1"].stack_size
  inventory[1].set_stack{name="assembling-machine-1",count=maximum-1,quality="rare"}
  local consumed = game.create_inventory(2)
  consumed[1].set_stack{name="assembling-machine-1",count=3,quality="rare"}
  consumed[2].set_stack{name="wooden-chest",count=2,quality="uncommon"}
  local built = surface.create_entity{name="assembling-machine-1",position={24,0},force="player",quality="rare"}
  build_handler{entity=built,player_index=player.index,consumed_items=consumed}
  assert(not built.valid,"Controlled building event was not blocked")
  assert(inventory.get_item_count{name="assembling-machine-1",quality="rare"} == maximum,"Partial refund did not fill available space")
  assert(ground_count(surface,"assembling-machine-1","rare") == ground_before+2,"Partial refund overflow count is wrong")
  assert(ground_count(surface,"wooden-chest","uncommon") == 2,"Second consumed stack was lost")
  assert(consumed[1].count == 3 and consumed[2].count == 2,"Refund modified the event's item data")
  consumed.destroy()

  local robot = surface.create_entity{name="construction-robot",position={4,0},force="player"}
  local cargo = robot.get_inventory(defines.inventory.robot_cargo)
  cargo.insert{name="iron-plate",count=1}
  local used = game.create_inventory(1)
  used[1].set_stack{name="assembling-machine-1",count=1,quality="rare"}
  built = surface.create_entity{name="assembling-machine-1",position={28,0},force="player",quality="rare"}
  robot_handler{entity=built,robot=robot,stack=used[1]}
  assert(not built.valid,"Full-cargo construction was not blocked")
  assert(cargo.get_item_count("iron-plate") == 1,"Existing robot cargo was changed")
  assert(ground_count(surface,"assembling-machine-1","rare") == ground_before+3,"Full robot cargo lost its refund")
  robot.destroy(); used.destroy(); inventory.clear()
  log("ZONE TEST PASS: multiple consumed stacks, partial overflow and full robot cargo")

  local outside = surface.create_entity{name="wooden-chest",position={40,0},force="player"}
  local outside_items = game.create_inventory(1)
  outside_items[1].set_stack{name="wooden-chest",count=1}
  build_handler{entity=outside,player_index=player.index,consumed_items=outside_items}
  assert(outside.valid,"Building outside a protected zone was blocked")
  assert(inventory.get_item_count("wooden-chest") == 0,"Allowed building incorrectly generated a refund")
  outside_items.destroy()

  surface=flat_surface("refund-robot-regression")
  player.teleport({-8,0},surface)
  local force=game.forces.player
  force.technologies["construction-robotics"].researched=true
  force.worker_robots_speed_modifier=4
  force.worker_robots_storage_bonus=3
  local port=surface.create_entity{name="roboport",position={0,0},force=force}
  port.energy=100000000
  port.get_inventory(defines.inventory.roboport_robot).insert{name="construction-robot",count=1}
  local provider=surface.create_entity{name="passive-provider-chest",position={4,0},force=force}
  local storage_chest=surface.create_entity{name="storage-chest",position={6,0},force=force}
  provider.insert{name="assembling-machine-1",count=3,quality="rare"}
  for _,x in ipairs{14,18} do
    surface.create_entity{name="entity-ghost",inner_name="assembling-machine-1",position={x,0},force=force,quality="rare"}
  end
  local state=storage.refund_tests
  state.surface=surface; state.provider=provider; state.storage_chest=storage_chest; state.port=port
  state.phase="native"
end

script.on_event(defines.events.on_tick,function()
  local player=assert(game.get_player(1))
  if not storage.refund_tests then initial_tests(player) end
  local state=storage.refund_tests
  local robots=state.surface.find_entities_filtered{type="construction-robot"}
  if not state.protected then
    for _,robot in pairs(robots) do
      local cargo=robot.get_inventory(defines.inventory.robot_cargo)
      if cargo and not cargo.is_empty() then
        zone(player,11,21)
        state.protected=true
        break
      end
    end
  end
  local item={name="assembling-machine-1",quality="rare"}
  local total=state.provider.get_item_count(item)+state.storage_chest.get_item_count(item)
    +ground_count(state.surface,item.name,item.quality)
  for _,robot in pairs(robots) do
    total=total+robot.get_inventory(defines.inventory.robot_cargo).get_item_count(item)
  end
  assert(total == 3,"Real robot construction lost or duplicated a rare item")
  if state.robot_events >= 2 and #robots == 0 then
    assert(state.protected,"Robot zone was never activated in flight")
    assert(#state.surface.find_entities_filtered{name="assembling-machine-1"} == 0,"Protected construction survived")
    log("ZONE TEST PASS: real robots keep all 3 rare items after zone activation in flight")
    log("ZONE TEST PASS: building regression run completed")
    script.finish_test(true)
  end
  assert(game.tick-state.start<3000,"Robot refund regression timed out")
end)
