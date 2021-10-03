-- spirals
-- @tomw
-- llllllll.co/t/spirals
--
-- E1 change spiral
-- K2 play / stop spiral
-- K3 toggle options
--  > E2 change option
--  > E3 change value
-- K1 + K2 lock sequence
-- K1 + K3 toggle scale overlay

engine.name = "PolyPerc"

MusicUtil = require "musicutil"
local Spiral = include("lib/spiral")

local grid_menu_row = 8
local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/midigrid" or grid
g = grid.connect()
  
scale_names = {}
audio_engines = {"PolyPerc"}
mxsamples_instruments = {}

local draw_metro = metro.init()
local options_slide_metro = metro.init()
local enc_metro = metro.init()

local alt = false
local x_offset = 0
local options_state = 0
local option_selected = 1
local option_slide_steps = 32
local option_ids = {"rotation", "rot_lfo_amt", "rot_lfo_fq", "lock_steps", "root_note", "scale_mode", "play_mode", "step_div", "rests"}
local option_names = {"rotation", "lfo amount", "lfo freq", "lock steps", "root note", "scale mode", "play mode", "step div", "rests"}
local option_vis = false

local spirals = {}
current_spiral = 0

function init()
  if libInstalled("mx.samples/lib/mx.samples") then
    mxsamples = include("mx.samples/lib/mx.samples")
    skeys = mxsamples:new()
    mxsamples_instruments = skeys:list_instruments()
    if #mxsamples_instruments > 0 then
      table.insert(audio_engines, "MxSamples")
    end
  end

  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  
  enc_metro.event = encoder_delay
  options_slide_metro.event = slide_options

  -- add polyperc params
  params:add_group("PolyPerc", 6)
  cs_AMP = controlspec.new(0,1,'lin',0,0.5,'')
  params:add{type="control",id="amp",controlspec=cs_AMP,
    action=function(x) engine.amp(x) end}

  cs_PW = controlspec.new(0,100,'lin',0,50,'%')
  params:add{type="control",id="pw",controlspec=cs_PW,
    action=function(x) engine.pw(x/100) end}

  cs_REL = controlspec.new(0.1,3.2,'lin',0,1.2,'s')
  params:add{type="control",id="release",controlspec=cs_REL,
    action=function(x) engine.release(x) end}

  cs_CUT = controlspec.new(50,5000,'exp',0,800,'hz')
  params:add{type="control",id="cutoff",controlspec=cs_CUT,
    action=function(x) engine.cutoff(x) end}

  cs_GAIN = controlspec.new(0,4,'lin',0,1,'')
  params:add{type="control",id="gain",controlspec=cs_GAIN,
    action=function(x) engine.gain(x) end}
  
  cs_PAN = controlspec.new(-1,1, 'lin',0,0,'')
  params:add{type="control",id="pan",controlspec=cs_PAN,
    action=function(x) engine.pan(x) end}
  
  params:add{type = "option", id = "audio_engine", name = "audio engine",
    options = audio_engines,
    action = function(value)
      if audio_engines[value] ~= engine.name then
        -- remember who was playing and stop play
        local spiral_state = {}
        for s = 1, #spirals do
          table.insert(spiral_state, spirals[s].playing)
          spirals[s].playing = false
          spirals[s]:all_notes_off()
        end
        
        -- change engine and resume play when done
        engine.load(audio_engines[value], function()
          if audio_engines[value] == "MxSamples" then
            mxSamplesInit()
          end
          
          for s = 1, #spirals do
            spirals[s].playing = spiral_state[s]
          end
        end
      )
      end
    end
  }
  
  -- add spirals and their params
  table.insert(spirals, Spiral:new(1))
  table.insert(spirals, Spiral:new(2))
  table.insert(spirals, Spiral:new(3))
  table.insert(spirals, Spiral:new(4))
  spirals[1].playing = true
  current_spiral = 1
      
  params:default()

  screen.aa(1)

  draw_metro.event = update
  draw_metro:start(1/60)
  
  if g then
    grid_menu_row = g.rows
    grid_draw_menu()
  end
  
end

function mxSamplesInit()
  skeys:reset()
end

function libInstalled(file)
  local dirs = {norns.state.path, _path.code, _path.extn}
  for _, dir in ipairs(dirs) do
    local p = dir..file..'.lua'
    if util.file_exists(p) then
      return true
    end
  end
  return false
end

function cleanup()
  for s = 1, #spirals do
    spirals[s]:all_notes_off()
  end
end

function update()
  redraw()
end

function encoder_delay()
  option_vis = false
end

function slide_options()
  if options_state == 1 then
    x_offset = x_offset - 1
  else
    x_offset = x_offset + 1
    if x_offset >= 0 then
      options_state = 0
    end
  end
end

function enc(n, d)
  if n == 1 then
    select_spiral(util.clamp(current_spiral + d, 1, #spirals))
    grid_draw_menu()
  elseif options_state > 0 then
    -- if options are visible, e2 changes option & e3 changes value
    if n == 2 then
      option_selected = util.clamp(option_selected + d, 1, #option_ids)
      option_vis = false
    elseif n == 3 then
      spirals[current_spiral]:set_param_delta(option_ids[option_selected], d)
      
      -- show visualization of the value for 5secs
      option_vis = true
      enc_metro:start(5, 1)
    end
  end
end

function key(n, z)
  if n==1 then
    alt = z==1
  elseif n == 2 and z == 1 then
    if alt then
      spirals[current_spiral]:toggle_lock()
    else
      spirals[current_spiral].playing = not spirals[current_spiral].playing
    end
    grid_draw_menu()
  elseif n == 3 and z == 1 then
    -- if options aren't visible and alt is held then show the scale overlay, otherwise toggle options if not currently moving
    if alt and options_state == 0 then
      option_vis = not option_vis
      enc_metro:stop()
    elseif x_offset == 0 or x_offset == 0 - option_slide_steps then
      option_vis = false
      options_state = options_state == 1 and 2 or 1
      options_slide_metro:start(1/60, option_slide_steps)
    end
  end
end

function select_spiral(n)
  current_spiral = n
  spirals[current_spiral]:draw_grid()
end

local grid_held_keys = {}
g.key = function(x, y, z)
  -- grid menu buttons
  if z == 1 and y == grid_menu_row then
    if x <= #spirals then
      select_spiral(x)
    elseif x == 7 then
      spirals[current_spiral]:toggle_lock()
    elseif x == 8 then
      spirals[current_spiral].playing = not spirals[current_spiral].playing
    end
    grid_draw_menu()
  end

  -- grid lock buttons
  if y < g.rows - 1 then
    local val = ((y - 1) * g.cols) + x
    
    if z == 1 then
      table.insert(grid_held_keys, val)
      if #grid_held_keys > 1 then
        -- get max min, set lock
        local min = math.min(table.unpack(grid_held_keys))
        local max = math.max(table.unpack(grid_held_keys))
        
        if max > #spirals[current_spiral].points then
          return
        end
        
        local cells = g.rows * (g.cols - 2)
        if #spirals[current_spiral].points > cells then
          min = #spirals[current_spiral].points - (cells - min)
          max = #spirals[current_spiral].points - (cells - max)
        end
        spirals[current_spiral]:lock(min, max)
        grid_draw_menu()
        grid_held_keys = {}
      end
    else
      for i, n in pairs(grid_held_keys) do
        if n == val then
          table.remove(grid_held_keys, i)
          break
        end
      end
    end
  end
  
end

function grid_draw_menu()
  if g then
    for s=1, #spirals do
      g:led(s, grid_menu_row, s==current_spiral and 15 or 10)
    end
    
    local spiral = spirals[current_spiral]
    g:led(g.cols - 1, grid_menu_row, spiral.locked and 15 or 10)
    g:led(g.cols, grid_menu_row, spiral.playing and 15 or 10)
    
    g:refresh()
  end
end

function redraw()
  local spiral = spirals[current_spiral]
  
  screen.clear()
  screen.font_face(24)
  screen.font_size(10)
  screen.level(15)
  
  screen.move(0, 8)
  screen.text(current_spiral)
  
  -- draw play/pause icon
  if spiral.playing then
    screen.move(10, 7)
    screen.line(10, 1)
    screen.line(16, 4)
    screen.line(10, 7)
  else
    screen.rect(10, 1, 6, 6)
  end
  screen.fill()
  
  -- draw lock icon
  if spiral.locked then
    screen.line_width(1)
    screen.aa(0)
    screen.rect(20, 4, 6, 4)
    screen.move(21, 4)
    screen.line(21, 1)
    screen.line(25, 1)
    screen.line(25, 4)
    screen.stroke()
    screen.rect(22, 5, 1, 2)
    screen.fill()
    screen.aa(1)
  end

  if options_state == 0 and option_vis then
    draw_scale()
  elseif options_state > 0 then
    draw_options()    
  end

  screen.level(15)
  screen.line_width(1)
  for i=1,#spiral.points do
    screen.circle(spiral.points[i].x + x_offset, spiral.points[i].y, spiral.points[i].r)
    screen.fill()
  end
  
  screen.update()
end

function draw_options()
  -- get the width of the current selected option
  local val = spirals[current_spiral]:get_param_string(option_ids[option_selected])
  if option_selected == 1 and not option_vis then
    val = string.format("%.2f", spirals[current_spiral].rotation)
  end
    
  if option_selected == 6 then
    screen.font_size(8)
  end
  local val_width = screen.text_extents(val)
  
  -- figure out the options width
  local opt_width = val_width
  if opt_width < 64 then
    opt_width = 64
  end
  
  -- current x of the options (changes when popping in and out)
  local x_opt_offset = 128 + opt_width + (x_offset * (opt_width / option_slide_steps))
  
  -- draw the value
  screen.move(x_opt_offset - val_width - 4, 30)
  screen.text(val)
  screen.stroke()
  
  -- draw the option label
  screen.font_size(10)
  local label = option_names[option_selected]
  local label_width = screen.text_extents(label)
  screen.move(x_opt_offset - label_width - 4, 10)
  screen.text(label)
  screen.stroke()
  
  -- option hints
  screen.move(76 + option_slide_steps + x_offset, 64)
  screen.text("< >")
  screen.stroke()
  screen.move(112 + option_slide_steps + x_offset, 64)
  screen.text("-/+")
  screen.stroke()
  
  -- options visualizations
  if option_vis then
    if option_selected ==1 then
      draw_angle()
    elseif option_selected == 5 or option_selected == 6 or option_selected == 9 then
      draw_scale()
    end
  end  
end

function draw_angle()
  -- show current angle
  local r = spirals[current_spiral].rotation
  if option_vis then
    r = spirals[current_spiral]:get_param("rotation")
  end
  
  local angle = two_pi * r
  screen.arc(64 + x_offset, 32, 30, 0, angle)
  screen.stroke()
  
  screen.line_width(2)
  screen.move(90 + x_offset, 32)
  screen.line(98 + x_offset, 32)
  screen.stroke()
  
  screen.move(64 + x_offset + math.cos(angle) * 26, 32 + math.sin(angle) * 26)
  screen.line(64 + x_offset + math.cos(angle) * 34, 32 + math.sin(angle) * 34)
  screen.stroke()
end

function draw_scale()
  local spiral = spirals[current_spiral]

  screen.font_size(8)
  for i=1,#spiral.notes - 4 do
    screen.level(2)
    screen.move(64 + x_offset, 32)
    screen.line(64 + x_offset + math.cos(i * spiral.rads_per_note) * 34, 32 + math.sin(i * spiral.rads_per_note) * 34)
    screen.stroke()
    
    if spiral.notes[i] > -1 then
      screen.level(15)
      screen.move(64 + x_offset + math.cos((i - 0.5) * spiral.rads_per_note) * 26, 32 + math.sin((i - 0.5) * spiral.rads_per_note) * 26)
      screen.text(MusicUtil.note_num_to_name(spiral.notes[i]))
      screen.stroke()
    end
  end
end