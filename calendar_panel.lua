require 'cairo'

local function draw_text(cr, text, x, y, size, alpha, bold)
  local weight = bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
  cairo_select_font_face(cr, 'JetBrainsMono Nerd Font', CAIRO_FONT_SLANT_NORMAL, weight)
  cairo_set_font_size(cr, size)
  cairo_set_source_rgba(cr, 1, 1, 1, alpha or 1)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, text)
end

local function draw_text_centered(cr, text, center_x, y, size, alpha, bold)
  local weight = bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
  cairo_select_font_face(cr, 'JetBrainsMono Nerd Font', CAIRO_FONT_SLANT_NORMAL, weight)
  cairo_set_font_size(cr, size)

  local extents = cairo_text_extents_t:create()
  cairo_text_extents(cr, text, extents)

  cairo_set_source_rgba(cr, 1, 1, 1, alpha or 1)
  cairo_move_to(cr, center_x - (extents.width / 2) - extents.x_bearing, y)
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

local function draw_cell(cr, x, y, w, h, alpha)
  cairo_set_source_rgba(cr, 1, 1, 1, alpha)
  cairo_rectangle(cr, x, y, w, h)
  cairo_fill(cr)
end

local function is_leap_year(year)
  if year % 400 == 0 then
    return true
  end
  if year % 100 == 0 then
    return false
  end
  return year % 4 == 0
end

local function days_in_month(year, month)
  local month_lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
  if month == 2 and is_leap_year(year) then
    return 29
  end
  return month_lengths[month]
end

local function build_month_grid(year, month)
  local grid = {}
  for r = 1, 6 do
    grid[r] = {nil, nil, nil, nil, nil, nil, nil}
  end

  local first_day_wday = tonumber(os.date('%w', os.time({year = year, month = month, day = 1}))) + 1
  local total_days = days_in_month(year, month)

  local row = 1
  local col = first_day_wday
  for day = 1, total_days do
    grid[row][col] = day
    col = col + 1
    if col > 7 then
      col = 1
      row = row + 1
      if row > 6 then
        break
      end
    end
  end

  return grid
end

function conky_calendar_panel()
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

  local panel_w = 640
  local panel_h = 430
  local x = (conky_window.width - panel_w) / 2
  local y = (conky_window.height - panel_h) / 2 + 20

  draw_panel(cr, x, y, panel_w, panel_h)

  local month_title = conky_parse('${time %B %Y}')
  local today = tonumber(conky_parse('${time %d}')) or 0
  local year = tonumber(conky_parse('${time %Y}')) or tonumber(os.date('%Y'))
  local month = tonumber(conky_parse('${time %m}')) or tonumber(os.date('%m'))
  local month_grid = build_month_grid(year, month)
  local clock_text = conky_parse('${time %H:%M:%S}')

  draw_text_centered(cr, clock_text, x + (panel_w / 2), y - 6, 65, 1, true)

  draw_text(cr, '  ' .. month_title, x + 26, y + 46, 30, 1, true)
  draw_text(cr, conky_parse('${time %A, %b %d}'), x + 28, y + 76, 16, 0.9, false)

  cairo_set_source_rgba(cr, 1, 1, 1, 0.35)
  cairo_set_line_width(cr, 1)
  cairo_move_to(cr, x + 22, y + 92)
  cairo_line_to(cr, x + panel_w - 22, y + 92)
  cairo_stroke(cr)

  local headers = {'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'}
  local grid_x = x + 26
  local grid_y = y + 118
  local cell_w = 82
  local cell_h = 48

  for c = 1, 7 do
    draw_text(cr, headers[c], grid_x + (c - 1) * cell_w + 16, grid_y + 20, 14, 0.95, true)
  end

  for r = 1, 6 do
    for col = 1, 7 do
      local day_num = month_grid[r][col]
      if day_num then
        local cx = grid_x + (col - 1) * cell_w
        local cy = grid_y + 26 + (r - 1) * cell_h

        local is_today = day_num == today
        if is_today then
          draw_cell(cr, cx + 4, cy + 4, cell_w - 8, cell_h - 8, 0.35)
        else
          draw_cell(cr, cx + 4, cy + 4, cell_w - 8, cell_h - 8, 0.08)
        end

        cairo_set_source_rgba(cr, 1, 1, 1, 0.25)
        cairo_set_line_width(cr, 1)
        cairo_rectangle(cr, cx + 4, cy + 4, cell_w - 8, cell_h - 8)
        cairo_stroke(cr)

        draw_text(cr, tostring(day_num), cx + 16, cy + 32, 18, 1, is_today)
      end
    end
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
