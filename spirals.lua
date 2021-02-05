-- spirals
-- @tomw
-- llllllll.co/t/spirals
--
-- K3 toggle options
--  > E2 change option
--  > E3 change value
--
-- K1 + K3 toggle scale overlay


engine.name = "PolyPerc"

MusicUtil = require "musicutil"

options = {}
options.OUTPUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"}

local midi_out_device
local midi_out_channel

local scale_names = {}
local notes = {}
local active_notes = {}

local draw_metro = metro.init()
local notes_off_metro = metro.init()
local options_slide_metro = metro.init()
local enc_metro = metro.init()

local points = {}
local radius = 0
local angle = 0
local two_pi = math.pi * 2
local rads_per_note = 0

local alt = false
local x_offset = 0
local options_state = 0
local option_selected = 1
local option_slide_steps = 32
local option_ids = {"rotation", "root_note", "scale_mode", "step_div"}
local option_names = {"rotation", "root note", "scale mode", "step div"}
local option_vis = false

function build_scale()
  local scale = MusicUtil.SCALES[params:get("scale_mode")]
  local scale_length = #scale.intervals - 1
  
  notes = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), scale_length)
  rads_per_note = two_pi / scale_length
end

function all_notes_off()
  if (params:get("output") == 2 or params:get("output") == 3) then
    for _, a in pairs(active_notes) do
      midi_out_device:note_off(a, nil, midi_out_channel)
    end
  end
  active_notes = {}
end

function step()
  while true do
    clock.sync(1/params:get("step_div"))
    
    all_notes_off()
    
    radius = radius + 0.2
    angle = angle + two_pi * params:get("rotation")

    table.insert(points, {
      x = 64 + math.cos(angle) * radius,
      y = 32 + math.sin(angle) * radius,
      r = 1
    })

    local note_idx = math.ceil((angle % two_pi) / rads_per_note)
    local note_num = notes[util.clamp(note_idx, 1, #notes)]
    local freq = MusicUtil.note_num_to_freq(note_num)
    -- Audio engine out
    if params:get("output") == 1 or params:get("output") == 3 then
      engine.hz(freq)
    elseif params:get("output") == 4 then
      crow.output[1].volts = (note_num-60)/12
      crow.output[2].execute()
    elseif params:get("output") == 5 then
      crow.ii.jf.play_note((note_num-60)/12,5)
    end

    -- MIDI out
    if (params:get("output") == 2 or params:get("output") == 3) then
      midi_out_device:note_on(note_num, 96, midi_out_channel)
      table.insert(active_notes, note_num)

      -- Note off timeout
      if params:get("note_length") < 4 then
        notes_off_metro:start((60 / params:get("clock_tempo") / params:get("step_div")) * (params:get("note_length") * 0.25), 1)
      end
    end
    
    if #points >= 128 then
      reset()
    end
    
  end  
end

function init()
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  
  midi_out_device = midi.connect(1)
  midi_out_device.event = function() end
  
  notes_off_metro.event = all_notes_off
  enc_metro.event = encoder_delay
  options_slide_metro.event = slide_options
  
  params:add{type = "option", id = "output", name = "output",
    options = options.OUTPUT,
    action = function(value)
      all_notes_off()
      if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
    end}
  params:add{type = "number", id = "midi_out_device", name = "midi out device",
    min = 1, max = 4, default = 1,
    
    action = function(value) midi_out_device = midi.connect(value) end}
  params:add{type = "number", id = "midi_out_channel", name = "midi out channel",
    min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_off()
      midi_out_channel = value
    end}
  params:add_separator()
  
  params:add{type = "number", id = "step_div", name = "step division", min = 1, max = 16, default = 1}

  params:add{type = "option", id = "note_length", name = "note length",
    options = {"25%", "50%", "75%", "100%"},
    default = 4}
  
  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() build_scale() end}
  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end}

  cs_ROT = controlspec.new(0, 1, 'lin', 0, 0.61803398875, '', 0.01)
  params:add{type="control",id="rotation",controlspec=cs_ROT}
  
  params:add_separator()

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

  params:default()

  screen.aa(1)
  reset()
  clock.run(step)
  
  draw_metro.event = update
  draw_metro:start(1/60)
end

function update()
  redraw()
end

function reset()
  radius = 6
  points = {}
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
  -- if options are visible, e2 changes option & e3 changes value
  if options_state > 0 then
    if n == 2 then
      option_selected = util.clamp(option_selected + d, 1, #option_ids)
      option_vis = false
    elseif n == 3 then
      params:delta(option_ids[option_selected], d)
      
      -- show visualization of the value for 5secs
      option_vis = true
      enc_metro:start(5, 1)
    end
  end
end

function key(n, z)
  if n==1 then
    alt = z==1
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

function redraw()
  screen.clear()
  screen.level(15)
  screen.line_width(1)
  for i=1,#points do
    screen.circle(points[i].x + x_offset, points[i].y, points[i].r)
    screen.fill()
  end

  if options_state == 0 and option_vis then
    draw_scale()
  elseif options_state > 0 then
    draw_options()    
  end
  
  screen.update()
end

function draw_options()
  screen.font_face(24)
  screen.font_size(10)

  -- get the width of the current selected option
  local val = params:get(option_ids[option_selected])
  if option_selected == 1 then
    val = string.format("%.2f", val)
    if option_vis then
      draw_angle()
    end
  elseif option_selected == 2 then
    val = MusicUtil.note_num_to_name(val)
  elseif option_selected == 3 then
    val = scale_names[val]
    screen.font_size(8)
  elseif option_selected == 4 then
  end
  
  if option_vis and (option_selected == 2 or option_selected == 3) then
    draw_scale()
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
end

function draw_angle()
  -- show current angle
  local angle = two_pi * params:get("rotation")
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
  screen.font_size(8)

  for i=1,#notes do
    screen.level(5)
    screen.move(64 + x_offset, 32)
    screen.line(64 + x_offset + math.cos(i * rads_per_note) * 34, 32 + math.sin(i * rads_per_note) * 34)
    screen.stroke()
    
    screen.level(10)
    screen.move(64 + x_offset + math.cos((i - 0.5) * rads_per_note) * 26, 32 + math.sin((i - 0.5) * rads_per_note) * 26)
    screen.text(MusicUtil.note_num_to_name(notes[i]))
    screen.stroke()
  end
end
