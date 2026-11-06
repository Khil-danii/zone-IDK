local permissions = require("permissions")
local zone_gui = require("zone-gui")

local function initialize_storage()
  storage.zones = storage.zones or {}
  storage.zone_counter = storage.zone_counter or 0
  storage.protected_entities = storage.protected_entities or {}
  permissions.initialize()
end

script.on_init(initialize_storage)

local function in_zone(x,y,z)
  return x>=z.area.left_top.x and x<=z.area.right_bottom.x
     and y>=z.area.left_top.y and y<=z.area.right_bottom.y
end

local function cancel_orders(entity, upgrade)
  if upgrade and not entity.to_be_upgraded() then return end
  if not upgrade and not entity.to_be_deconstructed() then return end
  for _,force in pairs(game.forces) do
    if entity.force == force or entity.force.name == "neutral" then
      if upgrade then entity.cancel_upgrade(force) else entity.cancel_deconstruction(force) end
    end
  end
end

local function refresh_entity(state)
  local entity = state.entity
  if not entity.valid then return end
  local mine,rotate,damage = state.minable_flag,state.rotatable,state.destructible
  for id in pairs(state.zones) do
    local z = storage.zones[id]
    if z and z.protected then
      if not permissions.any_allowed(z,"mine") then mine = false end
      if not permissions.any_allowed(z,"interact") then rotate = false end
      if z.invulnerable ~= false then damage = false end
    end
  end
  entity.minable_flag = mine
  entity.rotatable = rotate
  entity.destructible = damage
  if not permissions.can_act(nil,entity.position,entity.surface.name,"mine") then
    cancel_orders(entity,false)
  end
  if not permissions.can_act(nil,entity.position,entity.surface.name,"build")
      or not permissions.can_act(nil,entity.position,entity.surface.name,"mine") then
    cancel_orders(entity,true)
  end
end

local function protect_entity(id, z, entity)
  if not entity.valid then return end
  -- Registration numbers also identify entities without a unit_number, such as resources.
  local registration = script.register_on_object_destroyed(entity)
  local state = storage.protected_entities[registration]
  if not state then
    state = {
      entity = entity,
      minable_flag = entity.minable_flag,
      destructible = entity.destructible,
      rotatable = entity.rotatable,
      zones = {}
    }
    storage.protected_entities[registration] = state
  end
  state.zones[id] = true
  z.protected_entities = z.protected_entities or {}
  z.protected_entities[registration] = true
  refresh_entity(state)
end

local function protect(id)
  permissions.ensure()
  local z = storage.zones[id]
  local surface = game.surfaces[z.surface]
  if not surface then return end
  for _,entity in pairs(surface.find_entities_filtered{area=z.area}) do
    if in_zone(entity.position.x,entity.position.y,z) then protect_entity(id, z, entity) end
  end
end

local function protect_at_position(entity)
  permissions.ensure()
  for id,z in pairs(storage.zones) do
    if z.protected and z.surface == entity.surface.name
        and in_zone(entity.position.x, entity.position.y, z) then
      protect_entity(id, z, entity)
    end
  end
end

local function unprotect(id)
  permissions.ensure()
  local z = storage.zones[id]
  -- Older saves have no snapshots. Do not guess their objects' original properties.
  for registration in pairs(z.protected_entities or {}) do
    local state = storage.protected_entities[registration]
    if state then
      state.zones[id] = nil
      if not next(state.zones) then
        local entity = state.entity
        if entity.valid then
          entity.minable_flag = state.minable_flag
          entity.destructible = state.destructible
          entity.rotatable = state.rotatable
        end
        storage.protected_entities[registration] = nil
      else
        refresh_entity(state)
      end
    end
  end
  z.protected_entities = nil
end

script.on_event(defines.events.on_object_destroyed, function(ev)
  permissions.ensure()
  local state = storage.protected_entities[ev.registration_number]
  if not state then return end
  for id in pairs(state.zones) do
    local z = storage.zones[id]
    if z and z.protected_entities then
      z.protected_entities[ev.registration_number] = nil
    end
  end
  storage.protected_entities[ev.registration_number] = nil
end)

local function render(id, duration)
  local z=storage.zones[id]; if not z then return false end
  local s=game.surfaces[z.surface]; if not s then return false end
  duration = duration or 180
  rendering.draw_rectangle{
    color=z.protected and {r=1,g=0,b=0,a=0.4} or {r=0,g=1,b=0,a=0.4},
    width=3, left_top=z.area.left_top, right_bottom=z.area.right_bottom,
    surface=s, time_to_live=duration
  }
  rendering.draw_text{
    text=id..(z.protected and" [ЗАЩИЩЕНА]" or" [ОТКРЫТА]"),
    surface=s,
    target={x=(z.area.left_top.x+z.area.right_bottom.x)/2, y=z.area.left_top.y-1.5},
    color={r=1,g=1,b=1}, scale=1.2, time_to_live=duration
  }
  return true
end

script.on_event(defines.events.on_player_selected_area, function(ev)
  local p=game.get_player(ev.player_index)
  if not p or not p.admin or not p.cursor_stack.valid_for_read or p.cursor_stack.name~="zone-selector" then return end
  storage.zone_counter=storage.zone_counter+1
  local id="zone_"..storage.zone_counter
  storage.zones[id]={area=ev.area, surface=p.surface.name, created_by=p.name, protected=true, admin_bypass=true}
  permissions.initialize()
  protect(id); render(id)
  permissions.refresh_all()
  p.print("Зона создана и защищена: "..id,{r=0,g=1,b=0})
end)

local function refund_stack(stack, destination, surface, position)
  if not stack or not stack.valid_for_read then return end
  local remaining = stack.count
  if destination and destination.valid then
    remaining = remaining - destination.insert(stack)
  end
  if remaining > 0 then
    -- Copy the real stack so quality and item data survive a partial refund.
    -- Do not modify the event's stack, which other mods may also inspect.
    local overflow = game.create_inventory(1)
    overflow[1].set_stack(stack)
    overflow[1].count = remaining
    surface.spill_item_stack{
      position = position,
      stack = overflow[1],
      enable_looted = true,
      allow_belts = false,
      use_start_position_on_failure = true,
      drop_full_stack = true
    }
    overflow.destroy()
  end
end

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, function(ev)
  local ent = ev.created_entity or ev.entity
  if not ent or not ent.valid then return end
  local player = ev.player_index and game.get_player(ev.player_index)
  local allowed,id = permissions.can_act(player,ent.position,ent.surface.name,"build",player and "build")
  if not allowed then
    if player then player.print("Нельзя строить в зоне: "..id,{r=1,g=0,b=0}) end

    local surface, position = ent.surface, ent.position
    local ghost = ent.type == "entity-ghost" or ent.type == "tile-ghost"
    if not ent.destroy() then return end
    -- A blueprint ghost consumes no construction item and must not create a refund.
    if ghost then return end

    if ev.consumed_items and ev.consumed_items.valid then
      for index=1,#ev.consumed_items do
        refund_stack(ev.consumed_items[index], player, surface, position)
      end
    elseif ev.stack and ev.stack.valid_for_read then
      local robot = ev.robot
      local cargo = robot and robot.valid and robot.get_inventory(defines.inventory.robot_cargo)
      refund_stack(ev.stack, cargo, surface, position)
    end
    return
  end
  protect_at_position(ent)
  permissions.refresh_all()
end)

script.on_event(defines.events.on_gui_opened, function(ev)
  local player = game.get_player(ev.player_index)
  if not player then return end
  local entity = ev.entity
  if entity and entity.valid then
    protect_at_position(entity)
    local allowed,id = permissions.can_act(player,entity.position,entity.surface.name,"interact","open_gui")
    if not allowed then
      player.opened = nil
      player.print("Взаимодействие запрещено: "..id,{r=1,g=0,b=0})
    end
  end
  permissions.refresh(player)
end)

script.on_event({defines.events.on_selected_entity_changed,defines.events.on_gui_closed,
  defines.events.on_player_joined_game,defines.events.on_player_changed_surface,
  defines.events.on_player_changed_force,defines.events.on_player_demoted,defines.events.on_player_promoted},function(ev)
  local player = game.get_player(ev.player_index)
  if player and player.selected and player.selected.valid then protect_at_position(player.selected) end
  permissions.refresh(player)
end)

script.on_event(defines.events.on_player_rotated_entity,function(ev)
  local entity,player = ev.entity,game.get_player(ev.player_index)
  if not permissions.can_act(player,entity.position,entity.surface.name,"interact","rotate_entity") then
    entity.direction = ev.previous_direction
    entity.mirroring = ev.previous_mirroring
  end
  permissions.refresh(player)
end)

script.on_event(defines.events.on_marked_for_deconstruction,function(ev)
  local entity = ev.entity
  local player = ev.player_index and game.get_player(ev.player_index)
  if not permissions.can_act(player,entity.position,entity.surface.name,"mine",player and "deconstruct")
      or not permissions.can_act(nil,entity.position,entity.surface.name,"mine") then
    cancel_orders(entity,false)
  end
end)

script.on_event(defines.events.on_pre_ghost_deconstructed,function(ev)
  local ghost = ev.ghost
  if not ghost.valid or (ghost.type ~= "entity-ghost" and ghost.type ~= "tile-ghost") then return end
  local player = ev.player_index and game.get_player(ev.player_index)
  if permissions.can_act(player,ghost.position,ghost.surface.name,"mine",player and "deconstruct") then return end
  -- Ghost removal has no cancel flag. A native clone preserves its recipe,
  -- quality, tags and requests without inventing an item refund.
  local copy = ghost.clone{position=ghost.position,surface=ghost.surface,create_build_effect_smoke=false}
  if copy then
    local registration = script.register_on_object_destroyed(ghost)
    local original = storage.protected_entities[registration]
    if original then
      copy.minable_flag = original.minable_flag
      copy.destructible = original.destructible
      copy.rotatable = original.rotatable
    end
    protect_at_position(copy)
  end
end)

script.on_event(defines.events.on_marked_for_upgrade,function(ev)
  local entity = ev.entity
  local player = ev.player_index and game.get_player(ev.player_index)
  if not permissions.can_act(player,entity.position,entity.surface.name,"build",player and "upgrade")
      or not permissions.can_act(player,entity.position,entity.surface.name,"mine",player and "upgrade")
      or not permissions.can_act(nil,entity.position,entity.surface.name,"build")
      or not permissions.can_act(nil,entity.position,entity.surface.name,"mine") then
    cancel_orders(entity,true)
  end
end)

script.on_event(defines.events.on_permission_group_edited,permissions.on_group_edited)
script.on_event(defines.events.on_pre_permission_group_deleted,permissions.on_group_deleting)
script.on_event(defines.events.on_permission_group_deleted,function()
  for _,state in pairs(storage.protected_entities) do refresh_entity(state) end
  permissions.synchronize_all()
end)
-- This also catches another mod assigning a group and moving an already
-- selected/opened entity without a corresponding player input event.
script.on_nth_tick(1,permissions.refresh_all)

script.on_configuration_changed(function()
  initialize_storage()
  for _,state in pairs(storage.protected_entities) do refresh_entity(state) end
  permissions.synchronize_all()
end)

commands.add_command("show-zone","Показать зоны",function(ev)
  local p=game.get_player(ev.player_index)
  if not p then return end
  if not p.admin then p.print("Эта команда доступна только администраторам.",{r=1,g=0,b=0}) return end
  for id in pairs(storage.zones or {}) do render(id) end
  p.print("Все зоны показаны",{r=0,g=1,b=0})
end)

commands.add_command("zone-tool","Получить инструмент",function(ev)
  local p=game.get_player(ev.player_index)
  if not p then return end
  if not p.admin then p.print("Эта команда доступна только администраторам.",{r=1,g=0,b=0}) return end
  if p then p.clear_cursor(); p.cursor_stack.set_stack{name="zone-selector",count=1}; p.print("Инструмент",{r=0,g=1,b=0}) end
end)

commands.add_command("list-zones","Список зон",function(ev)
  local p=game.get_player(ev.player_index)
  if not p then return end
  p.print("=== Зоны ===")
  for id,z in pairs(storage.zones or {}) do
    p.print(id..": ["..(z.protected and"ЗАЩИЩЕНА"or" ОТКРЫТА").."] by "..(z.created_by or "unknown"))
  end
end)

local function gui(p)
  permissions.ensure()
  zone_gui.list(p,storage.zones)
end

commands.add_command("zone-gui","Открыть GUI",function(ev)
  local p=game.get_player(ev.player_index)
  if not p then return end
  if not p.admin then p.print("Эта команда доступна только администраторам.",{r=1,g=0,b=0}) return end
  gui(p)
end)

script.on_event(defines.events.on_gui_click, function(ev)
  permissions.ensure()
  local p=game.get_player(ev.player_index)
  if not p or not ev.element or not ev.element.valid or not zone_gui.owns(ev.element) then return end
  local action,id = ev.element.tags.zone_action,ev.element.tags.zone_id
  if action == "close" then
    if p.gui.screen.zone_gui then p.gui.screen.zone_gui.destroy() end
    return
  end
  if action == "close_permissions" then zone_gui.close_editor(p); return end
  if not p.admin then
    p.print("Управление зонами доступно только администраторам.",{r=1,g=0,b=0})
    return
  end
  local z = id and storage.zones[id]
  if action == "save" then
    local edited_id,revision,settings = zone_gui.read(p)
    local edited = edited_id and storage.zones[edited_id]
    if not edited then zone_gui.close_editor(p); return end
    if revision ~= edited.revision then
      p.print("Зону уже изменили. Проверьте обновлённые настройки и сохраните снова.",{r=1,g=0.5,b=0})
      zone_gui.editor(p,edited_id,edited,permissions.groups())
      return
    end
    for key,value in pairs(settings) do edited[key] = value end
    edited.revision = edited.revision + 1
    if edited.protected then protect(edited_id) end
    for registration in pairs(edited.protected_entities or {}) do
      local state = storage.protected_entities[registration]
      if state then refresh_entity(state) end
    end
    permissions.refresh_all()
    zone_gui.close_editor(p)
    gui(p)
    p.print("Права зоны сохранены: "..edited_id,{r=0,g=1,b=0})
    return
  end
  if not z then return end
  if action == "permissions" then zone_gui.editor(p,id,z,permissions.groups()); return end
  if action == "show" then render(id,11 * 60); return end
  if action == "protect" then
    if z then
      z.protected = not z.protected
      z.revision = (z.revision or 0) + 1
      if z.protected then protect(id) else unprotect(id) end
      permissions.refresh_all()
      gui(p)
    end
    return
  end
  if action == "delete" then
    if z then
      z.protected = false
      unprotect(id)
      storage.zones[id] = nil
      permissions.refresh_all()
      gui(p)
    end
    return
  end
end)
