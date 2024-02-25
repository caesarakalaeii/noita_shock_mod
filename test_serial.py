
from main import Noita2Serial


def loop():
    n = Noita2Serial("config.json")
    while True:
        command = input('''Type shock [time] to test shocking
Type intens [value] to check intensity calibration
Type c to close the application
''')
        c = command.split(" ")
        if c[0] == "shock":
            n.shock(int(c[1]))
        elif c[0] == "intens":
            n.set_intensity(int(c[1]))
        elif c[0] == "c":
            print("Exiting...")
            n.stop()
            break
        else:
            print("Unknown Command, please try again")
            
if __name__ == "__main__":
    loop()