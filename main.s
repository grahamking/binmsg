;; xwrite
;;
;; syscall (kernel) convention:
;;   IN: RDI, RSI, RDX, R10, R8 and R9
;;  OUT: RAX
;;
;; error codes are in /usr/include/asm-generic/errno-base.h
;;

;; macros

;; handle error and exit
;;
;; param1: err message
;; param2: err message length
%macro err_check 2
	cmp rax, 0
	jge %%ok
	mov rdi, rax
	mov rsi, %1
	mov rdx, %2
	jmp err
	%%ok:
%endmacro

;; end macros

;;
;; .data
;;
section .data
	usage: db `Usage: echo data | xwrite filename\n`
	usage_len: equ $-usage

	max_filename_length: equ 100

	elf_header: equ 0x464c457f

; error message

	em_open: db `: open error\n`
	em_open_len: equ $-em_open

	em_fstat: db `: fstat error\n`
	em_fstat_len: equ $-em_fstat

	em_mmap: db `: mmap error\n`
	em_mmap_len: equ $-em_mmap

	em_elf: db `: not an ELF file, invalid 4 header bytes expect 7F E L F\n`
	em_elf_len: equ $-em_elf

;;
;; .text
;;
section .text

global _start

;;
;; main
;; most of the code is here
;;
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
	err_check em_open, em_open_len

	mov r15, rax ; fd number should be in rax, save it

	; space to put stat buffer, on the stack
	sub rsp, 144 ; struct stat in stat/stat.h

	; fstat file to get size
	mov rax, 5		; fstat syscall
	mov rdi, r15	; fd
	mov rsi, rsp	; &stat
	syscall
	err_check em_fstat, em_fstat_len

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
	err_check em_mmap, em_mmap_len

	; check it's an ELF file
	cmp [rax], DWORD elf_header
	je _elf_ok
	; invalid elf header, use our macro by faking rax err code
	mov rax, -1
	err_check em_elf, em_elf_len

_elf_ok:

	; continue here

	jmp exit

;;
;; print usage and exit
;;
print_usage:
	mov rax, 1	; write
	mov rdi, 1  ; stdout
	mov rsi, usage
	mov rdx, usage_len
	syscall
	jmp exit

;;
;; err
;; prints an error include error code and exits
;;
err:
	; rdi: err code
	; rsi: err msg address
	; rdx: err msg length

	mov rax, rdi
	push rdx
	push rsi

	; abs(eax), err codes are negative
	xor eax, 0xFFFFFFFF
	sub eax, 0xFFFFFFFF

	; divide rax (err code) by 10 to get split digits into rax:rdx
	;  err codes are max two digits
	xor rdx, rdx  ; rdx to 0, it is going to get remainder
	mov rbx, 10
	div rbx
	push rdx      ; save the second digit, we hand the first digit first

	cmp rax, 0    ; do we have a first digit?
	je _err_second_digit ; if no skip this next section

	add rax, 0x30  ; convert to ascii
	push rax       ; need a memory address

	mov rax, 1	; write
	mov rdi, 1  ; stdout
	mov rsi, rsp
	mov rdx, 1
	syscall
	pop rax ; clean stack

_err_second_digit:

	; second digit (rdx, remainder) is on top of stack
	add [rsp], BYTE 0x30 ; convert to ascii

	mov rax, 1	; write
	mov rdi, 1  ; stdout
	mov rsi, rsp
	mov rdx, 1
	syscall

	pop rdx  ; clean stack

	mov rax, 1	; write
	mov rdi, 1  ; stdout
	pop rsi ; saved in function prologue
	pop rdx ;
	;mov rsi, em_open
	;mov rdx, em_open_len
	syscall
	jmp exit

;;
;; exit
;; never returns
;;
exit:
	mov rdi, 0  ; return code 0
	mov rax, 60 ; exit syscall
	syscall

