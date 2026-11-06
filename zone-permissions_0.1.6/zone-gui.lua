local G = {}

function G.list(player, zones)
  if player.gui.screen.zone_gui then player.gui.screen.zone_gui.destroy() end
  local frame = player.gui.screen.add{type="frame",name="zone_gui",caption="Управление зонами",direction="vertical"}
  frame.auto_center = true
  local scroll = frame.add{type="scroll-pane",name="zone_scroll",direction="vertical",vertical_scroll_policy="auto"}
  scroll.style.maximal_height = 600
  local ids = {}
  for id in pairs(zones) do ids[#ids+1] = id end
  table.sort(ids)
  for _,id in ipairs(ids) do
    local z = zones[id]
    local row = scroll.add{type="frame",direction="vertical",style="deep_frame_in_shallow_frame"}
    row.add{type="label",caption="Зона: " .. id .. (z.protected and " [ЗАЩИЩЕНА]" or " [ОТКРЫТА]"),style="caption_label"}
    local buttons = row.add{type="flow",direction="horizontal"}
    buttons.add{type="button",name="show_"..id,caption="Показать",tags={zone_action="show",zone_id=id}}
    buttons.add{type="button",name="permissions_"..id,caption="Права групп",tags={zone_action="permissions",zone_id=id}}
    buttons.add{type="button",name="protect_"..id,caption=z.protected and "Отключить" or "Включить",tags={zone_action="protect",zone_id=id}}
    buttons.add{type="button",name="delete_"..id,caption="Удалить",style="red_button",tags={zone_action="delete",zone_id=id}}
  end
  frame.add{type="button",name="close_gui",caption="Закрыть",style="red_back_button",tags={zone_action="close"}}
end

function G.editor(player, id, zone, groups)
  if player.gui.screen.zone_permissions_gui then player.gui.screen.zone_permissions_gui.destroy() end
  local frame = player.gui.screen.add{type="frame",name="zone_permissions_gui",caption="Права: "..id,direction="vertical",
    tags={zone_id=id,revision=zone.revision or 0}}
  frame.auto_center = true
  frame.add{type="label",caption="«Не ограничивать» сохраняет общие права группы Factorio."}
  frame.add{type="label",caption="При пересечении зон действует запрет. Настройки применяются кнопкой «Сохранить»."}
  local scroll = frame.add{type="scroll-pane",direction="vertical",vertical_scroll_policy="auto"}
  scroll.style.maximal_height = math.max(120,math.min(430,player.display_resolution.height / player.display_scale - 320))
  local grid = scroll.add{type="table",column_count=4}
  for _,caption in ipairs{"Группа", "Строить объекты", "Демонтировать", "Взаимодействовать"} do
    grid.add{type="label",caption=caption,style="caption_label"}
  end
  grid.add{type="label",caption="Остальные группы",tooltip="Правила для групп без отдельной настройки, включая новые группы."}
  for _,action in ipairs{"build","mine","interact"} do
    grid.add{type="drop-down",items={"Запретить","Не ограничивать"},
      selected_index=zone.default_permissions[action] and 2 or 1,
      tags={permission_row="default",permission_action=action}}
  end
  for _,group in ipairs(groups) do
    grid.add{type="label",caption=group.name}
    local rule = zone.permissions[group.group_id] or {}
    for _,action in ipairs{"build","mine","interact"} do
      grid.add{type="drop-down",items={"Как для остальных","Не ограничивать","Запретить"},
        selected_index=rule[action] == nil and 1 or (rule[action] and 2 or 3),
        tags={permission_row="group",permission_group=group.group_id,permission_action=action}}
    end
  end
  frame.add{type="label",caption="Взаимодействие: открытие зданий, быстрый перенос предметов, поворот и настройки."}
  frame.add{type="checkbox",name="zone_invulnerable",caption="Защищать объекты от любого урона",state=zone.invulnerable ~= false}
  frame.add{type="checkbox",name="zone_admin_bypass",caption="Не ограничивать администраторов правилами этой зоны",state=zone.admin_bypass == true}
  frame.add{type="checkbox",name="zone_robot_build",caption="Разрешить роботам строительство",state=zone.robot_permissions.build == true}
  frame.add{type="checkbox",name="zone_robot_mine",caption="Разрешить роботам демонтаж",state=zone.robot_permissions.mine == true}
  local buttons = frame.add{type="flow",direction="horizontal"}
  buttons.add{type="button",name="zone_permissions_save",caption="Сохранить",style="confirm_button",tags={zone_action="save"}}
  buttons.add{type="button",name="zone_permissions_close",caption="Отмена",tags={zone_action="close_permissions"}}
end

local function collect(element, result)
  local tags = element.tags
  if tags.permission_row == "default" then
    result.default_permissions[tags.permission_action] = element.selected_index == 2
  elseif tags.permission_row == "group" then
    local id = tags.permission_group
    result.permissions[id] = result.permissions[id] or {}
    if element.selected_index ~= 1 then
      result.permissions[id][tags.permission_action] = element.selected_index == 2
    end
  end
  for _,child in pairs(element.children) do collect(child,result) end
end

function G.read(player)
  local frame = player.gui.screen.zone_permissions_gui
  if not frame then return end
  local result = {permissions={},default_permissions={},robot_permissions={
    build=frame.zone_robot_build.state,mine=frame.zone_robot_mine.state},
    invulnerable=frame.zone_invulnerable.state,admin_bypass=frame.zone_admin_bypass.state}
  collect(frame,result)
  return frame.tags.zone_id,frame.tags.revision,result
end

function G.owns(element)
  while element do
    if element.name == "zone_gui" or element.name == "zone_permissions_gui" then return true end
    element = element.parent
  end
  return false
end

function G.close_editor(player)
  if player.gui.screen.zone_permissions_gui then player.gui.screen.zone_permissions_gui.destroy() end
end

return G
