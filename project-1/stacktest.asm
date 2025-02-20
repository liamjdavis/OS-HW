.Code
start:
        # Save some values on stack
        addi sp, sp, -16

        # Store test pattern
        li t0, 0xDEAD
        sw t0, 0(sp)
        li t0, 0xBEEF
        sw t0, 4(sp)
        li t0, 0xBEAD
        sw t0, 8(sp)
        li t0, 0xDEED
        sw t0, 12(sp)

        # Load values back in reverse order to verify
        lw t1, 12(sp)
        lw t2, 8(sp)
        lw t3, 4(sp)
        lw t4, 0(sp)

        # Cleanup stack
        addi sp, sp, 16

        # Exit program
        li a7, 1
        ecall

loop:
        j loop