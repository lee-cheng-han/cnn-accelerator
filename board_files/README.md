# Vendored Vivado Board Definition

`zybo-z7-20/A.0` is copied from Digilent's `vivado-boards` repository at
commit `36f34ab687b7fa9c778b779d027f3bce63b3ace9`. The files are distributed
under the MIT license included in each XML file.

Keeping the definition in this repository makes the Vivado build reproducible
without modifying the Vivado installation. The project script adds this
directory to `board.repoPaths` and selects board part
`digilentinc.com:zybo-z7-20:part0:1.2`.
