import asyncio
import os
import struct
import serial
import json
from decoder import Decoder




class Noita2Serial:
    
    def __init__(self, config_path= "config.json", debug_mode = False) -> None:
        print("Loading Config")
        config = self.load_config(config_path)
        self.cooldown = False
        self.trigger = False
        self.time = 0
        self.intensity = 0
        self.value_change = False
        self.d = Decoder(config)
        self.Debug = debug_mode
        self.s = serial.Serial(config["serial_port"], int(config["baud_rate"]), timeout=1)
        try:
            self.s.open()
        except Exception as e:
            print(f"{e}")
            # exit()
        print("Config loaded")
        
        pass
    
    def load_config(self, config_file):
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config = json.load(f)
        else:
            config = {"flag_path": ""}
            self.save_config(config_file, config)
        return config

    def save_config(self, config_file, config):
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
    
    
    def send_to_serial(self):
        #s1t9999i999 -- s flag indicates shock needed, t flag set time to shock, i flag sets intensity
        s=0
        if self.trigger:
            s=1
            self.d.reset_trigger()
            self.trigger = False    
            
        t=f"{self.time}"
        while len(t)<4:
            t= "0"+t
        i=f"{self.intensity}"
        while len(i)<3:
            i = "0" + i
        data = f"s{s}t{t}i{i}"
        print(f"Data is : {data}")
        
        self.s.write(data.encode())
        
        self.value_change = False

    
    
    async def loop(self):
        
        print("Starting Main Loop")
        old_insensity = 1
        
        while(True):
            
            data =self.d.read_files()
            #print(f"Data found: {data}")
            if(data["cleanup"]): # check if cleanup flag has been set, if so delete flag files
                print("Cleanup request detected")
                self.d.cleanup_flags()
                continue
            self.trigger = bool(data["trigger"]) #get trigger status as bool
            self.time = data["time"]
            self.intensity = data["intensity"]
            if self.trigger: #if trigger is set
                self.value_change = True
                #self.shock(data["time"]) # send shock trigger with appropriate time
            if old_insensity != self.intensity: # check for intensity change
                #self.set_intensity(data["intensity"]) # register intensity change
                self.value_change = True
                old_insensity = self.intensity
            if self.value_change:
                self.value_change = False
                self.send_to_serial()
            await asyncio.sleep(0.2)
            
    def start(self):
        asyncio.run(self.loop())
    
    def stop(self):
        self.s.close()
        
        
        
if __name__ == "__main__":
    main = Noita2Serial()
    print("Starting Listener")
    main.start()