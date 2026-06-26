## Arty Z7-20 constraints for cnn_accel_board_top
## UART uses external 3.3 V USB-UART adapter on PMOD JA.

## 125 MHz system clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -period 8.000 -name clk [get_ports clk]

## Reset
## SW0 = M20
## Switch ON/high means running. Switch OFF/low means reset.
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports rst_n]

## LEDs
## LED0 = busy
## LED1 = done
## LED2 = error
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports led_busy]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports led_done]
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports led_error]

## PMOD JA UART
## JA1 pin 1 = FPGA uart_rx, connect to USB-UART TX
## JA2 pin 3 = FPGA uart_tx, connect to USB-UART RX
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports uart_rx]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports uart_tx]
