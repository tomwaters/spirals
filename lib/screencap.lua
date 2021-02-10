local screencap = {}

local sc_recording = false
local sc_metro = metro.init()
local sc_path = ""
local sc_idx = 1

function screencap.start(script, fps)
  if sc_recording then
    screencap.stop()
  end
  
  sc_path = "/home/we/dust/" .. script .. "/" .. util.time()
  util.make_dir(sc_path)
  
  sc_recording = true
  sc_idx = 1
  sc_metro.event = snap
  sc_metro:start(1/fps)
end

function screencap.stop()
  sc_recording = false
  sc_metro:stop()
end

function screencap.is_recording()
  return sc_recording
end

function snap()
  local f = string.format("%s/%06d.png", sc_path, sc_idx)
  _norns.screen_export_png(f)
  sc_idx = sc_idx + 1
end

return screencap