;;
;; static definitions
;; %include in .data section
;;

	MAX_FNAME_LEN: equ 100
	USAGE: db `Usage: echo data | xwrite filename\n\0`

; fd's
	STDIN: equ 0
	STDOUT: equ 1
	STDERR: equ 2

; syscalls
	SYS_WRITE: equ	1
	SYS_OPEN: equ	2
	SYS_FSTAT: equ	5
	SYS_MMAP: equ	9
	SYS_EXIT: equ	60

; err codes
	ERR0: db "NOPE",10,0
	ERR1: db "EPERM",10,0
	ERR2: db "ENOENT",10,0
	ERR3: db "ESRCH",10,0
	ERR4: db "EINTR: Interrupted system call",10,0
	ERR5: db "EIO: I/O error ",10,0
	ERR6: db "ENXIO	 No such device or address",10,0
	ERR7: db "E2BIG	 Argument list too long",10,0
	ERR8: db "ENOEXEC Exec format error",10,0
	ERR9: db "EBADF	 Bad file number ",10,0
	ERR10: db "ECHILD No child processes",10,0
	ERR11: db "EAGAIN Try again",10,0
	ERR12: db "ENOMEM Out of memory",10,0
	ERR13: db "EACCES Permission denied",10,0
	ERR14: db "EFAULT Bad address",10,0
	ERR15: db "ENOTBLK Block device required",10,0

;ERR4: db "EBUSY Device or resource busy */
;ERR4: db "EEXIST File exists */
;ERR4: db "EXDEV Cross-device link */
;ERR4: db "ENODEV No such device */
;ERR4: db "ENOTDIR Not a directory */
;ERR4: db "EISDIR Is a directory */
;ERR4: db "EINVAL Invalid argument */
;ERR4: db "ENFILE File table overflow */
;ERR4: db "EMFILE Too many open files */
;ERR4: db "ENOTTY Not a typewriter */
;ERR4: db "ETXTBSY Text file busy */
;ERR4: db "EFBIG File too large */
;ERR4: db "ENOSPC No space left on device */
;ERR4: db "ESPIPE Illegal seek */
;ERR4: db "EROFS Read-only file system */
;ERR4: db "EMLINK Too many links */
;ERR4: db "EPIPE Broken pipe */
;ERR4: db "EDOM	 Math argument out of domain of func */
;ERR4: db "ERANGE Math result not representable */
	ERRS: dq ERR0, ERR1, ERR2, ERR3, ERR4, ERR5, ERR6, ERR7, ERR8, ERR9, ERR10, ERR11, ERR12, ERR13, ERR14

