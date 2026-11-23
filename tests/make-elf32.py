"""ELF a 32 bit minimo (articolo 3): esegue solo exit(42) con int 0x80.
Con ia32_emulation=0 il kernel lo rifiuta ("Exec format error", codice 126);
dove l'emulazione è attiva esce con 42. Uso: python3 tests/make-elf32.py > e32"""
import struct
import sys

code = bytes([0xB8, 1, 0, 0, 0,      # mov eax, 1   (sys_exit)
              0xBB, 42, 0, 0, 0,     # mov ebx, 42  (codice di uscita)
              0xCD, 0x80])           # int 0x80
base, ehsize, phsize = 0x08048000, 52, 32
size = ehsize + phsize + len(code)
elf_header = (b"\x7fELF\x01\x01\x01" + b"\0" * 9 +
              struct.pack("<HHIIIIIHHHHHH", 2, 3, 1, base + ehsize + phsize, ehsize,
                          0, 0, ehsize, phsize, 1, 0, 0, 0))
program_header = struct.pack("<IIIIIIII", 1, 0, base, base, size, size, 5, 0x1000)
sys.stdout.buffer.write(elf_header + program_header + code)
