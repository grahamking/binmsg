; ELF header
; https://refspecs.linuxbase.org/elf/gabi4+/ch4.eheader.html
struc elf64
	.e_ident		resd 1
	.unused			resd 3
	.e_type			resw 1
	.e_machine		resw 1
	.e_version		resd 1
	.e_entry		resq 1
	.e_phoff		resq 1
	.e_shoff		resq 1
	.e_flags		resd 1
	.e_ehsize		resw 1
	.e_phentsize	resw 1
	.e_phnum		resw 1
	.e_shentsize	resw 1
	.e_shnum		resw 1
	.e_shstrndx		resw 1
endstruc

; ELF Program header
; https://refspecs.linuxbase.org/elf/gabi4+/ch5.pheader.html
struc elf64_phdr
	.p_type resd 1
	.p_flags resd 1
	.p_offset resq 1
	.p_vaddr resq 1
	.p_paddr resq 1
	.p_filesz resq 1
	.p_memsz resq 1
	.p_align resq 1
endstruc

; ELF section header
; https://refspecs.linuxbase.org/elf/gabi4+/ch4.sheader.html
struc elf64_shdr
	.sh_name		resd 1
	.sh_type		resd 1
	.sh_flags		resq 1
	.sh_addr		resq 1
	.sh_offset		resq 1
	.sh_size		resq 1
	.sh_link		resd 1
	.sh_info		resd 1
	.sh_addralign	resq 1
	.sh_entsize		resq 1
endstruc

