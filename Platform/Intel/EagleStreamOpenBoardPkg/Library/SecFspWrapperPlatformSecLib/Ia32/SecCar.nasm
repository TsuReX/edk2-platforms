bits 32

CR0_CD		equ (0x1 << 29)
CR0_NW		equ (0x1 << 30)

NEM			equ 0x000002E0
NEM_RUN			equ (0x1 << 1)
NEM_SETUP		equ (0x1 << 0)

IA32_MTRR_CAP			equ 0x000000FE

IA32_MTRR_DEF_TYPE		equ 0x000002FF
IA32_MTRR_DEF_TYPE_EN		equ (0x1 << 11)
IA32_MTRR_DEF_TYPE_FE		equ (0x1 << 10)
IA32_MTRR_DEF_TYPE_MEMTYPE_WP	equ (0x5 << 0)
IA32_MTRR_DEF_TYPE_MEMTYPE_WB	equ (0x6 << 0)

IA32_MTRR_PHYS_BASE_0	equ 0x00000200
IA32_MTRR_PHYS_BASE_1	equ 0x00000202

IA32_MTRR_PHYS_MASK_0	equ 0x00000201
IA32_MTRR_PHYS_MASK_1	equ 0x00000203
IA32_MTRR_PHYS_MASK_VALID	equ (0x1 << 11)

DATA_STACK_BASE_ADDRESS		equ 0x00000000
DATA_STACK_SIZE			equ 0x00010000
DATA_STACK_SIZE_MASK		equ ( ~(DATA_STACK_SIZE - 1))
CODE_REGION_BASE_ADDRESS	equ 0xFFFFF000
CODE_REGION_SIZE		equ 0x00001000
CODE_REGION_SIZE_MASK		equ ( ~(CODE_REGION_SIZE - 1))

IA32_MTRR_FIX_64K_00000		equ 0x250
IA32_MTRR_FIX_16K_80000		equ 0x258
IA32_MTRR_FIX_16K_A0000		equ 0x259
IA32_MTRR_FIX_4K_C0000		equ 0x268
IA32_MTRR_FIX_4K_C8000		equ 0x269
IA32_MTRR_FIX_4K_D0000		equ 0x26a
IA32_MTRR_FIX_4K_D8000		equ 0x26b
IA32_MTRR_FIX_4K_E0000		equ 0x26c
IA32_MTRR_FIX_4K_E8000		equ 0x26d
IA32_MTRR_FIX_4K_F0000		equ 0x26e
IA32_MTRR_FIX_4K_F8000		equ 0x26f

IA32_MISC_ENABLE		equ 0x000001A0
IA32_MISC_ENABLE_FAST_STRINGS	equ (0x1 << 0)

global setup_car

section .text

;594768_3rd Gen Intel Xeon Scalable Processors_BWG_Rev1p4
;5.3.1 Enabling Cache for Stack and Code Use Prior to Memory Initialization
setup_car:

;Use the MTRR default type MSR as a proxy for detecting INIT#.
;Reset the system if any known bits are set in that MSR. That is
;an indication of the CPU not being properly reset.

check_for_clean_reset:
    mov ecx, IA32_MTRR_DEF_TYPE
    rdmsr
    and eax, (IA32_MTRR_DEF_TYPE_EN | IA32_MTRR_DEF_TYPE_FE)
    cmp eax, 0x0
    jnz warm_reset
    jmp cache_as_ram

;Perform warm reset
warm_reset:
    mov dx, 0x0CF9
    mov al, 0x06
    out dx, al

cache_as_ram:

;0
;Disable Fast_String support prior to NEM
    mov ecx, IA32_MISC_ENABLE
    rdmsr
    and eax, ~IA32_MISC_ENABLE_FAST_STRINGS
    wrmsr

;1
;Send INIT IPI to all excluding ourself.
;    mov eax, 0x000C4500
;    mov esi, 0xFEE00300
;    mov [esi], eax

;1.1
;All CPUs need to be in Wait for SIPI state
;wait_for_sipi:
;    mov eax,[esi]
;    bt eax, 12
;    jc wait_for_sipi

;5
;Clean-up IA32_MTRR_DEF_TYPE
    mov ecx, IA32_MTRR_DEF_TYPE
    xor eax, eax
    xor edx, edx
    wrmsr

;2
;Load microcode update into each NBSP
;TODO

;4 Clear/disable fixed MTRRs
    mov ebx, fixed_mtrr_list
    xor eax, eax
    xor edx, edx
clear_fixed_mtrr:
    movzx ecx, word [ebx]; ??? word ???
    wrmsr
    add ebx, 0x2
    cmp ebx, fixed_mtrr_list_end
    jl clear_fixed_mtrr

;3
;Zero out all variable range MTRRs.
    mov ecx, IA32_MTRR_CAP
    rdmsr
    and eax, 0xFF
    shl eax, 0x1
    mov edi, eax
    mov ecx, 0x200
    xor eax, eax
    xor edx, edx
clear_var_mtrrs:
    wrmsr
    add ecx, 0x1
    dec edi
    jnz clear_var_mtrrs


; Configure MTRR_PHYS_MASK_HIGH for proper addressing above 4GB
; based on the physical address size supported for this processor
; This is based on read from CPUID.(EAX=080000008h), EAX bits [7:0]
;
; Examples:
; MTRR_PHYS_MASK_HIGH = 00000000Fh For 36 bit addressing
; MTRR_PHYS_MASK_HIGH = 0000000FFh For 40 bit addressing
; MTRR_PHYS_MASK_HIGH = 00000FFFFh For 48 bit addressing
;
    mov eax, 80000008h	; Address sizes leaf
    cpuid
    sub al, 32		;!IF! al == 48 -> al = 48 - 32 = 16 
    movzx eax, al	;eax = al -> eax == 16	
    xor esi, esi	;esi = 0
    bts esi, eax	;esi[eax] = 1 -> esi[16] = 1 -> esi == 0b00000001.00000000.00000000 == 0x1.0000 == (1 << 16)
    dec esi		;esi = esi - 1 -> esi = 0x1.0000 - 1 -> esi = 0xFFFF

;7,8
;Configure the DataStack region as write-back (WB) cacheable memory type using the variable range MTRRs.
;For more details see 64-ia-32-architectures-software-developer-vol-3a-part-1-manual, chapter 11.11 MEMORY TYPE RANGE REGISTERS (MTRRS)

    mov eax, (((DATA_STACK_BASE_ADDRESS & (~0xFFF)) & ((1 << 32) - 1))| IA32_MTRR_DEF_TYPE_MEMTYPE_WB)	; Load lower part([31..12] bits
					    ; base is 4kB page aligned!!!) of base and region type
    mov edx, (DATA_STACK_BASE_ADDRESS >> 32)						; Load upper part(12bits) of base
    and edx, esi
;    xor edx, edx						; clear upper dword
    mov ecx, IA32_MTRR_PHYS_BASE_0				; Load the MTRR index
    wrmsr							; the value in MTRR_PHYS_BASE_0

    mov eax, (((DATA_STACK_SIZE_MASK & (~0xFFF)) & ((1 << 32) - 1)) | IA32_MTRR_PHYS_MASK_VALID)	; turn on the Valid flag
    mov edx, esi						; edx <- MTRR_PHYS_MASK_HIGH
    mov ecx, IA32_MTRR_PHYS_MASK_0				; Load the MTRR index
    wrmsr 							; the value in MTRR_PHYS_BASE_0

;9,10
;Configure the CodeRegion region as write-protected (WP) cacheable memory type using the variable range MTRRs.

    mov eax, (((CODE_REGION_BASE_ADDRESS & (~0xFFF)) & ((1 << 32) - 1)) | IA32_MTRR_DEF_TYPE_MEMTYPE_WP)	; Load the write-protected cache value
;    xor edx, edx						; clear upper dword
    mov edx, (CODE_REGION_BASE_ADDRESS >> 32)
    and edx,  esi
    mov ecx, IA32_MTRR_PHYS_BASE_1				; Load the MTRR index
    wrmsr							; the value in MTRR_PHYS_BASE_1

    mov eax, (((CODE_REGION_SIZE_MASK & (~0xFFF)) & ((1 << 32) - 1)) | IA32_MTRR_PHYS_MASK_VALID)	; turn on the Valid flag
    mov edx, esi						; edx <- MTRR_PHYS_MASK_HIGH
    mov ecx, IA32_MTRR_PHYS_MASK_1				; Load the MTRR index
    wrmsr

;11
;Enable the MTRRs by setting the IA32_MTRR_DEF_TYPE
    mov ecx, IA32_MTRR_DEF_TYPE
    rdmsr
    or eax, IA32_MTRR_DEF_TYPE_EN
    wrmsr

;12
;Enable the logical processor's (BSP) cache
    invd
    mov eax, cr0
    and eax, ~(CR0_NW | CR0_CD)	;Reset NW and CD bits
    mov cr0, eax

;13
;Enable No-Eviction Mode Setup State by setting NO_EVICT_MODE
    mov ecx, NEM	;Read MSR NEM
    rdmsr
    or eax, NEM_SETUP	;Set SETUP bit
    wrmsr

;14
;One location in each 64-byte cache line of the DataStack region must be written to
;set all cached values to the modified state.
    mov edi, DATA_STACK_BASE_ADDRESS
    mov ecx, DATA_STACK_SIZE / 64
    mov eax, 0x12345678
clear_loop:
    mov[edi], eax
    add edi, 64
    loop clear_loop

;15
;Enable No-Eviction Mode Run State by setting NO_EVICT_MODE
    mov ecx, NEM
    rdmsr
    or eax, NEM_RUN	;Set RUN bit
    wrmsr

    mov ecx, DATA_STACK_BASE_ADDRESS
    mov edx, DATA_STACK_SIZE - 1
    add edx, ecx
    jmp ebp

fixed_mtrr_list:
    DW IA32_MTRR_FIX_64K_00000
    DW IA32_MTRR_FIX_16K_80000
    DW IA32_MTRR_FIX_16K_A0000
    DW IA32_MTRR_FIX_4K_C0000
    DW IA32_MTRR_FIX_4K_C8000
    DW IA32_MTRR_FIX_4K_D0000
    DW IA32_MTRR_FIX_4K_D8000
    DW IA32_MTRR_FIX_4K_E0000
    DW IA32_MTRR_FIX_4K_E8000
    DW IA32_MTRR_FIX_4K_F0000
    DW IA32_MTRR_FIX_4K_F8000
fixed_mtrr_list_end: