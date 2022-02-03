Many ELF binaries have spare space at the start, often because they page-align sections. Eventually this program will copy stdin into that spare space. The ELF binary won't know and will still function. A kind of steganography.

Mostly it's an excuse to pratice my assembly.

- Requirements: x86-64 linux, `nasm` assembler.
- Build: `make`
- Run: `echo some_data | xwrite <filename>`

**Not ready yet**. The name will probably also change.

