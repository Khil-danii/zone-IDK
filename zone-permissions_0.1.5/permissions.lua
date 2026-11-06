local P = {}
local changing_groups = false

-- These inputs all act on the selected entity. GUI edits are guarded by
-- refusing/closing the entity GUI, including one opened before a rule changes.
local restricted_inputs = {
  [1] = {"begin_mining"},
  [2] = {"rotate_entity", "flip_entity", "fast_entity_transfer", "fast_entity_split",
    "paste_entity_settings", "copy_entity_settings", "wire_dragging", "remove_cables",
    "toggle_selected_entity", "toggle_driving", "build"}
}

function P.initialize()
  local migrating = storage.zone_permissions_schema ~= 1
  storage.permission_overlays = storage.permission_overlays or {}
  storage.permission_cache = storage.permission_cache or {}
  for _,z in pairs(storage.zones) do
    z.permissions = z.permissions or {}
    z.default_permissions = z.default_permissions or {build=false, mine=false, interact=false}
    z.robot_permissions = z.robot_permissions or {build=false, mine=false}
    if z.invulnerable == nil then z.invulnerable = true end
    z.revision = z.revision or 0
  end
  storage.zone_permissions_schema = 1
  if migrating then
    for _,player in pairs(game.players) do
      if player.gui.screen.zone_gui then player.gui.screen.zone_gui.destroy() end
      if player.gui.screen.zone_permissions_gui then player.gui.screen.zone_permissions_gui.destroy() end
    end
  end
end

-- Replacing a ZIP without changing its version does not necessarily invoke
-- on_configuration_changed. Initialize on the first runtime event as well;
-- never write to storage during on_load.
function P.ensure()
  if storage.zone_permissions_schema ~= 1 then
    storage.zones = storage.zones or {}
    storage.zone_counter = storage.zone_counter or 0
    storage.protected_entities = storage.protected_entities or {}
    P.initialize()
  end
end

function P.base_group(player)
  P.ensure()
  local group = player.permission_group or game.permissions.get_group(0)
  local overlay = group and storage.permission_overlays[group.group_id]
  if overlay then return game.permissions.get_group(overlay.base_id) or game.permissions.get_group(0) end
  return group
end

function P.groups()
  P.ensure()
  local groups = {}
  for _,group in pairs(game.permissions.groups) do
    if not storage.permission_overlays[group.group_id] then groups[#groups+1] = group end
  end
  table.sort(groups, function(a,b) return a.group_id < b.group_id end)
  return groups
end

function P.zone_allows(z, group_id, action, admin)
  if admin and z.admin_bypass then return true end
  local rule = z.permissions and z.permissions[group_id]
  if rule and rule[action] ~= nil then return rule[action] end
  return z.default_permissions and z.default_permissions[action] == true
end

local function contains(z, position, surface)
  return z.protected and z.surface == surface
    and position.x >= z.area.left_top.x and position.x <= z.area.right_bottom.x
    and position.y >= z.area.left_top.y and position.y <= z.area.right_bottom.y
end

function P.zone_denial(player, position, surface, action)
  P.ensure()
  local group = player and P.base_group(player)
  for id,z in pairs(storage.zones) do
    if contains(z, position, surface) then
      local allowed
      if player then
        allowed = P.zone_allows(z, group and group.group_id or 0, action, player.admin)
      else
        allowed = z.robot_permissions and z.robot_permissions[action] == true
      end
      if not allowed then return id end
    end
  end
end

function P.can_act(player, position, surface, action, input)
  if player and input then
    local group = P.base_group(player)
    if group and not group.allows_action(defines.input_action[input]) then
      return false, "общие права группы"
    end
  end
  local id = P.zone_denial(player, position, surface, action)
  return id == nil, id
end

-- Entity-wide locks can only remain when nobody is allowed this action.
-- Otherwise native player input permissions enforce each group's restriction.
function P.any_allowed(z, action)
  if z.admin_bypass or (z.robot_permissions and z.robot_permissions[action])
      or (z.default_permissions and z.default_permissions[action]) then return true end
  for group_id,rule in pairs(z.permissions or {}) do
    if rule[action] and game.permissions.get_group(group_id) then return true end
  end
  return false
end

local function opened_entity(player)
  local opened = player.opened
  if opened and opened.valid and opened.object_name == "LuaEntity" then return opened end
end

local function deny_entity(player, entity, action)
  return entity and entity.valid and P.zone_denial(player, entity.position, entity.surface.name, action)
end

local function synchronize(derived, base, mask)
  for _,action in pairs(defines.input_action) do
    local allowed = base.allows_action(action)
    for bit,names in pairs(restricted_inputs) do
      if bit32.band(mask,bit) ~= 0 then
        for _,name in ipairs(names) do
          if defines.input_action[name] == action then allowed = false; break end
        end
      end
    end
    if derived.allows_action(action) ~= allowed then derived.set_allows_action(action,allowed) end
  end
end

local function effective_group(base, mask)
  local cache = storage.permission_cache[base.group_id]
  if not cache then cache = {}; storage.permission_cache[base.group_id] = cache end
  local group = cache[mask] and game.permissions.get_group(cache[mask])
  if not group then
    group = assert(game.permissions.create_group("[Zone Permissions] " .. base.group_id .. ":" .. mask))
    storage.permission_overlays[group.group_id] = {base_id=base.group_id, mask=mask}
    cache[mask] = group.group_id
    synchronize(group,base,mask)
  end
  return group
end

function P.refresh(player)
  if changing_groups or not player or not player.valid then return end
  local base = P.base_group(player)
  if not base then return end
  local selected = player.selected
  local mine = deny_entity(player,selected,"mine")
  local interact = deny_entity(player,selected,"interact")
  local opened = opened_entity(player)
  if deny_entity(player,opened,"interact") then player.opened = nil end
  local mask = (mine and 1 or 0) + (interact and 2 or 0)
  if (mine or not base.allows_action(defines.input_action.begin_mining))
      and (player.controller_type == defines.controllers.character
      or player.controller_type == defines.controllers.god
      or player.controller_type == defines.controllers.editor) then
    if player.mining_state.mining then player.mining_state = {mining=false} end
  end
  changing_groups = true
  local target = mask == 0 and base or effective_group(base,mask)
  if player.permission_group ~= target then player.permission_group = target end
  changing_groups = false
end

function P.refresh_all()
  if changing_groups then return end
  P.ensure()
  local active = false
  for _,z in pairs(storage.zones) do if z.protected then active = true; break end end
  if not active then
    P.release_all()
    return
  end
  for _,player in pairs(game.connected_players) do P.refresh(player) end
end

function P.release_all()
  P.ensure()
  if changing_groups or not next(storage.permission_overlays) then return end
  changing_groups = true
  for _,player in pairs(game.players) do
    if player.permission_group and storage.permission_overlays[player.permission_group.group_id] then
      player.permission_group = P.base_group(player)
    end
  end
  for id in pairs(storage.permission_overlays) do
    local group = game.permissions.get_group(id)
    if group then group.destroy() end
  end
  storage.permission_overlays = {}
  storage.permission_cache = {}
  changing_groups = false
end

function P.synchronize_all()
  if changing_groups then return end
  P.ensure()
  changing_groups = true
  for id,overlay in pairs(storage.permission_overlays) do
    local group,base = game.permissions.get_group(id),game.permissions.get_group(overlay.base_id)
    if group and base then synchronize(group,base,overlay.mask) end
  end
  changing_groups = false
  P.refresh_all()
end

function P.on_group_edited(ev)
  -- Membership events run inside the engine's assignment. Reassigning the
  -- player there interrupts that assignment; the next tick/selection refresh
  -- applies the new canonical group's restrictions after it has completed.
  if ev.type == "add-player" or ev.type == "remove-player" then return end
  if not changing_groups then P.synchronize_all() end
end

function P.on_group_deleting(ev)
  if changing_groups then return end
  P.ensure()
  changing_groups = true
  local id = ev.group.group_id
  local overlay = storage.permission_overlays[id]
  if overlay then
    local base = game.permissions.get_group(overlay.base_id) or game.permissions.get_group(0)
    for _,player in pairs(ev.group.players) do player.permission_group = base end
    local cache = storage.permission_cache[overlay.base_id]
    if cache then cache[overlay.mask] = nil end
    storage.permission_overlays[id] = nil
  else
    for overlay_id,entry in pairs(storage.permission_overlays) do
      if entry.base_id == id then
        local group = game.permissions.get_group(overlay_id)
        if group then
          for _,player in pairs(group.players) do player.permission_group = game.permissions.get_group(0) end
          group.destroy()
        end
        storage.permission_overlays[overlay_id] = nil
      end
    end
    storage.permission_cache[id] = nil
    for _,z in pairs(storage.zones) do
      if z.permissions then z.permissions[id] = nil end
      z.revision = (z.revision or 0) + 1
    end
  end
  changing_groups = false
end

return P
