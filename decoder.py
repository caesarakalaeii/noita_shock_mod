import array
import os
from typing import List



class Decoder:
    
    def __init__(self, config, debug_mode = False) -> None:
        

        # Extract folder path from the configuration
        self.flag_path = config["flag_path"]
        self.time_prefix = config["time_prefix"]
        self.intensity_prefix = config["intensity_prefix"]
        self.trigger_prefix = config["trigger_prefix"]
        self.mod_identifier = config["mod_ident"]
        self.cleanup_identifier = config["cleanup_identifier"]
        self.debug = debug_mode
        pass
    

    def read_files(self) -> dict:
        files = self.check_folder_for_files()

        data = {
            "trigger": 0,
            "time" : 1,
            "intensity": 1,
            "cleanup" : False
        }
        for file in files:
            s = file.split("_")
            if s[1] == "cleanup":
                data[s[1]] = True
            else:
                data[s[1]] = int(s[2])
                
                
        return data
        
        
        

    def check_folder_for_files(self)-> List[str]:
        files = os.listdir(self.flag_path)
        
        # Filter files starting with the specified prefix
        matching_files = [file for file in files if file.startswith(self.mod_identifier)]
        if self.debug:
            print(f"Files for prefix {self.mod_identifier} are {matching_files}")
        return matching_files
    
    def get_value(self, identifier):
        files = self.check_folder_for_files()
        if len(files)>1:
            raise ValueError("Too many Files detected")
        if len(files) == 0:
            return -1
        file = files[0]
        pv_pair = file.split("_")
        if self.debug:
            print(f"Value for {identifier} is {pv_pair[-1]}")
        return pv_pair[-1]
    
    def cleanup_flags(self):
        print("Cleaning up flags")
        files = self.check_folder_for_files()
        print(f"Found files: {files}")
        for file in files:
            os.remove(f"{self.flag_path}\\{file}")
            
    def reset_trigger(self):
        if self.debug:
            print("Trigger reset")
            print(f"deleting {self.flag_path}\\{self.mod_identifier}_{self.trigger_prefix}_1")
        os.remove(f"{self.flag_path}\\{self.mod_identifier}_{self.trigger_prefix}_1")
    
    
    