import asyncio
import os
import time
import serial
import requests
import json
from decoder import Decoder




class Noita2Serial:
    
    def __init__(self, config_path= "config.json", debug_mode = False) -> None:
        print("Loading Config")
        self.config = self.load_config(config_path)
        self.cooldown = False
        self.trigger = False
        self.time = 0
        self.intensity = 0
        self.value_change = False
        self.d = Decoder(self.config)
        self.mode = self.config["mode"]
        self.Debug = debug_mode
        if self.mode == "tens":
            self.s = serial.Serial(self.config["tens"]["serial_port"], int(self.config["tens"]["baud_rate"]), timeout=1)
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

    def send_to_pishock(self, intensity):
        c: dict = self.config["pishock"]
        payload = {
            "Username": c["Username"],
            "Name": c["Name"],
            "Code": c["Code"],
            "Intensity": f"{intensity}",
            "Duration": f"{self.time}",
            "Apikey": c["Apikey"],
            "Op": "0"
        }

        headers = {
            "Content-Type": "application/json"
        }

        try:
            response = requests.post(endpoint_url, data=json.dumps(payload), headers=headers)
            # Return or print the response text for debugging
            return response.text
        except requests.exceptions.RequestException as e:
            # Handle any request exceptions
            print(f"Request failed: {e}")
            return None

    async def pishock_loop(self):
        print("Starting Main Loop")
        old_insensity = 1
        last_time = time.time()
        while True:

            data = self.d.read_files()
            # print(f"Data found: {data}")
            if data["cleanup"]:  # check if cleanup flag has been set, if so delete flag files
                print("Cleanup request detected")
                self.d.cleanup_flags()
                continue
            self.trigger = bool(data["trigger"])  # get trigger status as bool
            self.time = data["time"]
            self.intensity = data["intensity"]
            if self.trigger:  # if trigger is set
                self.send_to_pishock()
            if old_insensity != self.intensity:  # check for intensity change
                # self.set_intensity(data["intensity"]) # register intensity change
                old_insensity = self.intensity

            await asyncio.sleep(0.02)
    
    async def serial_loop(self):
        
        print("Starting Main Loop")
        old_insensity = 1
        last_time = time.time()
        while True:
            
            data =self.d.read_files()
            #print(f"Data found: {data}")
            if data["cleanup"]: # check if cleanup flag has been set, if so delete flag files
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
            elif time.time() - last_time >=  25 * 60: #if 25 minutes have elapsed, reset timeout timer of the tens unit
                self.intensity = 0
                self.send_to_serial()
                await asyncio.sleep(1)
                self.intensity = old_insensity
                self.send_to_serial()
            await asyncio.sleep(0.02)
            
    def start(self):
        try:
            if self.mode == "tens":
                asyncio.run(self.serial_loop())
            if self.mode == "pishock":
                asyncio.run(self.pishock_loop())
        except:
            self.stop() # close serial on shut down
    
    def stop(self):
        self.s.close()
        
        
        
if __name__ == "__main__":
    main = Noita2Serial()
    print("Starting Listener")
    main.start()