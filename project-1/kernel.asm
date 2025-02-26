### ================================================================================================================================
### kernel.asm
### Scott F. Kaplan -- sfkaplan@amherst.edu
###
### The assembly core that perform the basic initialization of the kernel, bootstrapping the installation of trap handlers and
### configuring the kernel's memory space.
###
### v.2025-02-10 : RISC-V (Fivish)
### ================================================================================================================================


### ================================================================================================================================
	.Code
### ================================================================================================================================



### ================================================================================================================================
### Entry point.

__start:	
	## Find RAM.  Start the search at the beginning of the device table.
	lw		t0,		device_table_base			# [t0] dt_current = &device_table[0]
	lw		s0,		none_device_code			# [s0] none_device_code
	lw		s1,		RAM_device_code				# [s1] RAM_device_code
	
RAM_search_loop_top:

	## End the search with failure if we've reached the end of the table without finding RAM.
	lw		t1,		0(t0) 					# [t1] device_code = dt_current->type_code
	beq		t1,		s0,		RAM_search_failure 	# if (device_code == none_device_code)

	## If this entry is RAM, then end the loop successfully.
	beq		t1,		s1,		RAM_found 		# if (device_code == RAM_device_code)

	## This entry is not RAM, so advance to the next entry.
	addi		t0,		t0,		12 			# [t0] dt_current += dt_entry_size
	j		RAM_search_loop_top

RAM_search_failure:

	## Record a code to indicate the error, and then halt.
	lw		a0,		kernel_error_RAM_not_found
	halt

RAM_found:
	
	## RAM has been found.  If it is big enough, create a stack.
	lw		t1,		4(t0) 					# [t1] RAM_base  = dt_RAM->base
	lw		t2,		8(t0)					# [t2] RAM_limit = dt_RAM->limit
	sub		t0,		t2,		t1			# [t0] |RAM| = RAM_limit - RAM_base
	lw		t3,		min_RAM					# [t3] |min_RAM|
	blt		t0,		t3,		RAM_too_small		# if (|RAM| < |min_RAM|) ...
	lw		t3,		kernel_size				# [t3] ksize
	add		sp,		t1,		t3			# [sp] klimit = RAM_base + ksize : new stack
	mv		fp,		sp					# Initialize fp

	## Copy the RAM and kernel bases and limits to statically allocated spaces.
	sw		t1,		RAM_base,	t6
	sw		t2,		RAM_limit,	t6
	sw		t1,		kernel_base,	t6	
	sw		sp,		kernel_limit,	t6

	## With the stack initialized, call main() to begin booting proper.
	addi		sp,		sp,		-8			# Push pfp / ra
	sw		fp,		0(sp)					# Preserve fp
	mv		fp,		sp					# Update fp
	call		main

	## Wrap up and halt.  Termination code has already been returned by main() in a0.
	lw		fp,		0(sp)					# Restore fp
	addi		sp,		sp,		8			# Pop pfp / ra
	halt

RAM_too_small:
	## Set an error code and halt.
	lw		a0,		kernel_error_small_RAM
	halt
### ================================================================================================================================



### ================================================================================================================================	
### Procedure: find_device
### Parameters:
###   [a0]: type     -- The device type to find.
###   [a1]: instance -- The instance of the given device type to find (e.g., the 3rd ROM).
### Caller preserved registers:
###   [s0/fp + 0]: pfp
### Return address (preserved if needed):
###   [s0/fp + 4]: pra
### Return value:
###   [a0]: If found, a pointer to the correct device table entry, otherwise, null.
### Locals:
###   [t0]: current_ptr  -- The current pointer into the device table.
###   [t1]: current_type -- The current entry's device type.
###   [t2]: none_type    -- The null device type code.

find_device:

	## Prologue: Initialize the locals.
	lw		t0,		device_table_base				# current_ptr = dt_base
	lw		t2,		none_device_code				# none_type
	
find_device_loop_top:

	## End the search with failure if we've reached the end of the table without finding the device.
	lw		t1,		0(t0)						# current_type = current_ptr->type
	beq		t1,		t2,		find_device_loop_failure	# while (current_type == none_type) {

	## If this entry matches the device type we seek, then decrement the instance count.  If the instance count hits zero, then
	## the search ends successfully.
	bne		t1,		a0,		find_device_continue_loop	#   if (current_type == type) {
	addi		a1,		a1,		-1				#     instance--
	beqz		a1,		find_device_loop_success			#     if (instance == 0) break }
	
find_device_continue_loop:	

	## Advance to the next entry.
	addi		t0,		t0,		12				#   current_ptr++
	j		find_device_loop_top						# }

find_device_loop_failure:

	## Set the return value to a null pointer.
	li		a0,		0						# rv = null
	j		find_device_return

find_device_loop_success:

	## Set the return pointer into the device table that currently points to the given iteration of the given type.
	mv		a0,		t0						# rv = current_ptr
	## Fall through...
	
find_device_return:

	## Epilogue: Return
	ret
### ================================================================================================================================



### ================================================================================================================================
### Procedure: print
### Preserved registers:
###   [fp + 0]: pfp
### Parameters:
###   [a0]: str_ptr -- A pointer to the beginning of a null-terminated string.
### Return address:
###   [ra / fp + 4]
### Return value:
###   <none>
### Preserved registers:
###   [fp -  4]: a0
###   [fp -  8]: s1
###   [fp - 12]: s2
###   [fp - 16]: s3
###   [fp - 20]: s4
###   [fp - 24]: s5
###   [fp - 28]: s6
### Locals:
###   [s1]: current_ptr        -- Pointer to the current position in the string.
###   [s2]: console_buffer_end -- The console buffer's limit.
###   [s3]: cursor_column      -- The current cursor column (always on the bottom row).
###   [s4]: newline_char       -- A copy of the newline character.
###   [s5]: cursor_char        -- A copy of the cursor character.
###   [s6]: console_width      -- The console's width.
	
print:

	## Callee prologue: Push preserved registers.
	sw		ra,		4(fp)					# Preserve ra
	addi		sp,		sp,		-28			# Push & preserve a0 / s[1-6]
	sw		a0,		-4(fp)
	sw		s1,		-8(fp)
	sw		s2,		-12(fp)
	sw		s3,		-16(fp)
	sw		s4,		-20(fp)
	sw		s5,		-24(fp)
	sw		s6,		-28(fp)

	## Initialize locals.
	mv		s1,		a0					# current_ptr = str_ptr
	lw		s2,		console_limit				# console_limit
	addi		s2,		s2,		-4			# console_buffer_end = console_limit - |word|
										#   (offset portal)
	lw		s3,		cursor_column				# cursor_column
	lb		s4,		newline_char
	lb		s5,		cursor_char
	lw		s6,		console_width

	## Loop through the characters of the given string until the terminating null character is found.
loop_top:
	lb		t0,		0(s1)					# [t0] current_char = *current_ptr

	## The loop should end if this is a null character
	beqz		t0,		loop_end

	## Scroll without copying the character if this is a newline.
	beq		t0,		s4,		_print_scroll_call

	## Assume that the cursor is in a valid location.  Copy the current character into it.
	sub		t1,		s2,		s6			# [t0] = console[limit] - width
	add		t1,		t1,		s3			#      = console[limit] - width + cursor_column
	sb		t0,		0(t1)					# Display current char @t1.
	
	## Advance the cursor, scrolling if necessary.
	addi		s3,		s3,		1			# cursor_column++
	blt		s3,		s6,		_print_scroll_end       # Skip scrolling if cursor_column < width

_print_scroll_call:
	##   Caller prologue...
	sw		s3,		cursor_column,	t6			# Store cursor_column
	addi		sp,		sp,		-8			# Push pfp / ra
	sw		fp,		0(sp)					# Preserve fp
	mv		fp,		sp					# Move fp
	##   Call...
	call		scroll_console
	##   Caller epilogue...
	lw		fp,		0(sp)		   			# Restore fp
	addi		sp,		sp,		8			# Pop pfp / ra
	lw		s3,		cursor_column				# Restore cursor_column, which may have changed

_print_scroll_end:
	## Place the cursor character in its new position.
	sub		t1,		s2,		s6			# [t1] = console[limit] - width
	add		t1,		t1,		s3			#      = console[limit] - width + cursor_column
	sb		s5,		0(t1)					# Display cursor char @t1.
	
	## Iterate by advancing to the next character in the string.
	addi		s1,		s1,		1
	j		loop_top

loop_end:
	## Callee Epilogue...
	##   Store cursor_column back into statics.
	sw		s3,		cursor_column,	t6			# Store cursor_column (static)
	##   Pop and restore preserved registers, then return.
	lw		s6,		-28(fp)					# Restore & pop a0 / s[1-6]
	lw		s5,		-24(fp)
	lw		s4,		-20(fp)
	lw		s3,		-16(fp)
	lw		s2,		-12(fp)
	lw		s1,		-8(fp)
	lw		a0,		-4(fp)
	addi		sp,		sp,		28
	lw		ra,		4(fp)					# Restore ra
	ret
### ================================================================================================================================

	

### ================================================================================================================================
### Procedure: scroll_console
### Description: Scroll the console and reset the cursor at the 0th column.
### Preserved frame pointer:
###   [fp + 0]: pfp
### Parameters:
###   <none>
### Return address:
###   [fp + 4]
### Return value:
###   <none>
### Locals:
###   [t0]: console_buffer_end / console_offset_ptr
###   [t1]: console_width
###   [t2]: console_buffer_begin
###   [t3]: cursor_column
###   [t4]: screen_size	
	
scroll_console:

	## Initialize locals.
	lw		t2,		console_base				# console_buffer_begin = console_base
	lw		t0,		console_limit				# console_limit
	addi		t0,		t0,		-4			# console_buffer_end = console_limit - |word|
	                                                                        #   (offset portal)
	lw		t1,		console_width				# console_width
	lw		t3,		cursor_column				# cursor_column
	lw		t4,		console_height				# t4 = console_height
	mul		t4,		t1,		t4			# screen_size = console_width * console_height
	
	## Blank the top line.
	lw		t5,		device_table_base       	        # t5 = dt_controller_ptr
	lw		t5,		8(t5)					#    = dt_controller_ptr->limit
	addi		t5,		t5,		-12			# DMA_portal_ptr = dt_controller_ptr->limit - 3*|word|
	la		t6,		blank_line				# t6 = &blank_line
	sw		t6,		0(t5)					# DMA_portal_ptr->src = &blank_line
	sw		t2,		4(t5)					# DMA_portal_ptr->dst = console_buffer_begin
	sw		t1,		8(t5)					# DMA_portal_ptr->len = console_width

	## Clear the cursor if it isn't off the end of the line.
	beq		t1,		t3,		_scroll_console_update_offset	# Skip if width == cursor_column
	sub		t5,		t0,		t1			# t5 = console_buffer_end - width
	add		t5,		t5,		t3			#    = console_buffer_end - width + cursor_column
	lb		t6,		space_char
	sb		t6,		0(t5)

	## Update the offset, wrapping around if needed.
_scroll_console_update_offset:
	lw		t6,		0(t0)					# [t6] offset
	add		t6,		t6,		t1			# offset += column_width
	rem		t6,		t6,		t4			# offset %= screen_size
	sw		t6,		0(t0)					# Set offset in console
	
	## Reset the cursor at the start of the new line.
	li		t3,		0					# cursor_column = 0
	sw		t3,		cursor_column,	t6			# Store cursor_column
	lb		t6,		cursor_char				# cursor_char
	sub		t5,		t0,		t1			# t5 = console_buffer_end - width (cursor_column == 0)	
	sb		t6,		0(t5)
	
	## Return.
	ret
### ================================================================================================================================



### ================================================================================================================================
### Procedure: default_handler

default_handler:
	# Preserve registers
	addi sp, sp, -8
	sw ra, 4(sp)
	sw fp, 0(sp)
	mv fp, sp

	# Print interrupt message
	la a0, interrupt_msg
	call print

	# Restore registers
	lw ra, 4(fp)
	lw fp, 0(sp)
	addi sp, sp, 8

	lw		a0,		kernel_error_unmanaged_interrupt

	# Enter supervisor mode and halt
    li t0, 0x1
    csrc md, t1
    csrs md, t0
	halt


### Procedure: system call handler
system_call_handler:
	# Preserve registers
	addi sp, sp, -8
	sw ra, 4(sp)
	sw fp, 0(sp)
	mv fp, sp

	# Check if EXIT_SYSCALL
	li t0, EXIT_SYSCALL
	beq a7, t0, handle_exit

	# Unknown syscall
	la a0, unknown_syscall_msg
	call print
	j syscall_return

handle_exit:
	la a0, exit_msg
	call print

syscall_return:
	# Restore registers
	lw ra, 4(fp)
	lw fp, 0(sp)
	addi sp, sp, 8

	lw a0, kernel_error_unmanaged_interrupt

	# Enter supervisor mode and halt
    li t0, 0x1
    csrc md, t1
    csrs md, t0
	halt

### ================================================================================================================================


	
### ================================================================================================================================
### Procedure: init_trap_table
### Caller preserved registers:	
###   [fp + 0]:      pfp
###   [ra / fp + 4]: pra
### Parameters:
###   [a0]: trap_base -- The address of the trap table to initialize and enable.
### Return value:
###   <none>
### Callee preserved registers:
###   <none>
### Locals:
###   [t0]: default_handler_ptr -- A pointer to the default interrupt handler

init_trap_table:

	# WRITE THIS FUNCTION
	# Initialize trap table base in tb register
	csrw tb, a0

	# Initialize the default handler pointer
	la t0, default_handler

	# Initialize the trap table
	sw t0, 0(a0)
	sw t0, 4(a0)
	sw t0, 8(a0)
	sw t0, 12(a0)
	sw t0, 16(a0)
	sw t0, 20(a0)
	sw t0, 24(a0)
	sw t0, 28(a0)
	sw t0, 32(a0)
	
	# System Call Handler
	la t0, system_call_handler
	sw t0, 36(a0)

	# Back to default handler
	la t0, default_handler
	sw t0, 40(a0)
	sw t0, 44(a0)
	sw t0, 48(a0)
	
	ret
	
### ================================================================================================================================


	
### ================================================================================================================================
### Procedure: main
### Preserved registers:
###   [fp + 0]:      pfp
###   [ra / fp + 4]: pra
### Parameters:
###   <none>
### Return value:
###   [a0]: exit_code
### Preserved registers:
###   <none>
### Locals:
###   <none>

main:

	# Callee prologue
	sw		ra,		4(fp)						# Preserve ra

	# Call find_device() to get console info.
	lw		a0,		console_device_code				# arg[0] = console_device_code
	li		a1,		1						# arg[1] = 1 (first instance)
	addi		sp,		sp,		-8				# Push pfp / ra
	sw		fp,		0(sp)						# Preserve fp
	mv		fp,		sp						# Update fp
	call		find_device							# [a0] rv = dt_console_ptr
	bnez		a0,		main_with_console				# if (dt_console_ptr == NULL) ...
	lw		a0,		kernel_error_console_not_found			# Return with failure code
	j		main_return

main_with_console:
	# Copy the console base and limit into statics for later use.
	lw		t0,		4(a0)						# [t0] dt_console_ptr->base
	sw		t0,		console_base,		t6
	lw		t0,		8(a0)						# [50] dt_console_ptr->limit
	sw		t0,		console_limit,		t6
	
	# Call print() on the banner and attribution.  (Keep using caller subframe...)
	la		a0,		banner_msg					# arg[0] = banner_msg
	call		print
	la		a0,		attribution_msg					# arg[0] = attribution_msg
	call		print

	# Call init_trap_table(), then finally restore the frame.
	la		a0,		initializing_tt_msg				# arg[0] = initializing_tt_msg
	call		print
	la		a0,		trap_table
	call		init_trap_table
	la		a0,		done_msg					# arg[0] = done_msg
	call		print
	lw		fp,		0(sp)						# Restore fp
	addi		sp,		sp,		8				# Pop pfp / ra

	# # Test interrupts
	# la a0, interrupt_msg
	# call print
	
	# lw t0, 0(zero)

	# # Should not reach here
	# la a0, interrupt_failed_msg
	# call print

	# # Test system call
	# ecall

	# # Should not reach here
	# la a0, syscall_failed_msg
	# call print

	# Find the third ROM
	lw a0, ROM_device_code
	li a1, 3
	call find_device
	beqz a0, no_user_program

	# Load program into memory
	lw t0, 4(a0)
	lw t1, 8(a0)

	# Calculate the size of the ROM
	sub t2, t1, t0

	# Set program RAM space
	lw t3, kernel_limit
	mv t4, t2

	# Setup user stack
	add t5, t3, t2

	# Add 4KB for stack
	li t6, 0x1000
	add t5, t5, t6
	mv sp, t5             

	# Copy program to RAM
	mv a0, t0
	mv a1, t3
	mv a2, t2
	call copy_program

	# Switch to user mode
	li t0, 2
	csrs md, t0

	# Jump to the program
	sw t3, user_program_addr, t6

	# Jump to program with label
	j user_program

	# Callee epilogue: If we reach here, end the kernel.
	lw		a0,		kernel_normal_exit				# Set the result code
main_return:	
	lw		ra,		4(fp)						# Restore ra
	ret
### ================================================================================================================================

no_user_program:
	la a0, no_program_msg
	call print
	lw a0, kernel_normal_exit
	j main_return

copy_program:
	# Copy with DMA controller
	lw t0, device_table_base
	lw t0, 8(t0)
	addi t0, t0, -12

	# Set DMA portal
	sw a0, 0(t0)
	sw a1, 4(t0)
	sw a2, 8(t0)
	ret

user_program:
	lw t0, user_program_addr
	jr t0

	# Should not reach here
	lw a0, kernel_normal_exit
	
### ================================================================================================================================
	.Numeric

	## A special marker that indicates the beginning of the statics.  The value is just a magic cookie, in case any code wants
	## to check that this is the correct location (with high probability).
statics_start_marker:	0xdeadcafe

	## The trap table.  An array of 13 function pointers, to be initialized at runtime.
trap_table:             0
			0
			0
			0
			0
			0
			0
			0
			0
			0
			0
			0
			0

	## The interrupt buffer, used to store auxiliary information at the moment of an interrupt.
interrupt_buffer:	0 0 
	
	## Device table location and codes.
device_table_base:	0x00001000
none_device_code:	0
controller_device_code:	1
ROM_device_code:	2
RAM_device_code:	3
console_device_code:	4
block_device_code:	5

## System Calls
EXIT_SYSCALL: 1

	## Error codes.
kernel_normal_exit:			0xffff0000
kernel_error_RAM_not_found:		0xffff0001
kernel_error_small_RAM:			0xffff0002	
kernel_error_console_not_found:		0xffff0003
kernel_error_unmanaged_interrupt:	0xffff0004
	
	## Constants for printing and console management.
console_width:		80
console_height:		24

	## Other constants.
min_RAM:		0x10000 # 64 KB = 0x40 KB * 0x400 B/KB
bytes_per_page:		0x1000	# 4 KB/page
kernel_size:		0x8000	# 32 KB = 0x20 KB * 0x4 B/KB taken by the kernel.

	## Statically allocated variables.
cursor_column:		0	# The column position of the cursor (always on the last row).
RAM_base:		0
RAM_limit:		0
console_base:		0
console_limit:		0
kernel_base:		0
kernel_limit:		0

# Program specific constants
user_program_addr: 0 
### ================================================================================================================================



### ================================================================================================================================
	.Text

space_char:		" "
cursor_char:		"_"
newline_char:		"\n"
banner_msg:		"Fivish kernel v.2025-02-10\n"
attribution_msg:	"COSC-275 : Systems-II\n"
halting_msg:		"Halting kernel..."
initializing_tt_msg:	"Initializing trap table..."
interrupt_msg: "Interrupt occurred!\n"
interrupt_failed_msg: "Interrupt failed!\n"
syscall_msg: "System call occurred!\n"
syscall_failed_msg: "System call failed!\n"
no_program_msg: "No user program found!\n"
exit_msg: "Program exited.\n"
unknown_syscall_msg: "Unknown system call.\n"
done_msg:		"done.\n"
failed_msg:		"failed!\n"
blank_line:		"                                                                                "
### ================================================================================================================================
