data:extend({
  -- Основной инструмент выделения зон
  {
    type = "selection-tool",
    name = "zone-selector",
    icon = "__base__/graphics/icons/blueprint.png",
    icon_size = 64,
    icon_mipmaps = 4,
    subgroup = "tool",
    order = "zzz[zone-selector]", -- Чтобы был в конце списка
    stack_size = 1,
    
    -- Цвета выделения
    selection_color = { r = 0, g = 1, b = 0, a = 0.2 },
    alt_selection_color = { r = 1, g = 0, b = 0, a = 0.2 },
    
    -- Режимы выделения
    selection_mode = {"any-entity"},
    alt_selection_mode = {"nothing"},
    
    -- Типы курсоров
    selection_cursor_box_type = "copy",
    alt_selection_cursor_box_type = "not-allowed",
    
    -- Основной режим (ЛКМ)
    select = {
      type = "custom",
      border_color = { r = 0, g = 1, b = 0 },
      cursor_box_type = "copy",
      mode = "blueprint"
    },
    
    -- Альтернативный режим (ПКМ)
    alt_select = {
      type = "custom",
      border_color = { r = 1, g = 0, b = 0 },
      cursor_box_type = "not-allowed",
      mode = "cancel-deconstruct"
    }
  },
  
  -- (Опционально) Иконка для интерфейса
  {
    type = "sprite",
    name = "zone-selector-icon",
    filename = "__base__/graphics/icons/blueprint.png",
    size = 64,
    mipmap_count = 4,
    flags = {"icon"}
  }
})

-- (Опционально) Добавляем в группы творческого режима
if mods["editor-extensions"] then
  data:extend({
    {
      type = "item-subgroup",
      name = "zone-tools",
      group = "editor",
      order = "zz"
    }
  })
  
  data.raw["selection-tool"]["zone-selector"].subgroup = "zone-tools"
  data.raw["selection-tool"]["zone-selector"].order = "a[zone]"
end