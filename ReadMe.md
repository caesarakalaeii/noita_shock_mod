# Noita Shock Mod  
## DISCLAIMER: Use this at your own risk! You will modify a device that will induce electro shocks to you. If you're unsure if this is safe, contact your doctor! You are liable for all damages this might casue to you!
This mod enables Noita to electrocute you, whenever you get damaged.  
You will need some additional Hardware, namely an Arduino, a TENS unit, a relay board (3 relay min), some wiring, and one 1k Ohm resistor.  
If you need help setting this up, feel free to contact me on Discord (caesarlp).  
  
## Why?  
Good question.  
  
## How?  
First, you'll need to install the mod itself.  
Just place this repo in your mods folder or install it from the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3170451933).  
Then you'll need to wire up the TENS unit, with the Arduino as shown [here](https://imgur.com/a/4pTD4HI).  
Connect your Arduino using USV and flash it using the ardu.ino file.  
You can install the requirements using the requirements.txt file using your favorite Python interpreter.  
Change the Path in the config.json and set the serial port according to your system.  
Run the file main.py and start a new game with the mod enabled.  
Check if everything works as expected, put on the electrodes, and have "fun".  
  
## Common Problems:  


If I find any Problems to be commonly occurring, I'll add them here.  

  
## TODO:  
  
- More Documentation :)  
- Add shock + intensity function in ardu, no reason both can't be done at the same time  
