;; xwrite
;;
;; syscall (kernel) convention:
;;   IN: RDI, RSI, RDX, R10, R8 and R9
;;  OUT: RAX

section .data
	usage: db `Usage: echo data | xwrite filename\n`
	usage_len: equ $-usage
	max_filename_length: equ 100

section .text

global _start
_start:

	; number of cmd line arguments is at rsp
	; we want exactly 2, program name, and a filename
	mov rax, [rsp]
	cmp rax, 2
	jne print_usage

	; strlen of filename
	mov rdi, [rsp + 16] ; address of first cmd line parameter
	mov rsi, rdi
	mov al, 0			; null byte
	mov rcx, max_filename_length ; max string length
	repne scasb ; search for null byte at end of string, end of filename
				; leaves rdi pointing at null byte
	mov rax, rdi	; subtract end of string from start to get length
	sub rax, rsi	;
	dec rax			; don't count null byte in length
					; strlen(arg[1]) is now in rax

	; open the file, we need fd for mmap
	mov rdi, rsi ; filename
	mov rsi, 2 ; flags: O_RDWR
	mov rax, 2 ; open syscall
	syscall
	mov r15, rax ; fd number should be in rax, save it

	; space to put stat buffer, on the stack
	add rsp, 144 ; struct stat in stat/stat.h

	; fstat file to get size
	mov rax, 5 ; fstat syscall
	mov rdi, r15 ; fd
	mov rsi, rsp ; &stat
	syscall
	mov r14, [rsp + 48] ; stat st_size is 44 bytes into the struct
						; but I guess 4 bytes of padding?

	; mmap it
	mov rax, 9 ; mmap syscall
	mov rdi, 0 ; let kernel choose starting address
	mov rsi, r14 ; size
	mov rdx, 3 ; prot: PROT_READ|PROT_WRITE which are 1 and 2
	mov r10, 2; flags: MAP_PRIVATE
	mov r8, r15 ; fd
	mov r9, 0; offset in the file to start mapping
	syscall
	; address is in rax

	; continue here

	jmp exit

print_usage:
	mov rax, 1	; write
	mov rdi, 1  ; stdout
	mov rsi, usage
	mov rdx, usage_len
	syscall

exit:
	mov rdi, 0  ; return code 0
	mov rax, 60 ; exit syscall
	syscall

