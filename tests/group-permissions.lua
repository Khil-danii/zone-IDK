-- Disposable engine-backed tests: production GUI, native permission groups,
-- real builds/mining, and save/load. Lua API calls are not network input: the
-- denied-input checks inspect the engine's effective input permission group.
local function find(element, predicate)
  if predicate(element) then return element end
  for _,child in pairs(element.children) do
    local result = find(child,predicate)
    if result then return result end
  end
end

local function click(player, button)
  assert(button,"Missing GUI button")
  script.get_event_handler(defines.events.on_gui_click){player_index=player.index,element=button}
end

local function action(player, name, id)
  gui(player)
  click(player,find(player.gui.screen.zone_gui,function(e) return e.name == name.."_"..id end))
end

local function group(name)
  local result = assert(game.permissions.create_group(name))
  for _,input in pairs(defines.input_action) do result.set_allows_action(input,true) end
  return result
end

local function create_zone(player, x1, x2)
  player.clear_cursor(); player.cursor_stack.set_stack{name="zone-selector",count=1}
  script.get_event_handler(defines.events.on_player_selected_area){player_index=player.index,
    area={left_top={x=x1,y=-5},right_bottom={x=x2,y=5}}}
  local id = "zone_"..storage.zone_counter
  action(player,"permissions",id)
  local editor = assert(player.gui.screen.zone_permissions_gui)
  assert(editor.zone_admin_bypass.state,"New zone did not default to admin bypass")
  -- The rest of this suite exercises explicit restrictions for the admin too.
  editor.zone_admin_bypass.state = false
  click(player,find(editor,function(e) return e.name == "zone_permissions_save" end))
  return id
end

local function edit(player, id, rules, options)
  action(player,"permissions",id)
  local frame = player.gui.screen.zone_permissions_gui
  assert(frame,"Permissions editor missing")
  for group_id,entries in pairs(rules or {}) do
    for key,value in pairs(entries) do
      local input = find(frame,function(e)
        return e.tags.permission_group == group_id and e.tags.permission_action == key
      end)
      assert(input,"Missing permission row")
      input.selected_index = value and 2 or 3
    end
  end
  for key,value in pairs(options or {}) do frame[key].state = value end
  click(player,find(frame,function(e) return e.name == "zone_permissions_save" end))
end

local function select(player, base, entity)
  player.selected = nil
  player.permission_group = base
  player.selected = entity
  permissions.refresh(player)
  assert(permissions.base_group(player).group_id == base.group_id,"Base group was lost")
end

local function allowed_input(player, name)
  return player.permission_group.allows_action(defines.input_action[name])
end

local function item_count(player, name)
  local count = player.get_main_inventory().get_item_count(name)
  if player.cursor_stack.valid_for_read and player.cursor_stack.name == name then
    count = count + player.cursor_stack.count
  end
  return count
end

local function flat_surface(name)
  local surface = game.create_surface(name,{width=128,height=64})
  surface.request_to_generate_chunks({16,0},2); surface.force_generate_chunk_requests()
  for _,e in pairs(surface.find_entities()) do e.destroy() end
  local tiles = {}
  for x=-10,64 do for y=-10,10 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
  surface.set_tiles(tiles)
  game.forces.player.chart(surface,{{-10,-10},{64,10}})
  return surface
end

local function spawn(surface, name, x)
  return assert(surface.create_entity{name=name,position={x,0},force="player"})
end

local function initial_tests(player)
  local surface = flat_surface("group-permissions-tests")
  player.teleport({5,4},surface)
  local builders,guests = group("Builders"),group("Guests")
  local limited = group("Restricted guest")
  limited.set_allows_action(defines.input_action.add_permission_group,false)
  limited.set_allows_action(defines.input_action.edit_permission_group,false)
  local belt,chest = spawn(surface,"transport-belt",10.5),spawn(surface,"wooden-chest",14.5)
  local custom = spawn(surface,"transport-belt",18.5)
  custom.minable_flag=false; custom.rotatable=false; custom.destructible=false
  local id = create_zone(player,8,25)
  assert(not belt.minable_flag and not belt.destructible,"Default zone opened existing objects")
  edit(player,id,{[builders.group_id]={build=true,mine=true,interact=true}})
  assert(belt.minable_flag and belt.rotatable and not belt.destructible,"Allowed group cannot use original properties")
  assert(not custom.minable_flag and not custom.rotatable and not custom.destructible,"Original restrictions were lost")
  assert(storage.zones[id].permissions[builders.group_id].build,"GUI did not save rules")
  log("ZONE TEST PASS: native group GUI, safe defaults, original flags and separate invulnerability")

  select(player,guests,belt)
  local initial_admin = player.admin
  player.admin = false
  -- A non-admin unable to create groups still needs a safe derived group.
  select(player,limited,chest)
  assert(not allowed_input(player,"begin_mining"),"Non-admin derived-group creation failed")
  select(player,guests,belt)
  guests.set_allows_action(defines.input_action.add_permission_group,false)
  guests.set_allows_action(defines.input_action.edit_permission_group,false)
  permissions.refresh(player)
  assert(not allowed_input(player,"begin_mining"),"Guest can start mining")
  assert(not allowed_input(player,"fast_entity_transfer"),"Guest can quick-transfer")
  assert(not allowed_input(player,"paste_entity_settings"),"Guest can paste settings")
  assert(not allowed_input(player,"rotate_entity"),"Guest can rotate")
  assert(guests.allows_action(defines.input_action.begin_mining),"Canonical group was modified")
  assert(allowed_input(player,"start_walking"),"Unrelated permission was removed")
  player.mining_state = {mining=true,position=belt.position}
  permissions.refresh(player)
  assert(not player.mining_state.mining,"Mining already in progress was not stopped")
  player.opened = chest
  script.get_event_handler(defines.events.on_gui_opened){player_index=player.index,entity=chest}
  assert(player.opened == nil,"Guest can open protected chest")
  player.admin = initial_admin
  log("ZONE TEST PASS: denied target inputs, running mining stopped, chest GUI refused, base group unchanged")

  select(player,builders,belt)
  assert(player.permission_group == builders and allowed_input(player,"begin_mining"),"Builder rights not restored")
  player.opened = chest
  script.get_event_handler(defines.events.on_gui_opened){player_index=player.index,entity=chest}
  assert(player.opened == chest,"Builder cannot open permitted chest")
  player.opened = nil
  assert(player.mine_entity(belt),"Builder cannot actually mine the entity")
  assert(not belt.valid,"Allowed mining left entity behind")
  player.selected = nil
  player.teleport({14,4},surface)
  player.clear_cursor(); player.cursor_stack.set_stack{name="wooden-chest",count=2}
  player.build_from_cursor{position={14.5,2.5}}
  assert(surface.find_entity("wooden-chest",{14.5,2.5}),"Allowed native construction was rejected")
  local before_count = item_count(player,"wooden-chest")
  player.permission_group = guests
  player.build_from_cursor{position={18.5,2.5}}
  assert(not surface.find_entity("wooden-chest",{18.5,2.5}),"Guest construction succeeded")
  assert(item_count(player,"wooden-chest") == before_count,"Guest construction lost its refund")
  player.teleport({24,4},surface)
  player.cursor_stack.set_stack{name="wooden-chest",count=1}
  player.build_from_cursor{position={28.5,2.5}}
  assert(surface.find_entity("wooden-chest",{28.5,2.5}),"Outside target was blocked by player's position")
  log("ZONE TEST PASS: native permitted mining/building, forbidden build refund, coordinates of target")

  -- A zone permission never elevates a globally prohibited input.
  builders.set_allows_action(defines.input_action.build,false)
  select(player,builders,chest)
  assert(not permissions.can_act(player,chest.position,surface.name,"build","build"),"Zone overrode global build denial")
  assert(not allowed_input(player,"build"),"Derived group elevated global build denial")
  builders.set_allows_action(defines.input_action.build,true)
  select(player,guests,chest)
  guests.set_allows_action(defines.input_action.start_walking,false)
  assert(not allowed_input(player,"start_walking"),"Global edit did not reach derived group immediately")
  guests.set_allows_action(defines.input_action.start_walking,true)
  builders.add_player(player)
  permissions.refresh(player)
  assert(permissions.base_group(player) == builders,"External group assignment was ignored")
  builders.name = "Renamed Builders"
  assert(permissions.can_act(player,chest.position,surface.name,"mine","begin_mining"),"Rename lost zone settings")
  local newcomer = group("New group")
  assert(permissions.zone_denial({permission_group=newcomer,admin=false},chest.position,surface.name,"mine"),"New group bypassed default denial")
  log("ZONE TEST PASS: global prohibitions and edits, reassignment, rename, new groups")

  local overlap = create_zone(player,12,22)
  edit(player,overlap,{[builders.group_id]={build=true,mine=false,interact=true}})
  select(player,builders,chest)
  assert(not allowed_input(player,"begin_mining"),"Overlap did not honor denial")
  assert(permissions.zone_denial(player,chest.position,surface.name,"mine") == overlap,"Wrong overlapping policy")
  action(player,"protect",overlap)
  assert(allowed_input(player,"begin_mining"),"Disabling overlapping zone did not refresh selected target")
  assert(chest.minable_flag and not chest.destructible,"Remaining zone protection was lost")
  action(player,"delete",overlap)

  select(player,builders,chest)
  chest.order_deconstruction(player.force,player)
  assert(not chest.to_be_deconstructed(),"Robot-disabled zone accepted a demolition order")
  edit(player,id,{}, {zone_robot_mine=true})
  chest.order_deconstruction(player.force,player)
  assert(chest.to_be_deconstructed(),"Permitted robot demolition order was refused")
  chest.cancel_deconstruction(player.force)
  select(player,guests,chest)
  chest.order_deconstruction(player.force,player)
  assert(not chest.to_be_deconstructed(),"Guest ordered robots to bypass group denial")
  edit(player,id,{}, {zone_robot_mine=false})
  log("ZONE TEST PASS: overlap denial wins, live refresh, independent robot demolition policy")

  local ghost = surface.create_entity{name="entity-ghost",inner_name="assembling-machine-1",position={22,0},force=player.force}
  ghost.set_recipe("iron-gear-wheel")
  protect_at_position(ghost)
  select(player,guests,ghost)
  local ghost_position = ghost.position
  ghost.order_deconstruction(player.force,player)
  assert(not ghost.valid,"Native ghost removal was not exercised")
  local preserved = surface.find_entity("entity-ghost",ghost_position)
  assert(preserved and preserved.get_recipe().name == "iron-gear-wheel","Denied ghost removal lost the ghost or settings")
  select(player,builders,preserved)
  preserved.order_deconstruction(player.force,player)
  assert(not surface.find_entity("entity-ghost",ghost_position),"Allowed ghost removal was refused")
  log("ZONE TEST PASS: native ghost demolition honors groups and preserves blueprint recipe")

  -- A GUI left open by an admin is not an authorization token.
  action(player,"permissions",id)
  local editor = player.gui.screen.zone_permissions_gui
  editor.zone_admin_bypass.state = true
  player.admin = false
  click(player,find(editor,function(e) return e.name == "zone_permissions_save" end))
  assert(not storage.zones[id].admin_bypass,"Demoted player changed zone settings")
  player.clear_cursor(); player.cursor_stack.set_stack{name="zone-selector",count=1}
  local count = storage.zone_counter
  script.get_event_handler(defines.events.on_player_selected_area){player_index=player.index,
    area={left_top={x=30,y=-5},right_bottom={x=35,y=5}}}
  assert(storage.zone_counter == count,"Non-admin created a zone with an old tool")
  player.admin = true
  storage.zones[id].revision = storage.zones[id].revision + 1
  click(player,find(editor,function(e) return e.name == "zone_permissions_save" end))
  assert(not storage.zones[id].admin_bypass,"Stale editor overwrote newer zone settings")
  log("ZONE TEST PASS: admin authorization rechecked, stale concurrent editor rejected")

  edit(player,id,{}, {zone_admin_bypass=true,zone_invulnerable=false})
  select(player,guests,chest)
  assert(allowed_input(player,"begin_mining"),"Explicit admin bypass did not work")
  assert(chest.destructible,"Invulnerability switch did not restore original destructibility")
  edit(player,id,{}, {zone_admin_bypass=false,zone_invulnerable=true})
  assert(not allowed_input(player,"begin_mining"),"Removing admin bypass did not restore denial")

  -- Deleting the last allowed group must restore the entity-wide lock too.
  select(player,builders,chest)
  local deleted_id = builders.group_id
  builders.destroy()
  assert(not storage.zones[id].permissions[deleted_id],"Deleted group retained its zone rules")
  assert(not chest.minable_flag,"Deleting allowed group left entity-wide mining unlocked")
  permissions.refresh(player)
  assert(permissions.base_group(player) == game.permissions.get_group(0),"Deleted base group did not fall back")
  action(player,"delete",id)
  assert(chest.minable_flag and chest.destructible,"Deleting zone failed to restore entity")
  assert(not next(storage.permission_overlays),"Last zone left derived groups behind")
  assert(player.permission_group == game.permissions.get_group(0),"Original group was not restored")
  log("ZONE TEST PASS: group deletion, original group restoration and derived-group cleanup")
  log("ZONE TEST PASS: group regression run completed")
  script.finish_test(true)
end

if not script.test_arg then
  script.on_init(function()
    initialize_storage()
    local surface = flat_surface("group-save-tests")
    local saved = spawn(surface,"transport-belt",10.5)
    local base = group("Saved group")
    storage.zones.saved_groups = {surface=surface.name,protected=true,
      area={left_top={x=8,y=-4},right_bottom={x=20,y=4}}}
    permissions.initialize()
    storage.zones.saved_groups.permissions[base.group_id] = {mine=true,interact=false,build=true}
    protect("saved_groups")
    local actor = {valid=true,permission_group=base,selected=saved,admin=false,
      controller_type=defines.controllers.spectator}
    permissions.refresh(actor)
    assert(actor.permission_group ~= base,"Persistence fixture did not create derived group")
    storage.group_test_save={entity=saved,base_id=base.group_id,overlay_id=actor.permission_group.group_id}
    log("ZONE TEST PASS: group persistence fixture created")
  end)
end

script.on_event(defines.events.on_tick,function()
  local player = assert(game.get_player(1))
  if script.test_arg == "groups" then initial_tests(player)
  elseif script.test_arg == "reload-groups" then
    local state = assert(storage.group_test_save)
    player.set_controller{type=defines.controllers.god}
    player.teleport({10,4},state.entity.surface)
    player.permission_group = assert(game.permissions.get_group(state.overlay_id))
    player.selected = state.entity
    permissions.refresh(player)
    assert(permissions.base_group(player).group_id == state.base_id,"Base group lost after reload")
    assert(allowed_input(player,"begin_mining") and not allowed_input(player,"fast_entity_transfer"),"Saved group rules lost")
    assert(state.entity.minable_flag and not state.entity.destructible,"Entity policy lost after reload")
    action(player,"delete","saved_groups")
    assert(player.permission_group.group_id == state.base_id,"Base group not restored after deleting saved zone")
    assert(state.entity.destructible and state.entity.minable_flag,"Original entity flags not restored")
    log("ZONE TEST PASS: group restoration after reload")
    script.finish_test(true)
  elseif script.test_arg == "migrate-groups" then
    local entity = assert(storage.legacy_test_entity)
    assert(storage.permission_overlays and storage.zones.zone_1.default_permissions,"Same-version legacy migration did not run")
    assert(not storage.zones.zone_1.default_permissions.build,"Legacy migration opened zone")
    assert(not storage.zones.zone_1.admin_bypass,"Legacy migration changed existing admin bypass")
    assert(not entity.minable_flag and not entity.destructible,"Legacy protection was lost")
    action(player,"delete","zone_1")
    assert(entity.minable_flag and entity.destructible and entity.rotatable,"Legacy snapshot was not restored")
    log("ZONE TEST PASS: same-version legacy migration")
    script.finish_test(true)
  else error("Unexpected test phase") end
end)
