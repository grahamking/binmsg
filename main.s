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
%macro err_check 1
	cmp rax, 0
	jge %%ok
	mov rdi, rax
	mov rsi, %1
	jmp err ; jmp not call because it doesn't return
	%%ok:
%endmacro

;; end macros

;;
;; .data
;;
section .data

	elf_header: equ 0x464c457f

; error messages

	em_open: db "open error: ",0
	em_fstat: db "fstat error: ",0
	em_mmap: db "mmap error: ",0
	em_elf: db "not an ELF file, invalid 4 header bytes expect 7F E L F",0

	%include "def.s"

;;
;; imports
;;

extern strlen, exit, print_usage, err

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
	call strlen

	; open the file, we need fd for mmap
				; filename still in rdi
	mov rsi, 2	; flags: O_RDWR
	mov rax, SYS_OPEN
	syscall
	err_check em_open

	mov r15, rax ; fd number should be in rax, save it

	; space to put stat buffer, on the stack
	sub rsp, 144 ; struct stat in stat/stat.h

	; fstat file to get size
	mov rax, SYS_FSTAT
	mov rdi, r15	; fd
	mov rsi, rsp	; &stat
	syscall
	err_check em_fstat

	mov r14, [rsp + 48] ; stat st_size is 44 bytes into the struct
						; but I guess 4 bytes of padding?

	; mmap it
	mov rax, SYS_MMAP
	mov rdi, 0 ; let kernel choose starting address
	mov rsi, r14 ; size
	mov rdx, 3 ; prot: PROT_READ|PROT_WRITE which are 1 and 2
	mov r10, 2; flags: MAP_PRIVATE
	mov r8, r15 ; fd
	mov r9, 0; offset in the file to start mapping
	syscall
	err_check em_mmap

	; check it's an ELF file
	cmp [rax], DWORD elf_header
	je _elf_ok
	; invalid elf header, use our macro by faking rax err code
	mov rax, -1
	err_check em_elf

_elf_ok:

	; continue here

	jmp exit
