from gpiozero import Motor, PWMOutputDevice
from time import sleep

# Enable pins (ENA, ENB) for speed/PWM control
ena = PWMOutputDevice(12)
enb = PWMOutputDevice(13)

# Motor direction pins
left = Motor(17, 23)
right = Motor(27, 22)

# Set 70% PWM cap to protect JZK TT motors
SPEED = 0.7
ena.value = SPEED
enb.value = SPEED

print("Testing Motors: 70% Speed Forward")
left.forward()
right.forward()
sleep(2)

print("Testing Motors: Reverse")
left.backward()
right.backward()
sleep(2)

left.stop()
right.stop()
print("Test Complete.")