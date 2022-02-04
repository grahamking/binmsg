**This does nothing yet**. I'm just practicing x86 assembly.

Many ELF binaries have spare space at the start, often because they page-align sections. Eventually this program will copy stdin into that spare space. The ELF binary won't know and will still function.

Ideas:
	- Put a version number, build date, git hash in your binary.
	- Write some notes in there. "Use this one to fix weird customer dat files".
	- Store binary data. A (small) program within a program? Secret data for basic steganography?

Mostly it's an excuse to practice my assembly.

- Requirements: x86-64 linux, `nasm` assembler, `make`.
- Build: `make`
- Run: `echo some_data | xwrite <filename>`

The name will probably change.
