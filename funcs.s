;;
;; functions
;;

%include "def.s"

section .text

;;
;; write_msg: Read from stdin, write into the file
;; rdi: address of space to write to [space_addr_ptr]
;; rsi: max length of data to write [num_space_ptr]
;; rdx: mmap address, we need this to msync
;; rcx: offset of space to write to [space_offset_ptr]
;;
global write_msg
write_msg:
	push rax
	push rbp
	mov rbp, rsp
	sub rsp, 8   ; space for 8 character digits

	mov r11, rcx ; [space_offset_ptr]
	mov r12, rdi ; [space_addr_ptr]
	mov r13, rsi ; [num_space_ptr]
	mov r14, rdx ; [mmap_ptr_ptr]

	; read up to [num_space_ptr] bytes from stdin straight into output
	mov eax, SYS_READ
	mov edi, STDIN
	mov rsi, r12		; read straight into the file
	mov rdx, r13		; how many bytes to read
	safe_syscall
	err_check EM_READ_STDIN
	; rax now holds how many bytes actually written
	mov r15, rax

	; sync the mmap back to disk
	mov rcx, r11
	add ecx, eax  ; bytes written
	mov eax, SYS_MSYNC
	mov rdi, r14			; mem to write must be aligned, so use start
	mov rsi, rcx			; how many bytes to write back
	mov edx, MS_SYNC
	safe_syscall
	err_check EM_MSYNC

	; tell user what we did

	mov rdi, WROTE
	call print

	; convert byte count, print it
	mov rdi, r15		; num bytes written, saved earlier from rax
	lea rsi, [rbp-8]	; buffer
	call itoa
	mov rdi, rsi		; the buffer we just filled with itoa(num bytes written)
	call print

	; print comma and space
	mov rdi, COMMA_SPACE
	call print

	; convert offset count, print it
	mov rdi, r11
	lea rsi, [rbp-8]
	call itoa
	lea rdi, [rbp-8]
	call print

	; print carriage return
	mov rdi, CR
	call print

	add rsp, 8
	pop rbp
	pop rax
	ret

;;
;; read_msg: Read from the file, write to stdout
;; rdi: Message start address
;; rsi: Message length in bytes
;;
global read_msg
read_msg:
	push rax
	push rcx
	push r11
	push r12

	mov r11, rdi ; save params
	mov r12, rsi

	; is there a message? we decide this based on first byte, must not be null
	xor eax, eax
	mov al, BYTE [rdi]
	test eax, eax
	jne .read_msg_proceed

	; if there's no msg display space and exit
	; this is probably more common than display msg, so make it the predicated not-jump
	mov rdi, r12
	call show_space
	jmp .read_msg_epilogue

.read_msg_proceed:
	; yes there's a message, write it to stdout
	mov eax, SYS_WRITE
	mov edi, STDOUT
	mov rsi, r11
	mov rdx, r12
	safe_syscall

.read_msg_epilogue:
	pop r12
	pop r11
	pop rcx
	pop rax

	ret

;;
;; show_space: Print how much space is available in this file
;; rdi: how much space is available, as a number
;;
global show_space
show_space:
	push rsi
	push rdi

	; print message
	mov rdi, AVAILABLE_SPACE
	call print

	; convert number to string and print it
	pop rdi  ; param we were given space as number
	sub rsp, 8	; we don't expect more than 7 digits (+ null byte) of empty space
	mov rsi, rsp
	call itoa

	mov rdi, rsi
	call print
	add rsp, 8

	mov rdi, BYTES
	call print

	pop rsi
	ret

;;
;; print usage and exit
;;
global print_usage
print_usage:
	mov rdi, USAGE
	call print
	call exit

;;
;; print a null terminated string to stdout
;; rdi: str addr
;;
global print
print:
	push rsi
	mov esi, STDOUT
	call fprint
	pop rsi
	ret

;;
;; print a null terminated string to stderr
;; rdi: str addr
;;
global print_err
print_err:
	push rsi
	mov esi, STDERR
	call fprint
	pop rsi
	ret

;;
;; strlen: Length of null-terminated string with addr in rdi
;; length returned in rax
;;
global strlen
strlen:
	push rcx
	push rdx

	xor eax, eax
	mov edx, 0xFF01		; range(01..FF), i.e. everything except null byte
	movd xmm0, edx		;  this is the range we are looking for
	sub eax, 16
	sub rdi, 16
.next:
	add eax, 16
	add rdi, 16
	pcmpistri xmm0, [rdi], 0x14	; Packed CMPare Implicit (\0 terminator) STRing
								;  returning Index.
								; 0x14 is control byte 1 01 00
								; 00: src is unsigned bytes
								; 01: range match
								; 1: negate the result (so match not in the range, i.e match \0)
	jnz .next
	add eax, ecx

	pop rdx
	pop rcx
	ret

;; Print null terimanted string to file descriptor
;; rdi: str addr
;; rsi: open file descriptor
global fprint
fprint:
	push rax
	push rdx

	push rdi
	push rsi

	call strlen
	mov edx, eax ; strlen now in edx

	; write syscall
	mov eax, SYS_WRITE
	; swap rdi/rsi from earlier push
	pop rdi  ; file descriptor now in rdi
	pop rsi  ; rsi now points at str addr
	safe_syscall

	pop rdx
	pop rax
	ret

;;
;; abs_rax: Absolute value ("abs" is reserved)
;; Unusual ABI!
;; rax: Number to convert. Is replaced with it's absolute value.
;;
global abs_rax
abs_rax:

	mov r11, rdx	; push rdx, faster. r11 is always fair game.
	; does the actual abs
	cqo ; fill rdx with sign of rax, so rdx will be 0 or -1 (0xFF..)
	xor eax, edx
	sub eax, edx
	mov rdx, r11	; pop rdx

	; MMX - 2x slower
	;pinsrw xmm0, eax, 0
	;pabsw xmm1, xmm0
	;pextrw eax, xmm1, 0

	; FPU - at least 5x slower, must go via memory
	;push rax			; can't copy directly x86 reg -> x87 reg, need to go via memory
	;fild qword [rsp]   ; copy to x87 register stack
	;fabs				; abs(top of FPU stack)
	;fistp qword [rsp]  ; copy from x87 register stack
	;pop rax			; rax now has abs value

	ret

;;
;; itoa: Convert number to string
;; rdi: number to convert
;; rsi: address to put converted number. Must have space.
;;
global itoa
itoa:
	; prologue
	push rax
	push rbx
	push rcx
	push rdx
	push rsi
	push rdi
	push r8
	push rbp
	mov rbp, rsp
	sub rsp, 8    ; we only handle up to 8 digit numbers

	xor ecx, ecx
	mov rax, rdi  ; rax is numerator
	mov ebx, 10   ; 10 is denominator
	mov r8, rbp

.itoa_next_digit:
	; divide rax by 10 to get split digits into rax:rdx
	xor edx, edx  ; rdx to 0, it is going to get remainder
	div rbx
	add edx, 0x30	; convert to ASCII
	inc cl
	dec r8
	mov [r8], BYTE dl	; digits are in reverse order, so work down memory
							; this must be dl, a byte, so that 'movsb' can
							; move bytes later.
	test eax, eax			; do we have more digits?
	jg .itoa_next_digit

	; now copy them from stack into memory, they will be in correct order
	cld					; clear direction flag, so we walk up
	mov rdi, rsi		; rsi had desination address
	mov rsi, r8			; source is stack
						; rcx already has string length
	rep movsb			; repeat rcx times: copy rsi++ to rdi++
	mov [rdi], BYTE 0	; null byte to terminate string

	; epilogue
	add rsp, 8
	pop rbp
	pop r8
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	pop rax

	ret

;;
;; err: prints an error include error code and exits
;; Unusual ABI!
;; rax: err code, because it's already in there
;; rdi: err msg address
;;
global err
err:
	call abs_rax
	call print_err

	mov ecx, ERRS_BYTE_LEN
	shr ecx, 3 ; divide by 8
	cmp eax, ecx
	jge .err_numeric

	mov rdi, QWORD [ERRS+rax*8]
	call print_err
	jmp exit

.err_numeric:
	; err code (rax) isn't in our table, print the code itself

	; convert code to string
	mov edi, eax
	sub rsp, 8
	mov rsi, rsp
	call itoa

	; print code
	mov rdi, rsi
	call print_err
	add rsp, 8

	; print carriage return
	mov rdi, CR
	call print_err

	jmp exit

;;
;; isatty
;; IN  rdi: fd to test
;; OUT rax: negative if fd is _not_ a terminal
;;     caller should `test rax, rax` and `js _not_terminal`
;;
global isatty
isatty:
	push rdx
	push rsi

	; we don't use what goes in here, but we need space
	sub rsp, SIZEOF_TERMIOS

	mov eax, SYS_IOCTL
		; rdi already has fd
	mov esi, TCGETS
	mov rdx, rsp
	safe_syscall

	add rsp, SIZEOF_TERMIOS

	pop rsi
	pop rdx
	ret

;;
;; exit
;; never returns
;;
global exit
exit:
	mov edi, 0  ; return code 0
	mov eax, SYS_EXIT
	safe_syscall
