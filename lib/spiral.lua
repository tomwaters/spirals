MusicUtil = require "musicutil"
SpiralMidiListener = include("lib/spirals_midi_listener")

two_pi = math.pi * 2
options = {
  OUTPUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"},
  PLAY_MODE = {"note", "chord"}
}

Spiral = {}
Spiral.__index = Spiral
  
function Spiral:new(id)
  local o = {
    id = id,
    playing = false,

    output = 0,
    midi_out_device = midi.connect(1),
    midi_out_channel = 0,
    mx_instrument = "",

    notes = {},
    active_notes = {},
    
    radius = 6,
    angle = 0,
    rotation = 0,
    points = {},
    rads_per_note = 0,
    
    locked = false,
    lock_step = 0,

    active_notes = {},
    notes_off_metro = metro.init()
  }
  o.notes_off_metro.event = function() o:all_notes_off() end

  setmetatable(o, Spiral)
  
  o:reset()
  o:init_params()
  
  clock.run(Spiral.step, o)
  
  return o
end

function Spiral:reset()
  self.radius = 6
  self.points = {}
end

function Spiral:init_params()
  local param_count = mxsamples == nil and 15 or 16
  
  params:add_group("spiral "..self.id, param_count)
  
  params:add{type = "option", id = self.id.."_output", name = "output",
    options = options.OUTPUT,
    action = function(value)
      self:all_notes_off()

      if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
      self.output = value
    end
  }
  
  if mxsamples ~= nil then
    params:add{type = "option", id = self.id.."_mxsamples_instrument", name = "mx inst.", options = mxsamples_instruments, 
      action = function(value)
        self:all_notes_off()
        self.mx_instrument = mxsamples_instruments[value]
      end
    }
  end
  
  params:add{type = "number", id = self.id.."midi_out_device", name = "midi out device",
    min = 1, max = 4, default = 1, action = function(value)
      self:all_notes_off()
      self.midi_out_device = midi.connect(value)
    end
  }
    
  params:add{type = "number", id = self.id.."_midi_out_channel", name = "midi out channel",
    min = 1, max = 16, default = 1,
    action = function(value)
      self:all_notes_off()
      midi_out_channel = value
    end}

  params:add{type = "number", id = self.id.."_midi_in_device", name = "midi in device",
    min = 1, max = 4, default = 1, action = function(value) 
      SpiralMidiListener:AddListener(self.id, value, function(data) self:midi_event(data) end)
    end
  }
  
  params:add{type = "number", id = self.id.."_midi_in_channel", name = "midi in channel",
    min = 1, max = 16, default = 1}  
    
  params:add{type = "option", id = self.id.."_note_length", name = "note length",
    options = {"25%", "50%", "75%", "100%"},
    default = 4}

  params:add{type = "number", id = self.id.."_velocity", name = "velocity", min = 1, max = 127, default = 100}    
    
  params:add{type = "number", id = self.id.."_step_div", name = "step division", min = 1, max = 16, default = 1}

  params:add{type = "option", id = self.id.."_scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() self:build_scale() end}
  params:add{type = "number", id = self.id.."_root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() self:build_scale() end}

  cs_ROT = controlspec.new(0, 1, 'lin', 0, 0.61803398875, '', 0.01)
  params:add{type = "control", id = self.id.."_rotation", name = "rotation", controlspec = cs_ROT, 
    action=function(x) self.rotation = x end}
  
  cs_ROTFOAMT = controlspec.new(0, 1, 'lin', 0, 0, '', 0.01)
  params:add{type = "control", id = self.id.."_rot_lfo_amt", name = "lfo amount", controlspec = cs_ROTFOAMT}
  
  --cs_ROTFOFQ = controlspec.new(0, 10, 'lin', 0.001, 0.001, 'Hz', 0.001)
  params:add{type = "control", id = self.id.."_rot_lfo_fq", name = "lfo freq", controlspec = controlspec.LOFREQ}  
  
  params:add{type = "number", id = self.id.."_lock_steps", name = "lock steps", min = 1, max = 16, default = 4}

  params:add{type = "option", id = self.id.."_play_mode", name = "play mode",
    options = options.PLAY_MODE, action = function(value) end}
end
  
function Spiral:get_param(idx)
  return params:get(self.id .. "_" .. idx)
end

function Spiral:get_param_string(idx)
  return params:string(self.id .. "_" .. idx)
end

function Spiral:set_param(idx, val)
  params:set(self.id .. "_" .. idx, val)
end

function Spiral:set_param_delta(idx, val)
  params:delta(self.id .. "_" .. idx, val)
end

function Spiral:build_scale()
  local scale = MusicUtil.SCALES[self:get_param("scale_mode")]
  local scale_length = #scale.intervals - 1
  
  self.notes = MusicUtil.generate_scale_of_length(self:get_param("root_note"), self:get_param("scale_mode"), scale_length + 4)
  self.rads_per_note = two_pi / scale_length
end

function Spiral:midi_event(data)
  local msg = midi.to_msg(data)
  local channel_param = self:get_param("midi_in_channel")
  if msg.ch == channel_param then
    -- Note off
    if msg.type == "note_off" then
      self:set_param("root_note", msg.note)
    end
  end
end

function Spiral:all_notes_off()
  for _, a in pairs(self.active_notes) do
    if self.output == 2 or self.output == 3 then
      self.midi_out_device:note_off(a, nil, self.midi_out_channel)
    end
    
    if (self.output == 1 or self.output == 3) and engine.name == "MxSamples" then
      skeys:off({name=self.mx_instrument, midi=a})
    end
  end
  self.active_notes = {}
end

function Spiral:reset_lock()
  self.lock_step = #self.points - self:get_param("lock_steps") + 1
  if self.lock_step < 1 then
    self.lock_step = 1
  end
end

function Spiral:step()
  while true do
    clock.sync(1/self:get_param("step_div"))
    self:all_notes_off()
    
    if self.playing then
      local note_angle = 0
      if self.locked then
        local deltaX = self.points[self.lock_step].x - 64
        local deltaY = self.points[self.lock_step].y - 32
        note_angle = math.atan2(deltaY, deltaX)
  
        self.lock_step = self.lock_step + 1
        if self.lock_step > #self.points then
          self:reset_lock()
        end
      else
        self.rotation = self:get_param("rotation")
        local lfo_amount = self:get_param("rot_lfo_amt")
        if lfo_amount > 0 then
          local lfo_rate = self:get_param("rot_lfo_fq")
          self.rotation = self.rotation + math.sin(two_pi * lfo_rate * util.time()) * lfo_amount
        end
        
        self.radius = self.radius + 0.2
        self.angle = self.angle + two_pi * self.rotation
        
        table.insert(self.points, {
          x = 64 + math.cos(self.angle) * self.radius,
          y = 32 + math.sin(self.angle) * self.radius,
          r = 1
        })
        note_angle = self.angle
      end
  
      local note_idx = math.ceil((note_angle % two_pi) / self.rads_per_note)
      local note_num = self.notes[util.clamp(note_idx, 1, #self.notes)]
      local freq = MusicUtil.note_num_to_freq(note_num)
      
      local note_num3 = self.notes[note_idx + 2]
      local freq_3 = MusicUtil.note_num_to_freq(note_num3)
      local note_num5 = self.notes[note_idx + 4]
      local freq_5 = MusicUtil.note_num_to_freq(note_num5)
      local note_off = false
      local velocity = self:get_param("velocity")

      -- Audio engine out
      if self.output == 1 or self.output == 3 then
        -- Mx.Samples
        if audio_engines[params:get("audio_engine")] == "MxSamples" then
          skeys:on({name=self.mx_instrument, midi=note_num, velocity=velocity})
          -- chord mode
          if self:get_param("play_mode") == 2 then
            skeys:on({name=self.mx_instrument, midi=note_num3, velocity=velocity})
            skeys:on({name=self.mx_instrument, midi=note_num5, velocity=velocity})
          end
          note_off = true
        else
          engine.hz(freq)
          -- chord mode
          if self:get_param("play_mode") == 2 then
            engine.hz(freq_3)
            engine.hz(freq_5)
          end
        end
      elseif self.output == 4 then
        crow.output[1].volts = (note_num-60)/12
        crow.output[2].execute()
      elseif self.output == 5 then
        crow.ii.jf.play_note((note_num-60)/12,5)
      end
  
      -- MIDI out
      if (self.output == 2 or self.output == 3) then
        self.midi_out_device:note_on(note_num, velocity, self:get_param("midi_out_channel"))
        table.insert(self.active_notes, note_num)
        
        -- chord mode
        if self:get_param("play_mode") == 2 then
          self.midi_out_device:note_on(note_num3, velocity, self:get_param("midi_out_channel"))
          table.insert(self.active_notes, note_num3)
          
          self.midi_out_device:note_on(note_num5, velocity, self:get_param("midi_out_channel"))
          table.insert(self.active_notes, note_num5)
        end
  
        note_off = true
      end
      
      -- Note off timeout
      if note_off and self:get_param("note_length") < 4 then
        self.notes_off_metro:start((60 / params:get("clock_tempo") / self:get_param("step_div")) * (self:get_param("note_length") * 0.25), 1)
      end
      
      if #self.points >= 128 then
        self:reset()
      end
    
    end
  end

end

return Spiral