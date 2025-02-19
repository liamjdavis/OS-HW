        .Code
start:
        # Print hello message
        la      a0, hello_msg
        # call    print          # Use direct call instead of syscall

        # Exit program
        li      a7, 1         # EXIT_SYSCALL
        ecall                                          # System call to exit

        # Should not reach here
loop:   
        j               loop

        .Text
hello_msg:      "Hello from user program!\n"