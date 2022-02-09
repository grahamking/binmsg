;; binmsg
;; A tool to write data into spare space in ELF binaries.
;; Usage: Write: echo -n 'the messages' | binmsg <filename>
;;        Read: binmsg <filename>
;;

;; syscall (kernel) convention:
;;   IN: RDI, RSI, RDX, R10, R8 and R9
;;  OUT: RAX
;;
;; syscall numbers: /usr/include/asm/unistd_64.h
;; error codes: /usr/include/asm-generic/errno-base.h
;;

%include "def.s"

;;
;; Global variables
;;
section .bss
	fd_ptr: resb 8				; fd of the file we are writing to
	file_size_ptr: resb 8		; number of bytes in target file
	mmap_ptr_ptr: resb 8		; address of mmap'ed file
	space_offset_ptr: resb 8	; how many bytes into the file we'll start writing
	num_space_ptr: resb 8		; number of bytes we can write to in file
	space_addr_ptr: resb 8		; start of space in memory
	;num_wrote_ptr: resb 8		; how many bytes we wrote to the file
	code_start_ptr: resb 8		; file offset where opcodes start

;;
;; imports
;;

extern strlen, exit, print, print_usage, itoa, err, isatty, read_msg, write_msg, show_space

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

	; ELF format is 64 bytes of header + variable program headers,
	; then the .text section (the program opcodes).
	; We need to find the end of program headers

	; mmap_ptr is **u8. It contains the address of a reserved (.bss) area
	; that reserved area contains the address of the mmap section
	mov r12, [mmap_ptr_ptr]		; Get mmap address

	; check it's an ELF file
	cmp [r12], DWORD ELF_HEADER
	jne elf_err

	; check it has type EXEC, that's the only kind we handle so far
	mov ax, WORD [r12+16]
	cmp ax, ELF_EXEC
	jne not_exec_file

	; size of program headers, to find their end
	xor eax, eax
	mov ax, WORD [r12+54]		; size of a program header
	xor ecx, ecx
	mov cx, WORD [r12+56]		; number of program headers
	mul ecx
	add rax, QWORD [r12+32]		; offset of start of program headers

	mov [space_offset_ptr], rax

	add rax, r12	; rax now has address of end of program headers, start of spare space
	mov [space_addr_ptr], rax

	; find where space stops, which is where program starts
	; we'll need the first LOAD program header (which comes after the ELF header)

	mov eax, [r12+64]
	cmp al, PH_LOAD
	jne not_load_program_header

	; calculate: (entry point - (p_vaddr - p_offset))
	mov rbx, [r12+72]   ; 64 + 8, elf64_phdr.p_offset (first program header)
	mov rax, [r12+80]   ; 64 + 16, elf64_phdr.p_vaddr (first program header)
	sub rax, rbx
	mov rbx, [r12+24]   ; entry point as memory address (ELF header)
	sub rbx, rax
	mov [code_start_ptr], rbx

	; we can use the space between end of program headers and start of opcodes
	mov eax, ebx
	sub eax, [space_offset_ptr]
	mov [num_space_ptr], rax

	; is there input on STDIN?
	mov edi, STDIN
	call isatty
	test rax, rax
	js _do_write   ; stdin is a pipe, write case
	; stdin is not a pipe, read case

	mov rdi, [space_addr_ptr]
	mov rsi, [num_space_ptr]
	call read_msg

	jmp _cleanup

_do_write:

	; is there any space?
	mov eax, DWORD [num_space_ptr]
	cmp eax, 0
	je _cleanup

	mov rdi, [space_addr_ptr]
	mov rsi, [num_space_ptr]
	mov rdx, [mmap_ptr_ptr]
	mov rcx, [space_offset_ptr]
	call write_msg

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
elf_err:
	; invalid elf header, use our macro by faking rax err code
	mov rax, -35
	err_check EM_ELF

not_load_program_header:
	mov rax, -35
	err_check EM_PH_LOAD

not_exec_file:
	mov rax, -35
	err_check EM_ELF_NOT_EXEC

