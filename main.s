;; xwrite
;;
;; syscall (kernel) convention:
;;   IN: RDI, RSI, RDX, R10, R8 and R9
;;  OUT: RAX
;;
;; syscall numbers: /usr/include/asm/unistd_64.h
;; error codes: /usr/include/asm-generic/errno-base.h
;;

;; macros

;; handle error and exit
;;
;; param1: err message
%macro err_check 1
	cmp rax, 0
	mov rdi, %1 ; should be a conditional move, but no immediate for that
	jl err
%endmacro

;; end macros

;;
;; Static data
;;
%include "def.s"
section .data

	ELF_HEADER: equ 0x464c457f

; messages

	SPACE_START: db "Available space: ",0
	SPACE_END: db " bytes",10,0
	WROTE: db "Wrote bytes at offset: ",0

; error messages

	EM_OPEN: db "open error: ",0
	EM_FSTAT: db "fstat error: ",0
	EM_MMAP: db "mmap error: ",0
	EM_ELF: db "not an ELF file, invalid 4 header bytes expect 7F E L F",0
	EM_READ_STDIN: db "stdin read error: ",0
	EM_CLOSE: db "close error: ",0
	EM_MSYNC: db "msync error: ",0
	EM_MUNMAP: db "munmap error: ",0

;;
;; Global variables
;;
section .bss
	fd_ptr: resb 8				; fd of the file we are writing to
	file_size_ptr: resb 8		; number of bytes in target file
	mmap_ptr_ptr: resb 8		; address of mmap'ed file
	write_offset_ptr: resb 8	; how many bytes into the file we'll start writing
	num_space_ptr: resb 8		; number of bytes we can write to in file
	space_addr_ptr: resb 8		; start of space in memory
	num_wrote_ptr: resb 8		; how many bytes we wrote to the file

;;
;; imports
;;

extern strlen, exit, print, print_usage, itoa, err, isatty

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
	mov al, BYTE [rsp]   ; don't need to clear al, registers start at 0
	cmp al, 2
	jne print_usage

	; strlen of filename
	mov rdi, [rsp + 16] ; address of first cmd line parameter
	call strlen

	; open the file, we need fd for mmap
				; filename still in rdi
	mov esi, 2	; flags: O_RDWR
	mov eax, SYS_OPEN
	safe_syscall
	err_check EM_OPEN

	mov [fd_ptr], rax ; fd number should be in rax, save it

	; space to put stat buffer, on the stack
	sub rsp, 144 ; struct stat in stat/stat.h

	; fstat file to get size
	mov eax, SYS_FSTAT
	mov edi, [fd_ptr]
	mov rsi, rsp	; &stat
	safe_syscall
	err_check EM_FSTAT

	mov rax, [rsp + 48] ; stat st_size is 44 bytes into the struct
						; but I guess 4 bytes of padding?
	mov [file_size_ptr], rax;

	; mmap it
	mov eax, SYS_MMAP
	mov edi, 0 ; let kernel choose starting address
	mov esi, [file_size_ptr] ; size
	mov edx, 3 ; prot: PROT_READ|PROT_WRITE which are 1 and 2
	mov r10, MAP_SHARED; flags
	mov r8, [fd_ptr]
	mov r9, 0; offset in the file to start mapping
	safe_syscall
	err_check EM_MMAP
	mov [mmap_ptr_ptr], rax ; save mmap address

	; check it's an ELF file
	cmp [rax], DWORD ELF_HEADER
	jne _elf_err

	; ELF format is 64 bytes of header + variable program headers,
	; then the .text section (the program opcodes).
	; We need to find the end of program headers

	; mmap_ptr is **u8. It contains the address of a reserved (.bss) area
	; that reserved area contains the address of the mmap section
	mov r12, [mmap_ptr_ptr]		; Get mmap address

	; program headers
	xor eax, eax
	mov ax, WORD [r12+54]		; size of a program header
	xor ecx, ecx
	mov cx, WORD [r12+56]		; number of program headers
	mul ecx
	add rax, QWORD [r12+32]		; offset of start of program headers

	mov [write_offset_ptr], rax

	add rax, r12	; rax now has address of start of program headers
	mov [space_addr_ptr], rax

	; count contiguous 0's (available space)
	mov rdi, rax		; compare this string
	mov eax, 0			;  with 0 (null byte)
	mov ecx, MAX_STORE  ; don't go beyond this many bytes
	repe scasb			; repeat moving rdi forward until it doesn't match al

	; space is current rdi pos minus start pos
	mov rcx, rdi
	sub rcx, [space_addr_ptr]
	dec ecx  ; rep leaves rdi on first non-null byte, which we don't count
	mov [num_space_ptr], rcx

	; tell user how much space there is

	; print message
	mov rdi, SPACE_START
	call print

	; convert number to string and print it
	sub rsp, 8	; we don't expect more than 7 digits (+ null byte) of empty space
	mov rdi, rcx ; rcx still holds [num_space_ptr], so a load
	mov rsi, rsp
	call itoa

	mov rdi, rsp
	call print
	add rsp, 8

	mov rdi, SPACE_END
	call print

	; is there any space?
	mov eax, DWORD [num_space_ptr]
	cmp al, 0
	je _cleanup

	; is there input on STDIN?
	mov edi, STDIN
	call isatty
	test rax, rax
	jns exit ; if STDIN is a terminal we're done

	; read up to [num_space_ptr] bytes from stdin straight into output
	mov eax, SYS_READ
	mov edi, STDIN
	mov rsi, [space_addr_ptr]		; read straight into the file
	mov edx, [num_space_ptr]		; how many bytes to read
	safe_syscall
	err_check EM_READ_STDIN
	mov [num_wrote_ptr], rax ; rax tells us how many bytes actually written

	; sync the mmap back to disk
	mov rcx, [write_offset_ptr]
	add ecx, [num_wrote_ptr]
	mov eax, SYS_MSYNC
	mov rdi, [mmap_ptr_ptr] ; mem to write must be aligned, so use start
	mov rsi, rcx			; how many bytes to write back
	mov edx, MS_SYNC
	safe_syscall
	err_check EM_MSYNC

	; tell user what we did

	mov rdi, WROTE
	call print

	; convert byte count, print it
	sub rsp, 8     ; should be plenty of space for string
	mov edi, [num_wrote_ptr]   ; num bytes written, saved earlier from rax
	mov rsi, rsp   ; buffer
	call itoa
	mov rdi, rsi   ; the buffer we just filled with itoa(num bytes written)
	call print
	add rsp, 8

	; print comma and space
	push 0   ; null byte
	push ' ' ; space (32)
	push ',' ; comma (44)
	mov rdi, rsp
	call print
	add rsp, 3

	; convert offset count, print it
	sub rsp, 8
	mov rdi, [write_offset_ptr]
	mov rsi, rsp
	call itoa
	mov rdi, rsi
	call print
	add rsp, 8

	; print carriage return
	push 0   ; these two pushes make null-terminated string "\n" on stack
	push 10
	mov rdi, rsp
	call print
	add rsp, 2

_cleanup:

	; munmap. we probably don't need this
	mov eax, SYS_MUNMAP
	mov rdi, [mmap_ptr_ptr]
	mov esi, [file_size_ptr]
	syscall  ; not safe_syscall, no need so late in the program
	err_check EM_MUNMAP

	; close the file. also probably not necessary
	mov eax, SYS_CLOSE
	mov edi, [fd_ptr]
	syscall  ; not safe_syscall, no need so late in the program
	err_check EM_CLOSE

	jmp exit

;
; misc jumps
;
_elf_err:
	; invalid elf header, use our macro by faking rax err code
	mov rax, -1
	err_check EM_ELF
