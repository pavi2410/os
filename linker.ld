OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

HIGHER_HALF_OFFSET = 0xFFFFFFFF80000000;
KERNEL_PHYS_BASE   = 0x100000;
KERNEL_VIRT_BASE   = HIGHER_HALF_OFFSET + KERNEL_PHYS_BASE;

SECTIONS
{
    /* Link at higher-half virtual addresses; load at physical 1 MB */
    . = KERNEL_VIRT_BASE;
    _kernel_start = .;

    .text ALIGN(4K) : AT(ADDR(.text) - HIGHER_HALF_OFFSET) {
        *(.text*)
    }

    .rodata ALIGN(4K) : AT(ADDR(.rodata) - HIGHER_HALF_OFFSET) {
        *(.rodata*)
    }

    .data ALIGN(4K) : AT(ADDR(.data) - HIGHER_HALF_OFFSET) {
        *(.data*)
    }

    .bss ALIGN(4K) : AT(ADDR(.bss) - HIGHER_HALF_OFFSET) {
        *(COMMON)
        *(.bss*)
    }

    _kernel_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}
