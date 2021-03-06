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
	space_addr_ptr: resb 8		; start of space in memory

	num_space_ptr: resb 8		; number of bytes we can write to in file
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

	; check it has type EXEC or DYN, those are the only kinds we handle so far
	mov ax, WORD [r12+elf64.e_type]
	cmp ax, ELF_EXEC
	je .ok_file_type
	cmp ax, ELF_DYN
	jne unsupported_elf_type

.ok_file_type:  ; we know we handle this type of file

	; Read program headers to find code start, that will be the end of our space

	xor eax, eax
	mov ax, WORD [r12+elf64.e_phentsize]		; size of a program header - 56 bytes
	mov r10, rax
	xor ecx, ecx
	mov cx, WORD [r12+elf64.e_phnum]			; number of program headers - varies

	; interlude - compute end of program headers, that's a candidate for space start
	mul ecx					; size of a prog header (already in rax) * num prog headers
	add rax, QWORD [r12+elf64.e_phoff]     ; add offset of start of program headers
	mov [space_offset_ptr], rax				; offset within file
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

	mov [code_start_ptr], r8 ; this is where first opcode appears. space stops here.

	; iterate section headers,
	; find sh_offset closest <= code_start_ptr. add it's sh_size to itself.

	xor ecx, ecx
	mov cx, [r12+elf64.e_shnum]			; number of section headers
	test ecx, ecx
	je .use_end_of_program_headers      ; no section headers (UPX files have this)

	mov rsi, QWORD [r12+elf64.e_shoff]	; offset of start of section headers
	add rsi, r12						; rsi now points at mmap first section header
	xor ebx, ebx
	mov bx, [r12+elf64.e_shentsize]		; size of a section header
	mov r8, 0							; best so far
	sub rsi, rbx

.next_sh:
	add rsi, rbx ; next section header
	mov rax, QWORD [rsi+elf64_shdr.sh_offset]
	add rax, QWORD [rsi+elf64_shdr.sh_size]

	; is it past code start? then we're not interested
	cmp rax, [code_start_ptr]
	jge .next_sh_end

	; is it bigger than our best so far?
	cmp rax, r8
	jle .next_sh_end
	mov r8, rax

.next_sh_end:
	dec ecx
	jnz .next_sh
	; r8 now has the end of the closest section header

	; compute start of space
	; It's the number closest to, and less than, start of opcodes, from:
	; - end of program headers (already in space_offset_ptr)
	; - end of closest section header
	cmp r8, [space_offset_ptr]
	jle .use_end_of_program_headers

	; use end of closest section header
	mov [space_offset_ptr], r8
	add r8, r12
	mov [space_addr_ptr], r8

.use_end_of_program_headers:

	; we can use the space between end of program headers and start of opcodes
	mov eax, [code_start_ptr]
	sub eax, [space_offset_ptr]
	mov [num_space_ptr], rax

	; sanity check for upx packed files, those are weird
	mov rsi, [space_addr_ptr]
	mov eax, DWORD [rsi+4]
	cmp eax, UPX_ID
	je upx_file

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
	test eax, eax
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

unsupported_elf_type:
	mov rax, -35
	err_check EM_ELF_UNSUPPORTED

upx_file:
	mov rax, -35
	err_check EM_UPX

