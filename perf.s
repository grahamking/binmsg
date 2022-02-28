;
; Script I've been using to test performance of small bits of assembly
; It allows comparing two different options. The displayed number isn't useful
; by itself, only as a comparison.
;
; Usage:
;  - Put the asm under test at HERE in the loop below
;    DO NOT USE r15 (or save existing if you do), it holds time stamp before test code.
;    DO NOT USE RCX (or more realistically save it), it holds loop counter.
;  - Build:
;    $ nasm -f elf64 perf.s
;    $ ld -n -N -o perf perf.o
;  - Run: ./perf
;    Repeat a few times, numbers don't vary much
;  - Then do it again for the other scenario, compare numbers, smaller means faster.
;
; This file has no dependencies on the binmsg program and vice-versa.

section .data
	;align 16
	;A_CONST: equ 100

section .bss
	; nothing here yet

section .text

global _start
_start:

	; we get far more consistent results with this
	; under 100M it doesn't help as much
	mov rcx, 100_000_000
.warm_up:
	nop
	nop
	nop
	nop
	loop .warm_up

	rdtsc	; Read Time Stamp Counter - this is the key instruction
	lfence
	mov r15, rdx
	shl r15, 32
	add r15, rax

	mov rcx, 1000  ; make this bigger if your asm is very fast
.l:
;	;
	; the code under test starts HERE
	;

	; <-- your code here. r15 must be unchanged after the loop. rcx must be unchanged at end of every loop.

	;
	; end code under test
	;
	dec ecx
	jnz .l

	lfence
	rdtsc
	; elapsed number of timestamp counters
	shl rdx, 32
	add rdx, rax
	sub rdx, r15

	; convert to string
	mov rdi, rdx
	sub rsp, 16
	mov rsi, rsp
	call itoa

	; print
	mov rdi, rsi
	mov rsi, 1 ; stdout
	call fprint
	add rsp, 16

	call exit

;;;;;;;;;
;;; Utility functions
;;;;;;;;;

;;
;; itoa: Convert number to string
;; rdi: number to convert
;; rsi: address to put converted number. Must have space.
;;
itoa:
	; prologue
	push rax
	push rbx
	push rcx
	push rdx
	push rsi
	push rdi
	push r8
	push rbp
	mov rbp, rsp
	sub rsp, 8    ; we only handle up to 8 digit numbers

	xor ecx, ecx
	mov rax, rdi  ; rax is numerator
	mov ebx, 10   ; 10 is denominator
	mov r8, rbp

_itoa_next_digit:
	; divide rax by 10 to get split digits into rax:rdx
	xor edx, edx  ; rdx to 0, it is going to get remainder
	div rbx
	add edx, 0x30	; convert to ASCII
	inc cl
	dec r8
	mov [r8], BYTE dl	; digits are in reverse order, so work down memory
							; this must be dl, a byte, so that 'movsb' can
							; move bytes later.
	test eax,  eax			; do we have more digits?
	jg _itoa_next_digit

	; now copy them from stack into memory, they will be in correct order
	cld					; clear direction flag, so we walk up
	mov rdi, rsi		; rsi had desination address
	mov rsi, r8			; source is stack
						; rcx already has string length
	rep movsb			; repeat rcx times: copy rsi++ to rdi++
	mov [rdi], BYTE 0	; null byte to terminate string

	; epilogue
	add rsp, 8
	pop rbp
	pop r8
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	pop rax

	ret

;;
;; strlen: Length of null-terminated string with addr in rdi
;; length returned in rax
;; max length 100
;;
strlen:
	push rcx
	push rdx

	xor eax, eax
	mov edx, 0xFF01		; range(01..FF), i.e. everything except null byte
	movd xmm0, edx		;  this is the range we are looking for
	sub eax, 16
	sub rdi, 16
.next:
	add eax, 16
	add rdi, 16
	pcmpistri xmm0, [rdi], 0x14	; Packed CMPare Implicit (\0 terminator) STRing
								;  returning Index.
								; 0x14 is control byte 1 01 00
								; 00: src is unsigned bytes
								; 01: range match
								; 1: negate the result (so match not in the range, i.e match \0)
	jnz .next
	add eax, ecx

	pop rdx
	pop rcx
	ret

;; Print null terimanted string to file descriptor
;; rdi: str addr
;; rsi: open file descriptor
fprint:
	push rax
	push rdx

	push rdi
	push rsi

	call strlen
	mov edx, eax ; strlen now in edx

	; write syscall
	mov eax, 1 ; SYS_WRITE
	; swap rdi/rsi from earlier push
	pop rdi  ; file descriptor now in rdi
	pop rsi  ; rsi now points at str addr

	push rcx
	push r11
	syscall
	pop r11
	pop rcx

	pop rdx
	pop rax
	ret

;;
;; exit
;; never returns
;;
exit:
	mov edi, 0  ; return code 0
	mov eax, 60 ; SYS_EXIT
	syscall
