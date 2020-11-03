DDC Test application for Ultibo
===============================

This application tests the additional BSC2 I2C bus on the Raspberry Pi with
Ultibo, which is not normally accessible as it is supposed to be privately owned
by the GPU. However, the GPU does not actually access this bus once the system
has booted (as far as I can tell from various forum postings), and it seems
that most linux installations will expose it as an I2C device in /dev when you
plug in a monitor, and therefore it is reasonably safe to use it. It is certainly
safe enough to read the EDID on address 50, which is what this application does.

To relate this demo to Linux (including Raspbian), see the ddcutil command.

Copmiling the app
-----------------
To be able to compile this application you must change the Ultibo core to enable access to the BSC2 device. See the Ultibo forum for details on how to do this. Don't forget to rebuild the core after making the change!

In this repo I have included the BCM2708.pas file I used to add support for the Pi 1 Model B (and zero, implicitly). Search for "BSC2" and "I2C2" in the file to see the changes.
