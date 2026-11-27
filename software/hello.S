# RV32I demo program. UART TX is a byte store to 0x10000000.
    lui  x1, 0x10000
    addi x2, x0, 72
    sb   x2, 0(x1)
    addi x2, x0, 105
    sb   x2, 0(x1)
    addi x2, x0, 10
    sb   x2, 0(x1)
1:  jal  x0, 1b
