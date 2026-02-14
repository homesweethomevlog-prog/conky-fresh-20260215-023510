require 'cairo'

local HOME = os.getenv('HOME') or ''
local VCLOUDS_DIR = HOME .. '/.config/conky/vclouds'

local function file_exists(path)
  local handle = io.open(path, 'rb')
  if handle then
    handle:close()
    return true
  end
  return false
end

local ICON_CANDIDATES = {
  clear = {'sun.png', 'sunny.png', 'clear.png', '32.png'},
  partly = {'partlycloudy.png', 'partly_cloudy.png', '30.png'},
  cloudy = {'cloudy.png', 'cloud.png', '26.png'},
  rain = {'rain.png', 'showers.png', 'rainy.png', '11.png', '12.png'},
  storm = {'storm.png', 'thunderstorm.png', 'thunder.png', '04.png'},
  snow = {'snow.png', 'sleet.png', '16.png'},
  fog = {'fog.png', 'mist.png', '20.png'},
}

local function resolve_icon_path(icon_key)
  local candidates = ICON_CANDIDATES[icon_key] or ICON_CANDIDATES.partly
  for _, filename in ipairs(candidates) do
    local fullpath = VCLOUDS_DIR .. '/' .. filename
    if file_exists(fullpath) then
      return fullpath
    end
  end
  return nil
end

local function draw_png(cr, path, x, y, width, height)
  local image = cairo_image_surface_create_from_png(path)
  if cairo_surface_status(image) ~= CAIRO_STATUS_SUCCESS then
    cairo_surface_destroy(image)
    return
  end

  local image_width = cairo_image_surface_get_width(image)
  local image_height = cairo_image_surface_get_height(image)
  if image_width <= 0 or image_height <= 0 then
    cairo_surface_destroy(image)
    return
  end

  local sx = width / image_width
  local sy = height / image_height

  cairo_save(cr)
  cairo_translate(cr, x, y)
  cairo_scale(cr, sx, sy)
  cairo_set_source_surface(cr, image, 0, 0)
  cairo_paint(cr)
  cairo_restore(cr)
  cairo_surface_destroy(image)
end

local function draw_ring(cr, pct, x, y, radius, thickness, bg, fg)
  local angle0 = -math.pi / 2
  local angle1 = angle0 + (2 * math.pi * pct)

  cairo_set_line_width(cr, thickness)

  cairo_set_source_rgba(cr, bg[1], bg[2], bg[3], bg[4])
  cairo_arc(cr, x, y, radius, 0, 2 * math.pi)
  cairo_stroke(cr)

  cairo_set_source_rgba(cr, fg[1], fg[2], fg[3], fg[4])
  cairo_arc(cr, x, y, radius, angle0, angle1)
  cairo_stroke(cr)
end

function conky_draw_rings()
  if conky_window == nil then return end
  local cs = cairo_xlib_surface_create(
    conky_window.display,
    conky_window.drawable,
    conky_window.visual,
    conky_window.width,
    conky_window.height
  )
  local cr = cairo_create(cs)

  local cpu = tonumber(conky_parse('${cpu cpu0}')) or 0
  local mem = tonumber(conky_parse('${memperc}')) or 0
  local disk = tonumber(conky_parse('${fs_used_perc /}')) or 0

  local center_x = conky_window.width - 170
  local center_y = 170

  draw_ring(cr, cpu / 100, center_x, center_y, 95, 14, {1, 1, 1, 0.15}, {0.2, 0.7, 1, 0.9})
  draw_ring(cr, mem / 100, center_x, center_y, 120, 14, {1, 1, 1, 0.15}, {0.4, 1, 0.5, 0.9})
  draw_ring(cr, disk / 100, center_x, center_y, 145, 14, {1, 1, 1, 0.15}, {1, 0.7, 0.2, 0.9})

  local icon_key = conky_parse('${execi 1800 python3 ~/.config/conky/weather_bbc.py icon}')
  local icon_path = resolve_icon_path(icon_key or '')
  if icon_path then
    draw_png(cr, icon_path, 20, 345, 84, 84)
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

function draw_rings()
  conky_draw_rings()
end
