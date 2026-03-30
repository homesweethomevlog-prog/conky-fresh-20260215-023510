require 'cairo'

local drive_cache = {
  timestamp = 0,
  entries = {},
}

local network_graph_cache = {}
local cpu_graph_cache = {
  timestamp = 0,
  history = {},
}

local function draw_panel(cr, x, y, width, height)
  cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
  cairo_rectangle(cr, x, y, width, height)
  cairo_fill(cr)

  cairo_set_source_rgba(cr, 1, 1, 1, 0.35)
  cairo_set_line_width(cr, 2)
  cairo_rectangle(cr, x, y, width, height)
  cairo_stroke(cr)
end

local function draw_text(cr, text, x, y, size, alpha)
  cairo_select_font_face(cr, 'JetBrainsMono Nerd Font', CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  cairo_set_source_rgba(cr, 1, 1, 1, alpha or 1)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, text or '')
end

local function draw_circle(cr, x, y, radius, r, g, b, a)
  cairo_set_source_rgba(cr, r, g, b, a)
  cairo_arc(cr, x, y, radius, 0, math.pi * 2)
  cairo_fill(cr)
end

local function draw_bar(cr, x, y, width, height, percent)
  local clamped = math.max(0, math.min(100, percent or 0))

  cairo_set_source_rgba(cr, 1, 1, 1, 0.12)
  cairo_rectangle(cr, x, y, width, height)
  cairo_fill(cr)

  cairo_set_source_rgba(cr, 0.98, 0.47, 0.28, 0.95)
  cairo_rectangle(cr, x, y, width * (clamped / 100), height)
  cairo_fill(cr)
end

local function draw_divider(cr, x1, y, x2, alpha)
  cairo_set_source_rgba(cr, 1, 1, 1, alpha or 0.14)
  cairo_set_line_width(cr, 1)
  cairo_move_to(cr, x1, y)
  cairo_line_to(cr, x2, y)
  cairo_stroke(cr)
end

local function draw_graph(cr, x, y, width, height, history, r, g, b)
  cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
  cairo_rectangle(cr, x, y, width, height)
  cairo_fill(cr)

  local max_value = 64 * 1024
  for _, value in ipairs(history) do
    if value > max_value then
      max_value = value
    end
  end

  if #history > 1 then
    local step_x = width / (#history - 1)

    cairo_set_source_rgba(cr, r, g, b, 0.18)
    cairo_move_to(cr, x, y + height)
    for index, value in ipairs(history) do
      local px = x + (index - 1) * step_x
      local py = y + height - ((value / max_value) * height)
      cairo_line_to(cr, px, py)
    end
    cairo_line_to(cr, x + width, y + height)
    cairo_close_path(cr)
    cairo_fill(cr)

    cairo_set_source_rgba(cr, r, g, b, 0.95)
    cairo_set_line_width(cr, 1.5)
    for index, value in ipairs(history) do
      local px = x + (index - 1) * step_x
      local py = y + height - ((value / max_value) * height)
      if index == 1 then
        cairo_move_to(cr, px, py)
      else
        cairo_line_to(cr, px, py)
      end
    end
    cairo_stroke(cr)
  end

  cairo_set_source_rgba(cr, 1, 1, 1, 0.18)
  cairo_rectangle(cr, x, y, width, height)
  cairo_stroke(cr)
end

local function read_file(path)
  local handle = io.open(path, 'r')
  if not handle then
    return nil
  end

  local content = handle:read('*a')
  handle:close()
  return content
end

local function read_cpu_count()
  local handle = io.open('/proc/stat', 'r')
  if not handle then
    return 0
  end

  local count = 0
  for line in handle:lines() do
    if line:match('^cpu%d+') then
      count = count + 1
    end
  end
  handle:close()
  return count
end

local function first_line(path)
  local handle = io.open(path, 'r')
  if not handle then
    return nil
  end

  local line = handle:read('*l')
  handle:close()
  return line
end

local function read_cpu_model()
  local handle = io.open('/proc/cpuinfo', 'r')
  if not handle then
    return 'CPU Monitor'
  end

  for line in handle:lines() do
    local model = line:match('^model name%s*:%s*(.+)$')
    if model then
      handle:close()
      model = model:gsub('%(R%)', '')
      model = model:gsub('%(TM%)', '')
      model = model:gsub('%s+', ' ')
      model = model:gsub('^%s+', '')
      model = model:gsub('%s+$', '')
      return model
    end
  end

  handle:close()
  return 'CPU Monitor'
end

local function read_loadavg()
  local content = read_file('/proc/loadavg') or ''
  local one, five, fifteen = content:match('([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)')
  return one or '--', five or '--', fifteen or '--'
end

local function read_meminfo()
  local handle = io.open('/proc/meminfo', 'r')
  if not handle then
    return {}
  end

  local info = {}
  for line in handle:lines() do
    local key, value = line:match('^(%w+):%s+(%d+)')
    if key and value then
      info[key] = tonumber(value)
    end
  end
  handle:close()
  return info
end

local function format_uptime()
  local content = read_file('/proc/uptime') or ''
  local seconds = tonumber(content:match('([%d%.]+)')) or 0
  local total = math.floor(seconds)
  local days = math.floor(total / 86400)
  local hours = math.floor((total % 86400) / 3600)
  local minutes = math.floor((total % 3600) / 60)

  if days > 0 then
    return string.format('%dd %02dh', days, hours)
  end
  if hours > 0 then
    return string.format('%dh %02dm', hours, minutes)
  end
  return string.format('%dm', minutes)
end

local function parse_number(text)
  return tonumber((text or ''):match('([%d%.]+)')) or 0
end

local function ellipsize(text, max_len)
  if not text or text == '' then
    return ''
  end
  if #text <= max_len then
    return text
  end
  return text:sub(1, max_len - 3) .. '...'
end

local function format_gib_from_kib(kib)
  local value = (kib or 0) / (1024 * 1024)
  return string.format('%.1f GiB', value)
end

local function format_bytes(bytes)
  local units = { 'B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB' }
  local value = tonumber(bytes) or 0
  local unit_index = 1

  while value >= 1024 and unit_index < #units do
    value = value / 1024
    unit_index = unit_index + 1
  end

  if unit_index == 1 then
    return string.format('%d %s', value, units[unit_index])
  end
  return string.format('%.1f %s', value, units[unit_index])
end

local function is_external_mount(mountpoint)
  return mountpoint == '/mnt'
    or mountpoint:match('^/mnt/.+') ~= nil
    or mountpoint:match('^/media/.+') ~= nil
    or mountpoint:match('^/run/media/.+') ~= nil
end

local function read_drive_entries()
  local now = os.time()
  if drive_cache.timestamp ~= 0 and now - drive_cache.timestamp < 10 then
    return drive_cache.entries
  end

  local handle = io.popen('df -P -B1 2>/dev/null')
  if not handle then
    return drive_cache.entries
  end

  local entries = {}
  for line in handle:lines() do
    local filesystem, total, used, available, percent, mountpoint =
      line:match('^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%%s+(.+)$')

    if filesystem and mountpoint then
      table.insert(entries, {
        filesystem = filesystem,
        total = tonumber(total) or 0,
        used = tonumber(used) or 0,
        available = tonumber(available) or 0,
        percent = tonumber(percent) or 0,
        mountpoint = mountpoint,
      })
    end
  end

  handle:close()
  drive_cache.timestamp = now
  drive_cache.entries = entries
  return entries
end

local function find_mount_entry(entries, mountpoint)
  for _, entry in ipairs(entries) do
    if entry.mountpoint == mountpoint then
      return entry
    end
  end
  return nil
end

local function collect_external_entries(entries)
  local results = {}
  for _, entry in ipairs(entries) do
    if is_external_mount(entry.mountpoint) then
      table.insert(results, entry)
    end
  end
  return results
end

local function drive_label(entry)
  if not entry then
    return 'Unavailable'
  end

  if entry.mountpoint == '/' then
    return 'System /'
  end
  if entry.mountpoint == '/home' then
    return 'Home /home'
  end

  local label = entry.mountpoint:match('([^/]+)$') or entry.mountpoint
  return ellipsize(label, 24)
end

local function detect_primary_interface()
  local handle = io.open('/proc/net/route', 'r')
  if handle then
    for line in handle:lines() do
      local iface, destination = line:match('^(%S+)%s+(%S+)')
      if iface and destination == '00000000' and iface ~= 'lo' then
        handle:close()
        return iface
      end
    end
    handle:close()
  end

  local net_dir = '/sys/class/net'
  local pipe = io.popen('ls -1 ' .. net_dir .. ' 2>/dev/null')
  if not pipe then
    return 'lo'
  end

  local selected = 'lo'
  for iface in pipe:lines() do
    if iface ~= 'lo' then
      local operstate = first_line(net_dir .. '/' .. iface .. '/operstate')
      if operstate == 'up' then
        selected = iface
        break
      end
      if selected == 'lo' then
        selected = iface
      end
    end
  end
  pipe:close()
  return selected
end

local function format_speed(value, unit)
  local numeric = tonumber((value or ''):match('([%d%.]+)')) or 0
  if numeric >= 1024 then
    return string.format('%.2f M%s', numeric / 1024, unit)
  end
  return string.format('%.0f K%s', numeric, unit)
end

local function read_counter_bytes(iface, counter)
  return tonumber(read_file(string.format('/sys/class/net/%s/statistics/%s_bytes', iface, counter))) or 0
end

local function trim_history(history, max_points)
  while #history > max_points do
    table.remove(history, 1)
  end
end

local function update_network_graphs(iface)
  if not iface or iface == '' then
    return { rx_history = { 0 }, tx_history = { 0 } }
  end

  local state = network_graph_cache[iface]
  if not state then
    state = {
      timestamp = 0,
      rx_bytes = read_counter_bytes(iface, 'rx'),
      tx_bytes = read_counter_bytes(iface, 'tx'),
      rx_history = {},
      tx_history = {},
    }
    network_graph_cache[iface] = state
  end

  local now = os.time()
  local current_rx = read_counter_bytes(iface, 'rx')
  local current_tx = read_counter_bytes(iface, 'tx')

  if state.timestamp ~= 0 and now > state.timestamp then
    local elapsed = now - state.timestamp
    local rx_rate = math.max(0, current_rx - state.rx_bytes) / elapsed
    local tx_rate = math.max(0, current_tx - state.tx_bytes) / elapsed
    table.insert(state.rx_history, rx_rate)
    table.insert(state.tx_history, tx_rate)
    trim_history(state.rx_history, 72)
    trim_history(state.tx_history, 72)
  elseif #state.rx_history == 0 then
    table.insert(state.rx_history, 0)
    table.insert(state.tx_history, 0)
  end

  state.timestamp = now
  state.rx_bytes = current_rx
  state.tx_bytes = current_tx
  return state
end

local function update_cpu_graph(sample)
  local now = os.time()
  if cpu_graph_cache.timestamp ~= now then
    table.insert(cpu_graph_cache.history, math.max(0, sample or 0))
    trim_history(cpu_graph_cache.history, 72)
    cpu_graph_cache.timestamp = now
  elseif #cpu_graph_cache.history == 0 then
    table.insert(cpu_graph_cache.history, math.max(0, sample or 0))
  end

  return cpu_graph_cache.history
end

local function draw_drive_row(cr, x, y, width, entry)
  if not entry then
    draw_text(cr, 'Unavailable', x, y, 15, 0.8)
    return 38
  end

  draw_text(cr, drive_label(entry), x, y, 16, 1)
  draw_text(cr, string.format('%d%%', math.floor(entry.percent + 0.5)), x + width - 44, y, 16, 1)
  draw_bar(cr, x, y + 12, width, 10, entry.percent)
  draw_text(
    cr,
    string.format('Used %s / %s', format_bytes(entry.used), format_bytes(entry.total)),
    x,
    y + 34,
    14,
    0.9
  )

  cairo_set_source_rgba(cr, 1, 1, 1, 0.14)
  cairo_set_line_width(cr, 1)
  cairo_move_to(cr, x, y + 46)
  cairo_line_to(cr, x + width, y + 46)
  cairo_stroke(cr)
  return 56
end

function conky_cpu_monitor()
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

  local panel_w = 500
  local panel_h = 1400
  local x = (conky_window.width - panel_w) / 2
  local y = (conky_window.height - panel_h) / 2

  local cpu_total = parse_number(conky_parse('${cpu cpu0}'))
  local cpu_count = read_cpu_count()
  local cpu_model = ellipsize(read_cpu_model(), 34)
  local load_1, load_5, load_15 = read_loadavg()
  local uptime = format_uptime()
  local meminfo = read_meminfo()
  local mem_total = meminfo.MemTotal or 0
  local mem_available = meminfo.MemAvailable or 0
  local mem_used = math.max(mem_total - mem_available, 0)
  local mem_percent = mem_total > 0 and (mem_used / mem_total) * 100 or 0
  local mem_cached = (meminfo.Cached or 0) + (meminfo.SReclaimable or 0)
  local mem_buffers = meminfo.Buffers or 0
  local swap_total = meminfo.SwapTotal or 0
  local swap_free = meminfo.SwapFree or 0
  local swap_used = math.max(swap_total - swap_free, 0)
  local swap_percent = swap_total > 0 and (swap_used / swap_total) * 100 or 0
  local drive_entries = read_drive_entries()
  local root_drive = find_mount_entry(drive_entries, '/')
  local home_drive = find_mount_entry(drive_entries, '/home')
  local external_drives = collect_external_entries(drive_entries)
  local iface = detect_primary_interface()
  local ip_addr = conky_parse(string.format('${addr %s}', iface))
  local downspeed = conky_parse(string.format('${downspeedf %s}', iface))
  local upspeed = conky_parse(string.format('${upspeedf %s}', iface))
  local totaldown = conky_parse(string.format('${totaldown %s}', iface))
  local totalup = conky_parse(string.format('${totalup %s}', iface))
  local signal = conky_parse(string.format('${wireless_link_qual_perc %s}', iface))
  local essid = conky_parse(string.format('${wireless_essid %s}', iface))
  local network_graphs = update_network_graphs(iface)
  local cpu_graph = update_cpu_graph(cpu_total)

  draw_panel(cr, x, y, panel_w, panel_h)
  draw_circle(cr, x + 34, y + 50, 10, 0.98, 0.47, 0.28, 1)
  draw_text(cr, string.format('%d%%', math.floor(cpu_total + 0.5)), x + 70, y + 54, 34, 1)
  draw_text(cr, cpu_model, x + 190, y + 46, 15, 0.95)
  draw_text(
    cr,
    string.format('%d cores   load %s %s %s   up %s', cpu_count, load_1, load_5, load_15, uptime),
    x + 32,
    y + 92,
    15,
    0.88
  )

  draw_divider(cr, x + 30, y + 108, x + panel_w - 30, 0.35)

  local cpu_graph_y = y + 126
  draw_text(cr, 'CPU History', x + 32, cpu_graph_y, 16, 0.95)
  draw_text(cr, string.format('%d%%', math.floor(cpu_total + 0.5)), x + 404, cpu_graph_y, 16, 0.95)
  draw_graph(cr, x + 32, cpu_graph_y + 10, 408, 42, cpu_graph, 0.98, 0.47, 0.28)
  draw_divider(cr, x + 30, cpu_graph_y + 66, x + panel_w - 30)

  local visible_cores = math.min(math.max(cpu_count, 1), 8)
  local process_count = 10
  local row_y = y + 204
  local row_h = 28

  for core = 1, visible_cores do
    local usage = parse_number(conky_parse(string.format('${cpu cpu%d}', core)))
    local current_y = row_y + (core - 1) * row_h

    draw_circle(cr, x + 35, current_y - 6, 4, 0.98, 0.47, 0.28, 1)
    draw_text(cr, string.format('Core %d', core), x + 50, current_y, 16, 1)
    draw_bar(cr, x + 148, current_y - 14, 220, 10, usage)
    draw_text(cr, string.format('%3d%%', math.floor(usage + 0.5)), x + 388, current_y, 16, 1)

    draw_divider(cr, x + 30, current_y + 12, x + panel_w - 30)
  end

  local memory_y = row_y + visible_cores * row_h + 26
  draw_text(cr, 'Memory', x + 32, memory_y, 18, 1)
  draw_text(cr, string.format('%d%%', math.floor(mem_percent + 0.5)), x + 403, memory_y, 18, 1)

  local ram_bar_y = memory_y + 16
  draw_bar(cr, x + 32, ram_bar_y, 408, 12, mem_percent)
  draw_text(
    cr,
    string.format('Used %s / %s', format_gib_from_kib(mem_used), format_gib_from_kib(mem_total)),
    x + 32,
    ram_bar_y + 30,
    15,
    0.95
  )
  draw_text(
    cr,
    string.format('Available %s', format_gib_from_kib(mem_available)),
    x + 282,
    ram_bar_y + 30,
    15,
    0.95
  )
  draw_text(
    cr,
    string.format('Cached %s', format_gib_from_kib(mem_cached)),
    x + 32,
    ram_bar_y + 56,
    15,
    0.82
  )
  draw_text(
    cr,
    string.format('Buffers %s', format_gib_from_kib(mem_buffers)),
    x + 282,
    ram_bar_y + 56,
    15,
    0.82
  )

  local swap_y = ram_bar_y + 84
  draw_text(cr, 'Swap', x + 32, swap_y, 16, 0.95)
  draw_text(
    cr,
    string.format('%s / %s', format_gib_from_kib(swap_used), format_gib_from_kib(swap_total)),
    x + 338,
    swap_y,
    15,
    0.95
  )
  draw_bar(cr, x + 32, swap_y + 12, 408, 8, swap_percent)

  draw_divider(cr, x + 30, swap_y + 34, x + panel_w - 30)

  local storage_y = swap_y + 68
  draw_text(cr, 'Storage', x + 32, storage_y, 18, 1)

  local drive_y = storage_y + 28
  drive_y = drive_y + draw_drive_row(cr, x + 32, drive_y, 408, root_drive)
  drive_y = drive_y + draw_drive_row(cr, x + 32, drive_y, 408, home_drive)

  if #external_drives > 0 then
    draw_text(cr, 'External Drives', x + 32, drive_y + 4, 16, 0.95)
    drive_y = drive_y + 28

    for index = 1, math.min(3, #external_drives) do
      drive_y = drive_y + draw_drive_row(cr, x + 32, drive_y, 408, external_drives[index])
    end
  end

  local network_y = drive_y + 26
  draw_text(cr, 'Network', x + 32, network_y, 18, 1)
  draw_text(cr, ellipsize(iface, 14), x + 390, network_y, 16, 0.95)

  local network_row_y = network_y + 30
  draw_text(cr, string.format('IP %s', ip_addr ~= '' and ip_addr or 'Unavailable'), x + 32, network_row_y, 15, 0.95)
  if essid ~= '' and essid ~= iface then
    draw_text(cr, ellipsize(essid, 18), x + 290, network_row_y, 15, 0.85)
  end

  local down_y = network_row_y + 28
  draw_text(cr, string.format('Down %s/s', format_speed(downspeed, 'B')), x + 32, down_y, 15, 1)
  draw_text(cr, string.format('Total %s', totaldown ~= '' and totaldown or '0B'), x + 282, down_y, 15, 0.85)
  draw_graph(cr, x + 32, down_y + 10, 408, 34, network_graphs.rx_history, 0.98, 0.47, 0.28)

  local up_y = down_y + 56
  draw_text(cr, string.format('Up   %s/s', format_speed(upspeed, 'B')), x + 32, up_y, 15, 1)
  draw_text(cr, string.format('Total %s', totalup ~= '' and totalup or '0B'), x + 282, up_y, 15, 0.85)
  draw_graph(cr, x + 32, up_y + 10, 408, 34, network_graphs.tx_history, 0.95, 0.68, 0.46)

  if tonumber(signal) and tonumber(signal) > 0 then
    local signal_y = up_y + 56
    draw_text(cr, 'Signal', x + 32, signal_y, 15, 0.95)
    draw_text(cr, string.format('%s%%', signal), x + 405, signal_y, 15, 0.95)
    draw_bar(cr, x + 95, signal_y - 11, 280, 8, tonumber(signal))
    up_y = signal_y
  else
    up_y = up_y + 30
  end

  draw_divider(cr, x + 30, up_y + 22, x + panel_w - 30)

  local processes_y = up_y + 56
  draw_text(cr, 'Top Processes', x + 32, processes_y, 18, 1)
  draw_text(cr, 'CPU', x + 340, processes_y, 16, 0.9)
  draw_text(cr, 'MEM', x + 405, processes_y, 16, 0.9)

  local process_row_y = processes_y + 28
  local process_row_h = 24
  for index = 1, process_count do
    local name = ellipsize(conky_parse(string.format('${top name %d}', index)), 20)
    local cpu = conky_parse(string.format('${top cpu %d}', index))
    local mem = conky_parse(string.format('${top mem %d}', index))
    local current_y = process_row_y + (index - 1) * process_row_h

    draw_circle(cr, x + 35, current_y - 6, 4, 0.98, 0.47, 0.28, 1)
    draw_text(cr, name ~= '' and name or '-', x + 50, current_y, 15, 1)
    draw_text(cr, string.format('%s%%', cpu ~= '' and cpu or '0'), x + 334, current_y, 15, 1)
    draw_text(cr, string.format('%s%%', mem ~= '' and mem or '0'), x + 402, current_y, 15, 1)

    draw_divider(cr, x + 30, current_y + 12, x + panel_w - 30)
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end