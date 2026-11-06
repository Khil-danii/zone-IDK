local function initialize_storage()
  storage.zones = storage.zones or {}
  storage.zone_counter = storage.zone_counter or 0
  storage.protected_entities = storage.protected_entities or {}
end

script.on_init(initialize_storage)
script.on_configuration_changed(initialize_storage)

script.on_load(function() end)

local function in_zone(x,y,z)
  return x>=z.area.left_top.x and x<=z.area.right_bottom.x
     and y>=z.area.left_top.y and y<=z.area.right_bottom.y
end

local function is_prot(pos,surf)
  for id,z in pairs(storage.zones or {}) do
    if z.surface==surf and z.protected and in_zone(pos.x,pos.y,z) then return true,id end
  end
  return false,nil
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
  entity.minable_flag = false
  entity.destructible = false
  entity.rotatable = false
end

local function protect(id)
  local z = storage.zones[id]
  local surface = game.surfaces[z.surface]
  if not surface then return end
  for _,entity in pairs(surface.find_entities_filtered{area=z.area}) do
    protect_entity(id, z, entity)
  end
end

local function protect_at_position(entity)
  for id,z in pairs(storage.zones) do
    if z.protected and z.surface == entity.surface.name
        and in_zone(entity.position.x, entity.position.y, z) then
      protect_entity(id, z, entity)
    end
  end
end

local function unprotect(id)
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
      end
    end
  end
  z.protected_entities = nil
end

script.on_event(defines.events.on_object_destroyed, function(ev)
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

local function render(id)
  local z=storage.zones[id]; if not z then return false end
  local s=game.surfaces[z.surface]; if not s then return false end
  rendering.draw_rectangle{
    color=z.protected and {r=1,g=0,b=0,a=0.4} or {r=0,g=1,b=0,a=0.4},
    width=3, left_top=z.area.left_top, right_bottom=z.area.right_bottom,
    surface=s, time_to_live=180
  }
  rendering.draw_text{
    text=id..(z.protected and" [ЗАЩИЩЕНА]" or" [ОТКРЫТА]"),
    surface=s,
    target={x=(z.area.left_top.x+z.area.right_bottom.x)/2, y=z.area.left_top.y-1.5},
    color={r=1,g=1,b=1}, scale=1.2, time_to_live=180
  }
  return true
end

script.on_event(defines.events.on_player_selected_area, function(ev)
  local p=game.get_player(ev.player_index)
  if not p or not p.cursor_stack.valid_for_read or p.cursor_stack.name~="zone-selector" then return end
  storage.zone_counter=storage.zone_counter+1
  local id="zone_"..storage.zone_counter
  storage.zones[id]={area=ev.area, surface=p.surface.name, created_by=p.name, protected=true}
  protect(id); render(id)
  p.print("Зона создана и защищена: "..id,{r=0,g=1,b=0})
end)

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, function(ev)
  local ent = ev.created_entity or ev.entity
  if not ent or not ent.valid then return end
  local prot,id = is_prot(ent.position, ent.surface.name)
  if prot then
    local player = ev.player_index and game.get_player(ev.player_index)
    if player then player.print("Нельзя строить в зоне: "..id,{r=1,g=0,b=0}) end

    local count = 0
    local name
    if ent.prototype.items_to_place_this then
      for _,it in pairs(ent.prototype.items_to_place_this) do
        name = it.name; count = it.count; break
      end
    end
    if not name then name = ent.name; count = 1 end

    ent.destroy()
    if player and count > 0 then
      player.insert{name=name, count=count}
    end
    return true
  end
end)

script.on_event({
  defines.events.on_player_mined_entity,
  defines.events.on_entity_died,
  defines.events.on_player_rotated_entity,
  defines.events.on_pre_ghost_deconstructed,
  defines.events.on_marked_for_deconstruction,
  defines.events.on_player_setup_blueprint,
  defines.events.on_player_configured_blueprint,
  defines.events.on_pre_entity_settings_pasted,
  defines.events.on_gui_opened
}, function(ev)
  local e = ev.entity or ev.created_entity or ev.ghost or ev.destination
  if e and e.valid then
    local prot,id = is_prot(e.position, e.surface.name)
    if prot then
      local pl = ev.player_index and game.get_player(ev.player_index)
      if pl then pl.print("Действие запрещено в зоне: "..id,{r=1,g=0,b=0}) end
      protect_at_position(e)
      if ev.name==defines.events.on_player_mined_entity and ev.buffer then ev.buffer.clear()
      elseif ev.name==defines.events.on_player_rotated_entity and e.valid then e.rotate{reverse=true}
      elseif ev.name==defines.events.on_gui_opened and ev.player_index then local pp=game.get_player(ev.player_index); if pp then pp.opened=nil end
      end
      return true
    end
  end
end)

script.on_event(defines.events.on_entity_damaged, function(ev)
  if ev.entity and ev.entity.valid and ev.cause and ev.cause.valid then
    local f = ev.cause.force
    if f and f.players and #f.players>0 then
      if is_prot(ev.entity.position, ev.entity.surface.name) then ev.damage_amount=0 end
    end
  end
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
  if p.gui.screen.zone_gui then p.gui.screen.zone_gui.destroy() end
  local f = p.gui.screen.add{type="frame", name="zone_gui", caption="Управление зонами", direction="vertical"}; f.auto_center=true
  local scroll = f.add{type="scroll-pane", name="zone_scroll", direction="vertical", vertical_scroll_policy="auto"}; scroll.style.maximal_height=600
  for id,z in pairs(storage.zones or {}) do
    local ff = scroll.add{type="frame", name="zone_frame_"..id, direction="vertical", style="deep_frame_in_shallow_frame"}
    ff.add{type="label", caption="Зона: "..id.." ["..(z.protected and"ЗАЩИЩЕНА"or" ОТКРЫТА").."]", style="caption_label"}
    local flow = ff.add{type="flow", direction="horizontal"}
    flow.add{type="button", name="show_"..id, caption="Показать"}
    flow.add{type="button", name="protect_"..id, caption=z.protected and"Отключить"or"Включить"}
    flow.add{type="button", name="delete_"..id, caption="Удалить", style="red_button"}
  end
  f.add{type="button", name="close_gui", caption="Закрыть", style="red_back_button"}
end

commands.add_command("zone-gui","Открыть GUI",function(ev)
  local p=game.get_player(ev.player_index)
  if not p then return end
  if not p.admin then p.print("Эта команда доступна только администраторам.",{r=1,g=0,b=0}) return end
  gui(p)
end)

script.on_event(defines.events.on_gui_click, function(ev)
  local p=game.get_player(ev.player_index)
  if not p or not ev.element or not ev.element.valid then return end
  if ev.element.name=="close_gui" then
    if p.gui.screen.zone_gui then p.gui.screen.zone_gui.destroy() end
    return
  end
  local nm = ev.element.name
  if nm:find("show_") then local id=nm:match("show_(.+)"); render(id); p.print("Показана: "..id,{r=0,g=1,b=0}); return end
  if nm:find("protect_") then
    local id=nm:match("protect_(.+)"); local z=storage.zones[id]
    if z then
      z.protected = not z.protected
      if z.protected then protect(id) else unprotect(id) end
      gui(p)
    end
    return
  end
  if nm:find("delete_") then
    local id = nm:match("delete_(.+)")
    local z = storage.zones[id]
    if z then
      z.protected = false
      unprotect(id)
      storage.zones[id] = nil
      gui(p)
    end
    return
  end
end)
