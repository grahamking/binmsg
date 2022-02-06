;;
;; functions
;;

%include "def.s"

section .text

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
	push rdi
	push rcx
	push rsi

	mov eax, 0
	mov ecx, MAX_FNAME_LEN
	mov rsi, rdi	; save string start
	repne scasb		; search for null byte at end of string, end of filename
					; leaves rdi pointing at null byte
	sub rdi, rsi	; subtract start to get length
	dec edi			; don't count null byte
	mov eax, edi	; return length in rax

	pop rsi
	pop rcx
	pop rdi
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
	push rdx

	; does the actual abs
	cqo ; fill rdx with sign of rax, so rdx will be 0 or -1 (0xFF..)
	xor eax, edx
	sub eax, edx

	pop rdx
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

	mov ecx, 0
	mov rax, rdi  ; rax is numerator
	mov ebx, 10   ; 10 is denominator

_itoa_next_digit:
	; divide rax by 10 to get split digits into rax:rdx
	xor edx, edx  ; rdx to 0, it is going to get remainder
	div rbx
	add edx, 0x30	; convert to ASCII
	push rdx		; digits are in reverse order. stacks are good for that.
	inc cl
	cmp al, 0		; do we have more digits?
	jg _itoa_next_digit

	; now pop them off the stack into memory, they will be in correct order
	xor ebx, ebx
_itoa_next_format:
	pop rax
	mov [rsi+rbx], BYTE al
	inc bx
	loop _itoa_next_format

	; null byte to terminate string
	mov [rsi+rbx], BYTE 0

	; epilogue
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
	jge _err_numeric

	mov rdi, QWORD [ERRS+rax*8]
	call print_err
	jmp exit

_err_numeric:
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
	push 0   ; these two pushes make null-terminated string "\n" on stack
	push 10
	mov rdi, rsp
	call print_err
	add rsp, 2

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
