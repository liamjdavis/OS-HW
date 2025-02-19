.Code
start:
        # Save some values on stack
        addi sp, sp, -16      # Allocate space for 4 words
        
        # Store test pattern
        li t0, 0xDEAD
        sw t0, 0(sp)          # Store 0xDEAD
        li t0, 0xBEEF
        sw t0, 4(sp)          # Store 0xBEEF
        li t0, 0xCAFE
        sw t0, 8(sp)          # Store 0xCAFE
        li t0, 0xBABE
        sw t0, 12(sp)         # Store 0xBABE

        # Load values back in reverse order to verify
        lw t1, 12(sp)         # Should be 0xBABE
        lw t2, 8(sp)          # Should be 0xCAFE
        lw t3, 4(sp)          # Should be 0xBEEF
        lw t4, 0(sp)          # Should be 0xDEAD

        # Cleanup stack
        addi sp, sp, 16

        # Exit program
        li a7, 1              # EXIT_SYSCALL
        ecall

        # Should not reach here
loop:   
        j loop