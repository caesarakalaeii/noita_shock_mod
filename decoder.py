import os
import json


class Decoder:
    
    def __init__(self) -> None:
        # Load configuration from JSON file
        config = self.load_config("config.json")

        # Extract folder path from the configuration
        self.folder_path = config["flag_path"]
        
        pass
    

    def load_config(self, config_file):
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config = json.load(f)
        else:
            config = {"folder_path": ""}
            self.save_config(config_file, config)
        return config

    def save_config(self, config_file, config):
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
    

    def check_folder_for_files(folder_path, prefix):
        # List all files in the folder
        files = os.listdir(folder_path)
        
        # Filter files starting with the specified prefix
        matching_files = [file for file in files if file.startswith(prefix)]
        
        return matching_files