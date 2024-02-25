
import asyncio
from main import Noita2Serial


def loop():
    n = Noita2Serial("config.json")
    while True:
        command = input('''Type shock [time] to test shocking
Type intens [value] to check intensity calibration
Type c to close the application
''')
        n.time = 1
        n.intensity = 1
        c = command.split(" ")
        if c[0] == "shock":
            try:
                n.time = int(c[1])
                n.trigger = True
                n.send_to_serial()
            except FileNotFoundError as e:
                print("Flag not found, continuing")
        elif c[0] == "intens":
            n.intensity = int(c[1])
            n.send_to_serial()
        elif c[0] == "raw":
            n.trigger = bool(c[1])
            n.time = c[2]
            n.intensity = c[3]
            n.send_to_serial()
        elif c[0] == "c":
            print("Exiting...")
            n.stop()
            break
        else:
            print("Unknown Command, please try again")
            
if __name__ == "__main__":
    loop()