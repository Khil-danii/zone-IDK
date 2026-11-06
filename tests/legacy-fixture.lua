-- Minimal 0.1.5 storage format before group permissions, deliberately with no
-- new fields. Same metadata/version: migration must also handle a replaced ZIP.
script.on_init(function()
  storage.zones = {}
  storage.zone_counter = 1
  storage.protected_entities = {}
  local surface = game.create_surface("legacy-zone-tests",{width=32,height=32})
  surface.set_tiles{{name="grass-1",position={0,0}}}
  local entity = surface.create_entity{name="transport-belt",position={0.5,0.5},force="player"}
  local registration = script.register_on_object_destroyed(entity)
  storage.zones.zone_1={surface=surface.name,protected=true,
    area={left_top={x=-2,y=-2},right_bottom={x=2,y=2}},protected_entities={[registration]=true}}
  storage.protected_entities[registration]={entity=entity,minable_flag=true,rotatable=true,
    destructible=true,zones={zone_1=true}}
  entity.minable_flag=false; entity.rotatable=false; entity.destructible=false
  storage.legacy_test_entity=entity
  log("ZONE TEST PASS: legacy persistence fixture created")
end)
