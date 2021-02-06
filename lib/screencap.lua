-- quick library to take screenshots at <fps>

local screencap = {}

local sc_recording = false
local sc_metro = metro.init()
local sc_path = ""

function screencap.start(script, fps)
  if sc_recording then
    screencap.stop()
  end
  
  sc_path = "/home/we/dust/" .. script .. "/" .. util.time()
  util.make_dir(sc_path)
  
  sc_recording = true
  sc_metro.event = snap
  sc_metro:start(1/fps)
end

function screencap.stop()
  sc_recording = false
  sc_metro:stop()
end

function snap()
  local f = sc_path .. "/" .. util.time() .. ".png"
  _norns.screen_export_png(f)
end

return screencap