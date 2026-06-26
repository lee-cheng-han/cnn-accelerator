# Host UART Script

This folder is for PC-side scripts that talk to the FPGA over UART.

Required Python package:

pip install pyserial

Example Linux command:

python3 host/send_image_uart.py --port /dev/ttyUSB0 --baud 115200

Example Windows command:

python host/send_image_uart.py --port COM5 --baud 115200
