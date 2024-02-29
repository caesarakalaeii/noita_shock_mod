# Noita Shock Mod  
This mod enables Noita to electricute you, when ever you get damaged.  
You will need some addidtional Hardware, namely an Arduino, a TENS unit, a relay board (3 relay min), some wiring and one 1k Ohm resistor.  
  
  
## Why?  
Good question.  
  
## How?  
First you'll need to install the mod itself.  
You can just place this repo in your mods folder or install it from the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3170451933).  
Then you'll need to wire up the TENS unit, with the Arduino as shown [here](https://imgur.com/a/4pTD4HI).  
Connect your Arduino using USV and flash it using the ardu.ino file.  
Using your favorite python interpreter, install the requirements using the requirements.txt file.  
Change the Path in the config.json and set the serial port according to your system.  
Run the file main.py and start a new game with the mod enabled.  
Check if everything works as expected, put on the electrodes and have "fun".  
  
## Common Problems:  
  
If i find any Problems to be commonly ocurring, I'll add them here  
  
## TODO:  
  
- More Documentation :)  
- Add shock + intensity function in ardu, no reason both can't be done at the same time  