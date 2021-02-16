local SpiralMidiListener = {
    devices = {}
  }
  
function SpiralMidiListener:RemoveListener(id)
    for d=1, #self.devices do
        for l=1, #self.devices[d].listeners do
        if self.devices[d].listeners[l].listener_id == id then
            table.remove(self.devices[d].listeners, 1)
            return
        end
        end
    end
    end

    function SpiralMidiListener:AddListener(id, device_id, event)
    if device_id < 1 then
        return
    end

    -- search for existing listeners for this id and remove them
    self:RemoveListener(id);

    local foundDevice = false
    for d=1, #self.devices do
        if self.devices[d].device_id == device_id then
        foundDevice = true
        table.insert(self.devices[d].listeners, { listener_id = id, event = event})
        end
    end

    if not foundDevice then
        local newDevice = {
        device_id = device_id,
        device = midi.connect(device_id),
        listeners = {{ listener_id = id, event = event } }
        }

        newDevice.device.event = function(data)
        for l=1, #newDevice.listeners do
            newDevice.listeners[l].event(data)
        end
        end
        
        table.insert(self.devices, newDevice)
    end

end


return SpiralMidiListener