;; xwrite

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

	; continue here

	; debug start
	                ; rsi already contains string start
	mov rdx, rax    ; string length we just calculated
	mov rax, 1		; write syscall
	mov rdi, 1		; stdout
	syscall
	; debug end

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

