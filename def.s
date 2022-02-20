;;
;; shared and static definitions
;;

;; macros

;; handle error and exit
;; param1: err message
%macro err_check 1
	cmp rax, 0
	mov rdi, %1 ; should be a conditional move, but no immediate for that
	jl err
%endmacro

;; syscall overwrites rcx and r11, and I'm not going to remember every time
%macro safe_syscall 0
	push rcx
	push r11
	syscall
	pop r11
	pop rcx
%endmacro

;; end macros

section .data
	align 16

	ELF_HEADER: equ 0x464c457f  ; ELF magic header
	ELF_EXEC: equ 2				; ELF e_type of ET_EXEC
	ELF_DYN: equ 3				; ELF e_type of ET_DYN
	PH_LOAD: equ 1				; program header type LOAD
	MAX_FNAME_LEN: equ 100
	USAGE: db `Usage: \n\tWrite: echo -n data | binmsg filename\n\tRead: binmsg filename [> out]\n\0`
	UPX_ID: equ 0x21585055		; "UPX!" to identify files packed with upx

; messages

	AVAILABLE_SPACE: db "Available space: ",0
	BYTES: db " bytes",10,0
	WROTE: db "Wrote bytes at offset: ",0
	COMMA_SPACE: db ", ",0
	CR: db "",10,0

; error messages

	EM_OPEN: db "open error: ",0
	EM_FSTAT: db "fstat error: ",0
	EM_MMAP: db "mmap error: ",0
	EM_ELF: db "not an ELF file, invalid 4 header bytes expect 7F E L F",0
	EM_READ_STDIN: db "stdin read error: ",0
	EM_CLOSE: db "close error: ",0
	EM_MSYNC: db "msync error: ",0
	EM_MUNMAP: db "munmap error: ",0
	EM_PH_LOAD: db "expected first program header to be LOAD",0
	EM_ELF_UNSUPPORTED: db "not ELF EXEC or DYN file, unsupported type",0
	EM_UPX: db "file is packed with upx, unsupported",0

; fd's
	STDIN: equ 0
	STDOUT: equ 1
	STDERR: equ 2

; syscalls
	SYS_READ: equ 0
	SYS_WRITE: equ 1
	SYS_OPEN: equ 2
	SYS_CLOSE: equ 3
	SYS_FSTAT: equ 5
	SYS_MMAP: equ 9
	SYS_MUNMAP: equ 11
	SYS_IOCTL: equ 16
	SYS_MSYNC: equ 26
	SYS_EXIT: equ 60

; syscall params
	MAP_SHARED: equ 1
	TCGETS: equ 0x00005401
	SIZEOF_TERMIOS: equ 60  ; From: 'struct termios x; print sizeof(x)'
	MS_SYNC: equ 4			; msync synchronous because we exit soon after

; err codes
	ERR0: db "",0 ; never happens
	ERR1: db "EPERM Operation not permitted",10,0
	ERR2: db "ENOENT No such file or directory",10,0
	ERR3: db "ESRCH No such process",10,0
	ERR4: db "EINTR Interrupted system call",10,0
	ERR5: db "EIO I/O error ",10,0
	ERR6: db "ENXIO No such device or address",10,0
	ERR7: db "E2BIG Argument list too long",10,0
	ERR8: db "ENOEXEC Exec format error",10,0
	ERR9: db "EBADF Bad file number ",10,0
	ERR10: db "ECHILD No child processes",10,0
	ERR11: db "EAGAIN Try again",10,0
	ERR12: db "ENOMEM Out of memory",10,0
	ERR13: db "EACCES Permission denied",10,0
	ERR14: db "EFAULT Bad address",10,0
	ERR15: db "ENOTBLK Block device required",10,0
	ERR16: db "EBUSY Device or resource busy",10,0
	ERR17: db "EEXIST File exists",10,0
	ERR18: db "EXDEV Cross-device link",10,0
	ERR19: db "ENODEV No such device",10,0
	ERR20: db "ENOTDIR Not a directory",10,0
	ERR21: db "EISDIR Is a directory",10,0
	ERR22: db "EINVAL Invalid argument",10,0
	ERR23: db "ENFILE File table overflow",10,0
	ERR24: db "EMFILE Too many open files",10,0
	ERR25: db "ENOTTY Not a typewriter",10,0
	ERR26: db "ETXTBSY Text file busy",10,0
	ERR27: db "EFBIG File too large",10,0
	ERR28: db "ENOSPC No space left on device",10,0
	ERR29: db "ESPIPE Illegal seek",10,0
	ERR30: db "EROFS Read-only file system",10,0
	ERR31: db "EMLINK Too many links",10,0
	ERR32: db "EPIPE Broken pipe",10,0
	ERR33: db "EDOM	 Math argument out of domain of func",10,0
	ERR34: db "ERANGE Math result not representable",10,0
	ERR35: db "",10,0 ; custom error, no code or name
	ERRS: dq ERR0, ERR1, ERR2, ERR3, ERR4, ERR5, ERR6, ERR7, ERR8, ERR9, ERR10, ERR11, ERR12, ERR13, ERR14, ERR15, ERR16, ERR17, ERR18, ERR18, ERR20, ERR21, ERR22, ERR23, ERR24, ERR25, ERR26, ERR27, ERR28, ERR29, ERR30, ERR31, ERR32, ERR33, ERR34, ERR35
	ERRS_BYTE_LEN: equ $-ERRS  ; will need to divide by 8 to get num items
