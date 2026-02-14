require 'cairo'

local HOME = os.getenv('HOME') or ''
local ICON_DIR = HOME .. '/.config/conky/weather_icons'

local function file_exists(path)
  local handle = io.open(path, 'rb')
  if handle then
    handle:close()
    return true
  end
  return false
end

local function icon_code_for_condition(condition)
  local text = (condition or ''):lower()
  if text:find('thunder') or text:find('storm') then
    return '11d'
  end
  if text:find('snow') or text:find('sleet') or text:find('blizzard') then
    return '13d'
  end
  if text:find('mist') or text:find('fog') or text:find('haze') then
    return '50d'
  end
  if text:find('drizzle') then
    return '09d'
  end
  if text:find('rain') or text:find('shower') then
    return '10d'
  end
  if text:find('overcast') then
    return '04d'
  end
  if text:find('cloud') then
    return '03d'
  end
  if text:find('partly') or text:find('interval') then
    return '02d'
  end
  if text:find('sun') or text:find('clear') or text:find('fair') then
    return '01d'
  end
  return '02d'
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

local function draw_text(cr, text, x, y, size, alpha)
  cairo_select_font_face(cr, 'JetBrainsMono Nerd Font', CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  cairo_set_source_rgba(cr, 1, 1, 1, alpha or 1)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, text)
end

local function draw_panel(cr, x, y, width, height)
  cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
  cairo_rectangle(cr, x, y, width, height)
  cairo_fill(cr)

  cairo_set_source_rgba(cr, 1, 1, 1, 0.35)
  cairo_set_line_width(cr, 2)
  cairo_rectangle(cr, x, y, width, height)
  cairo_stroke(cr)
end

local function split_lines(text)
  local lines = {}
  if not text or text == '' then
    return lines
  end
  for line in (text .. '\n'):gmatch('(.-)\n') do
    if line ~= '' then
      table.insert(lines, line)
    end
  end
  return lines
end

local function ellipsize(text, max_len)
  if #text <= max_len then
    return text
  end
  return text:sub(1, max_len - 3) .. '...'
end

local function condition_from_summary(summary)
  if not summary or summary == '' then
    return ''
  end
  local cleaned = summary:gsub('^%s*[%-%+]?%d+°[CF]?%s*', '')
  cleaned = cleaned:gsub('^%s*[%-%+]?%d+%.?%d*%s*°[CF]?%s*', '')
  cleaned = cleaned:gsub('^%s+', '')
  if cleaned == '' then
    return summary
  end
  return cleaned
end

local function split_temp_and_condition(summary)
  if not summary or summary == '' then
    return '--°C', 'Unavailable'
  end

  local temp, condition = summary:match('^%s*([%-%+]?%d+%.?%d*°[CF])%s+(.+)$')
  if temp and condition then
    return temp, condition
  end

  local fallback_condition = condition_from_summary(summary)
  return '--°C', fallback_condition ~= '' and fallback_condition or 'Unavailable'
end

function conky_weather_forecast()
  if conky_window == nil then
    return
  end

  local cs = cairo_xlib_surface_create(
    conky_window.display,
    conky_window.drawable,
    conky_window.visual,
    conky_window.width,
    conky_window.height
  )
  local cr = cairo_create(cs)

  local panel_w = 860
  local panel_h = 440
  local x = (conky_window.width - panel_w) / 2
  local y = (conky_window.height - panel_h) / 2

  draw_panel(cr, x, y, panel_w, panel_h)
  local current_summary = conky_parse('${execi 600 python3 ~/.config/conky/weather_bbc.py summary}')
  local current_temp, current_condition_text = split_temp_and_condition(current_summary)
  local current_condition = condition_from_summary(current_summary)
  if current_condition ~= '' and current_summary ~= 'Unavailable' then
    local current_icon_code = icon_code_for_condition(current_condition)
    local current_icon_path = ICON_DIR .. '/' .. current_icon_code .. '.png'
    if file_exists(current_icon_path) then
      draw_png(cr, current_icon_path, x + 30, y + 16, 68, 68)
    end
  end
  draw_text(cr, current_temp, x + 115, y + 52, 34, 1)
  draw_text(cr, ellipsize(current_condition_text, 42), x + 245, y + 52, 20, 0.95)
  draw_text(cr, 'Bacoor, Cavite', x + 115, y + 82, 16, 0.9)

  cairo_set_source_rgba(cr, 1, 1, 1, 0.35)
  cairo_set_line_width(cr, 1)
  cairo_move_to(cr, x + 30, y + 100)
  cairo_line_to(cr, x + panel_w - 30, y + 100)
  cairo_stroke(cr)

  local raw = conky_parse('${execi 1800 python3 ~/.config/conky/weather_bbc_7day.py}')
  local lines = split_lines(raw)

  if #lines == 0 or lines[1] == 'Unavailable' then
    draw_text(cr, 'Weather data unavailable', x + 32, y + 150, 18, 1)
  else
    local start_y = y + 145
    local row_h = 40

    for i = 1, math.min(7, #lines) do
      local day, max_t, min_t, condition = lines[i]:match('([^|]+)|([^|]+)|([^|]+)|(.+)')
      if day and max_t and min_t and condition then
        local row_y = start_y + (i - 1) * row_h
        local icon_code = icon_code_for_condition(condition)
        local icon_path = ICON_DIR .. '/' .. icon_code .. '.png'
        if file_exists(icon_path) then
          draw_png(cr, icon_path, x + 34, row_y - 24, 28, 28)
        end

        draw_text(cr, day, x + 80, row_y, 18, 1)
        draw_text(cr, string.format('%s° / %s°', max_t, min_t), x + 275, row_y, 20, 1)
        draw_text(cr, ellipsize(condition, 33), x + 430, row_y, 18, 0.95)

        cairo_set_source_rgba(cr, 1, 1, 1, 0.20)
        cairo_set_line_width(cr, 1)
        cairo_move_to(cr, x + 30, row_y + 12)
        cairo_line_to(cr, x + panel_w - 30, row_y + 12)
        cairo_stroke(cr)
      end
    end
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
