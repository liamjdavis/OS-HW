.Code
start:
        # Print hello message
        la a0, hello_msg
        # Print when syscall to print in kernel

        # Exit program
        li a7, 1
        ecall

loop:   
        j loop

.Text
hello_msg: "Hello from user program!\n"