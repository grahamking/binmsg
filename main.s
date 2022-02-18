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
%include "struct.s"

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
	cmp [r12+elf64.e_ident], DWORD ELF_HEADER
	jne elf_err

	; check it has type EXEC, that's the only kind we handle so far
	mov ax, WORD [r12+elf64.e_type]
	cmp ax, ELF_EXEC
	jne not_exec_file

	; Read program headers to find code start, that will be the end of our space

	xor eax, eax
	mov ax, WORD [r12+elf64.e_phentsize]		; size of a program header - 56 bytes
	mov r10, rax
	xor ecx, ecx
	mov cx, WORD [r12+elf64.e_phnum]			; number of program headers - varies

	; interlude - compute end of program headers, that's a candidate for space start
	mul ecx						; size of a prog header (already in rax) * num prog headers
	add rax, QWORD [r12+elf64.e_phoff]     ; add offset of start of program headers
	mov [space_offset_ptr], rax ; offset within file
	add rax, r12				; add mmap address
	mov [space_addr_ptr], rax   ; memory address (within mmap)
	; end interlude

	mov rsi, QWORD [r12+elf64.e_phoff]	; offset of start of program headers, always 64
	add rsi, r12						; rsi now points at mmap first program header
	mov r8, -1							; lowest offset so far. -1 is unsigned max

.next_ph:

	; r9 = size_of_a_program_header (rdx, usually 56) * rcx (loop counter)
	mov rax, rcx
	dec rax
	mul r10
	mov r9, rax

	; is it a LOAD header? we only want those
	mov eax, [rsi+r9+elf64_phdr.p_type]
	cmp al, PH_LOAD
	jne .next_ph_end

	; is it at least read+execute? we only want those
	mov eax, [rsi+r9+elf64_phdr.p_flags]
	and eax, 0x5
	cmp eax, 0x5
	jne .next_ph_end

	; we found one, only keep if our best so far is bigger
	mov rax, [rsi+r9+elf64_phdr.p_offset]
	cmp r8, rax
	cmova r8, rax	; conditional move; if r8 is above the new value

.next_ph_end:
	dec ecx
	jnz .next_ph

	mov [code_start_ptr], r8	; this is where the first opcode appears. our space stops here.

	; TODO: compute start of space.
	; It's the number closest to, and less than, end of space (above), from:
	; - end of program headers (computed earlier)
	; - iterate section headers, find closest lower sh_offset. add it's sh_size to itself.
	;   ignore values with sh_offset of 0, and values not strictly less that 'end of space' above
	; That's start of our space

	; we can use the space between end of program headers and start of opcodes
	mov eax, [code_start_ptr]
	sub eax, [space_offset_ptr]
	mov [num_space_ptr], rax

	; is there input on STDIN?
	mov edi, STDIN
	call isatty
	test rax, rax
	js .do_write   ; stdin is a pipe, write case
	; stdin is not a pipe, read case

	mov rdi, [space_addr_ptr]
	mov rsi, [num_space_ptr]
	call read_msg

	jmp .cleanup

.do_write:

	; is there any space?
	mov eax, DWORD [num_space_ptr]
	cmp eax, 0
	je .cleanup

	mov rdi, [space_addr_ptr]
	mov rsi, [num_space_ptr]
	mov rdx, [mmap_ptr_ptr]
	mov rcx, [space_offset_ptr]
	call write_msg

.cleanup:

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

