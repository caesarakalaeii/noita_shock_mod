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
        self.d = Decoder(config, debug_mode)
        self.Debug = debug_mode
        self.s = serial.Serial(config["serial_port"], int(config["baud_rate"]), timeout=1)
        try:
            self.s.open()
        except Exception as e:
            print(f"{e}")
            self.s.close()
            exit()
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
    
    def shock(self, time : int):
        mode = 1 << 15
        data = mode +time # shift by 8 to left to get mode bit
        if self.Debug:
            print("Shock send with data: {0:b}".format(data), "Mode being: {0:b}".format(mode), f"Time being: {time}")
            self.d.reset_trigger()
            self.cooldown = False
            
            return
        self.s.write(data.to_bytes(length=2, byteorder='big'))
        self.d.reset_trigger()
        self.cooldown = False
        
        
    def set_intensity(self, intensity : int):
        data = intensity # no shift necessary?
        if self.Debug:
            print("Intensity send with data: {0:b}".format(data), f" Intensity being: {intensity}")
            return
        self.s.write(data.to_bytes(length=2, byteorder='big'))
    
    
    async def loop(self):
        
        print("Starting Main Loop")
        old_insensity = 1
        self.set_intensity(1)
        while(True):
            data =self.d.read_files()
            print(f"Data found: {data}")
            if(data["cleanup"]): # check if cleanup flag has been set, if so delete flag files
                print("Cleanup request detected")
                self.d.cleanup_flags()
                continue
            trigger = bool(data["trigger"]) #get trigger status as bool
            if trigger and not self.cooldown: #if trigger is set
                self.cooldown = True
                self.shock(data["time"]) # send shock trigger with appropriate time
            if old_insensity != data["intensity"]: # check for intensity change
                self.set_intensity(data["intensity"]) # register intensity change
                old_insensity = data["intensity"] 
            await asyncio.sleep(0.2)
            
    def start(self):
        asyncio.run(self.loop())
    
    def stop(self):
        self.s.close()
        
        
        
if __name__ == "__main__":
    main = Noita2Serial(debug_mode=True)
    print("Starting Listener")
    main.start()