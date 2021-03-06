/*
 *  linux/arch/arm/mm/proc-v7m.S
 *
 *  Copyright (C) 2008 ARM Ltd.
 *  Copyright (C) 2001 Deep Blue Solutions Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 *  This is the "shell" of the ARMv7-M processor support.
 */
#include <linux/linkage.h>
#include <asm/assembler.h>
#include <asm/memory.h>
#include <asm/v7m.h>
#include "proc-macros.S"

ENTRY(cpu_v7m_proc_init)
	ret	lr
ENDPROC(cpu_v7m_proc_init)

ENTRY(cpu_v7m_proc_fin)
	ret	lr
ENDPROC(cpu_v7m_proc_fin)

/*
 *	cpu_v7m_reset(loc)
 *
 *	Perform a soft reset of the system.  Put the CPU into the
 *	same state as it would be if it had been reset, and branch
 *	to what would be the reset vector.
 *
 *	- loc   - location to jump to for soft reset
 */
	.align	5
ENTRY(cpu_v7m_reset)
	ret	r0
ENDPROC(cpu_v7m_reset)

/*
 *	cpu_v7m_do_idle()
 *
 *	Idle the processor (eg, wait for interrupt).
 *
 *	IRQs are already disabled.
 */
ENTRY(cpu_v7m_do_idle)
	wfi
	ret	lr
ENDPROC(cpu_v7m_do_idle)

ENTRY(cpu_v7m_dcache_clean_area)
	ret	lr
ENDPROC(cpu_v7m_dcache_clean_area)

/*
 * There is no MMU, so here is nothing to do.
 */
ENTRY(cpu_v7m_switch_mm)
	ret	lr
ENDPROC(cpu_v7m_switch_mm)

.globl	cpu_v7m_suspend_size
.equ	cpu_v7m_suspend_size, 0

#ifdef CONFIG_ARM_CPU_SUSPEND
ENTRY(cpu_v7m_do_suspend)
	ret	lr
ENDPROC(cpu_v7m_do_suspend)

ENTRY(cpu_v7m_do_resume)
	ret	lr
ENDPROC(cpu_v7m_do_resume)
#endif

	.section ".text.init", #alloc, #execinstr

/*
 *	__v7m_setup
 *
 *	This should be able to cover all ARMv7-M cores.
 */
__v7m_setup:
	@ Configure the vector table base address
	ldr	r0, =BASEADDR_V7M_SCB
	ldr	r12, =vector_table
	str	r12, [r0, V7M_SCB_VTOR]

	@ enable UsageFault, BusFault and MemManage fault.
	ldr	r5, [r0, #V7M_SCB_SHCSR]
	orr	r5, #(V7M_SCB_SHCSR_USGFAULTENA | V7M_SCB_SHCSR_BUSFAULTENA | V7M_SCB_SHCSR_MEMFAULTENA)
	str	r5, [r0, #V7M_SCB_SHCSR]

	@ Lower the priority of the SVC and PendSV exceptions
	mov	r5, #0x80000000
	str	r5, [r0, V7M_SCB_SHPR2]	@ set SVC priority
	mov	r5, #0x00800000
	str	r5, [r0, V7M_SCB_SHPR3]	@ set PendSV priority

	@ SVC to switch to handler mode. Notice that this requires sp to
	@ point to writeable memory because the processor saves
	@ some registers to the stack.
	badr	r1, 1f
	ldr	r5, [r12, #11 * 4]	@ read the SVC vector entry
	str	r1, [r12, #11 * 4]	@ write the temporary SVC vector entry
	mov	r6, lr			@ save LR
	ldr	sp, =init_thread_union + THREAD_START_SP
	cpsie	i
#ifdef CONFIG_MACH_STM32F746
	dsb
#endif
	svc	#0
1:	cpsid	i
	str	r5, [r12, #11 * 4]	@ restore the original SVC vector entry
	mov	lr, r6			@ restore LR

#ifdef CONFIG_CPU_CACHE_V7M
	stmia	sp, {r0-r7, lr}		@ v7_invalidate_l1 touches r0-r6
	bl    v7m_invalidate_l1
	@ invalidate I-Cache
	ldr r0, =BASEADDR_V7M_SCS
	mov r1, #0
	str r1, [r0, #V7M_SCS_ICIALLU]
	dsb
	isb

	/* Enable D&I-cache */
	ldr r0, =0xE000ED14	@ CCR register
	ldr r6, [r0]
	mov r5, #0x07
	lsl r5, r5, #16
	orr r5, r5, r6
	str r5, [r0]
	dsb
	isb
	ldmia	sp, {r0-r7, lr}
#endif

	@ Special-purpose control register
	mov	r1, #1
	msr	control, r1		@ Thread mode has unpriviledged access

	@ Configure the System Control Register to ensure 8-byte stack alignment
	@ Note the STKALIGN bit is either RW or RAO.
	ldr	r12, [r0, V7M_SCB_CCR]	@ system control register
	orr	r12, #V7M_SCB_CCR_STKALIGN
	str	r12, [r0, V7M_SCB_CCR]
	ret	lr
ENDPROC(__v7m_setup)

	define_processor_functions v7m, dabort=nommu_early_abort, pabort=legacy_pabort, nommu=1

	.section ".rodata"
	string cpu_arch_name, "armv7m"
	string cpu_elf_name "v7m"
	string cpu_v7m_name "ARMv7-M"

	.section ".proc.info.init", #alloc

	/*
	 * Match any ARMv7-M processor core.
	 */
	.type	__v7m_proc_info, #object
__v7m_proc_info:
	.long	0x000f0000		@ Required ID value
	.long	0x000f0000		@ Mask for ID
	.long   0			@ proc_info_list.__cpu_mm_mmu_flags
	.long   0			@ proc_info_list.__cpu_io_mmu_flags
	initfn	__v7m_setup, __v7m_proc_info	@ proc_info_list.__cpu_flush
	.long	cpu_arch_name
	.long	cpu_elf_name
	.long	HWCAP_HALF|HWCAP_THUMB|HWCAP_FAST_MULT
	.long	cpu_v7m_name
	.long	v7m_processor_functions	@ proc_info_list.proc
	.long	0			@ proc_info_list.tlb
	.long	0			@ proc_info_list.user
#ifdef CONFIG_CPU_CACHE_NOP
	.long	nop_cache_fns		@ proc_info_list.cache
#else
	.long v7m_cache_fns		@ proc_info_list.cache
#endif
	.size	__v7m_proc_info, . - __v7m_proc_info
