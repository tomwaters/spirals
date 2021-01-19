
engine.name = "PolyPerc"

MusicUtil = require "musicutil"

options = {}
options.OUTPUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"}

local midi_out_device
local midi_out_channel

local scale_names = {}
local notes = {}
local active_notes = {}

snd_sel = 1
snd_names = {"cut","gain","pw","rel","fb","rate", "pan", "delay_pan"}
snd_params = {"cutoff","gain","pw","release", "delay_feedback","delay_rate", "pan", "delay_pan"}
NUM_SND_PARAMS = #snd_params

notes_off_metro = metro.init()

local points = {}
local radius = 0
local angle = 0
local two_pi = math.pi * 2
local rads_per_note = 0

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
    
    -- nice angle values
    --angle = angle + (two_pi * 1.61803398875)
    --angle = angle + (two_pi * 0.6852)
    --angle = angle + (two_pi *0.527)
    local r = 0--math.random() / 10
    angle = angle + two_pi * (params:get("rotation") + r)

    table.insert(points, {
      x = 64 + math.cos(angle) * radius,
      y = 32 + math.sin(angle) * radius,
      r = 1
    })

    local note_idx = math.ceil((angle % two_pi) / rads_per_note)

    local note_num = notes[note_idx]
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

      --local note_off_time = 
      -- Note off timeout
      if params:get("note_length") < 4 then
        notes_off_metro:start((60 / params:get("clock_tempo") / params:get("step_div")) * (params:get("note_length") * 0.25), 1)
      end
    end
    
    redraw()
    
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

  cs_ROT = controlspec.new(0, 1, 'lin', 0, 0.61803398875, '', 0.001)
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

  math.randomseed(os.time())
  screen.aa(1)
  reset()
  clock.run(step)  
end

function reset()
  radius = 6
  angle = 0
  points = {}
end

function enc(n,d)
end

function key(n, z)
end

function redraw()
  screen.clear()

  for i=1,#points do
    screen.circle(points[i].x, points[i].y, points[i].r)
    screen.fill()
  end
  screen.update()

end
