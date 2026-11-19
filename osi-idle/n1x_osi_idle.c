// SPDX-License-Identifier: GPL-2.0
/*
 * n1x_osi_idle: OS-initiated (OSI) CPU idle for the Surface Laptop Ultra (NVIDIA N1X), the way
 * Windows runs this SoC.
 *
 * Windows' PEP driver (nvpep.sys 2.27) switches PSCI to OS-initiated suspend mode at load
 * (SET_SUSPEND_MODE(OSI); PSCI_FEATURES(CPU_SUSPEND) = 0x1: OSI supported, original
 * power_state format), writes SYSRAM 0x130000 = 0x89736C41 and the "OSI" marker
 * 0x12FF00 = 0x4F5349, and calls \_SB.PEPD.ELST(1). In OSI mode only the last CPU of a power
 * domain may ask for that domain's state, and the request carries the domain's _LPI LevelID.
 * Linux's ACPI LPI idle driver only does platform-coordinated (PC) mode, so this module
 * replaces it with an equivalent driver that tracks the last CPU per domain:
 *
 *   SYSM (Standby-DRIPS 0x020100F0, LevelID 0x2000)
 *    \_ PKG0 (PGKSL 0x01010012, PGKLL 0x01010013, LevelID 0x1000)
 *        |_ CLU0 = CPUs 0-9   (DSUOFF 0x01010011, LevelID 0x1000)
 *        \_ CLU1 = CPUs 10-19 (DSUOFF 0x01010011, LevelID 0x1000)
 *             \_ core: WFI, CoreIdle-OFF 0x00010000
 *
 * A CPU that is not the last idle one in its cluster asks for CoreIdle-OFF; the last one asks
 * for the cluster/package state allowed by the shallowest choice of the CPUs it covers. A race
 * the firmware catches comes back as DENIED and the idle loop tries again. Standby-DRIPS is only
 * used from s2idle (max_depth 4 by default): at runtime, with devices running, it hangs the
 * machine (the same reason omarchy's kernel does not call ELST).
 *
 * The idle entry mirrors drivers/acpi/processor_idle.c + drivers/acpi/arm64/cpuidle.c: states
 * carry CPUIDLE_FLAG_RCU_IDLE | CPUIDLE_FLAG_TIMER_STOP and enter psci_cpu_suspend_enter()
 * through CPU_PM_CPU_IDLE_ENTER_PARAM_RCU.
 *
 * Does nothing unless enable=1. The firmware refuses to go back from OSI to PC mode, so after
 * an unload the CPUs only use WFI until the next boot.
 */
#define pr_fmt(fmt) "n1x_osi_idle: " fmt

#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/cpuidle.h>
#include <linux/cpu_pm.h>
#include <linux/cpumask.h>
#include <linux/acpi.h>
#include <linux/arm-smccc.h>
#include <linux/io.h>
#include <linux/spinlock.h>
#include <acpi/processor.h>
#include <uapi/linux/psci.h>

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "Switch to OSI idle at load (default off)");

static bool osi = true;
module_param(osi, bool, 0444);
MODULE_PARM_DESC(osi, "Switch PSCI to OS-initiated mode (0: stay platform-coordinated, test the driver only)");

/* CPU_SUSPEND results: powered down and resumed, returned at once, DENIED, INVALID_PARAMETERS, other */
static int stats[5];
module_param_array(stats, int, NULL, 0444);

/* the same per requested state (WFI, core, cluster, pkg-SL, pkg-LL, DRIPS) */
static int st_down[6], st_ret[6], st_denied[6], st_fallback[6];
module_param_array(st_down, int, NULL, 0444);
MODULE_PARM_DESC(st_down, "per state: powered down and resumed");
module_param_array(st_ret, int, NULL, 0444);
MODULE_PARM_DESC(st_ret, "per state: firmware returned at once (aborted, e.g. a wakeup was pending)");
module_param_array(st_denied, int, NULL, 0444);
MODULE_PARM_DESC(st_denied, "per state: DENIED (lost the last-CPU race)");
module_param_array(st_fallback, int, NULL, 0444);
MODULE_PARM_DESC(st_fallback, "per state: after DENIED, CoreIdle-OFF entered instead");

static bool pep = true;
module_param(pep, bool, 0444);
MODULE_PARM_DESC(pep, "In OSI mode also do nvpep.sys' ELST(1) and SYSRAM writes");

static int max_depth = 4;
module_param(max_depth, int, 0644);
MODULE_PARM_DESC(max_depth, "Deepest state outside s2idle: 1 core, 2 cluster, 3/4 package, 5 DRIPS (hangs)");

/*
 * s2idle_depth: what s2idle asks for. 5 = Standby-DRIPS (default, like Windows). Long lid-closed
 * sleeps still die inside DRIPS (BERT 0xa0000004, with and without OSI), so 4 (PGKLL) is there to
 * tell DRIPS itself apart from the package power-down. Takes effect on the next suspend.
 */
static int s2idle_depth = 5;
module_param(s2idle_depth, int, 0644);
MODULE_PARM_DESC(s2idle_depth, "State s2idle asks for: 1 core, 2 cluster, 3/4 package, 5 DRIPS (default)");

#define NCPU		20
#define CLUSTER(c)	((c) / 10)

enum { S_WFI, S_CORE, S_CLUSTER, S_PKG_SL, S_PKG_LL, S_DRIPS, S_NUM };

static struct acpi_lpi_state lpi[S_NUM] = {
	[S_WFI]     = { .address = 0xFFFFFFFF, .arch_flags = 0, .desc = "CoreIdle-WFI" },
	[S_CORE]    = { .address = 0x00010000, .arch_flags = 1, .desc = "CoreIdle-OFF" },
	[S_CLUSTER] = { .address = 0x01010011, .arch_flags = 1, .desc = "PlatIdle-DSUOFF" },
	[S_PKG_SL]  = { .address = 0x01010012, .arch_flags = 1, .desc = "PlatIdle-PGKSL" },
	[S_PKG_LL]  = { .address = 0x01010013, .arch_flags = 1, .desc = "PlatIdle-PGKLL" },
	[S_DRIPS]   = { .address = 0x020100F0, .arch_flags = 1, .desc = "Standby-DRIPS" },
};

/*
 * OSI: a composite request must also carry the LevelID of the highest container it powers
 * down (DEN0048 FFH spec; NVIDIA NV-Kernels "Add FFH hierarchy coordination hooks"): the
 * _LPI header element[1] of C0LI/C1LI 0x1000, GLPI 0x1000, SLPI 0x2000; cores 0.
 */
static const u32 level_id[S_NUM] = {
	[S_CLUSTER] = 0x1000, [S_PKG_SL] = 0x1000, [S_PKG_LL] = 0x1000, [S_DRIPS] = 0x2000,
};

static int (*ffh_lpi_enter)(struct acpi_lpi_state *lpi);
static int (*psci_enter)(u32 state);
static struct cpuidle_device * __percpu *cpuidle_devices_p;
static struct cpuidle_driver *acpi_drv;
static struct cpuidle_device *acpi_dev[NR_CPUS];
static struct cpuidle_device * __percpu *acpi_devs;	/* processor_idle.c acpi_cpuidle_device (per-CPU pointer) */
static bool active;	/* our driver is registered */

static DEFINE_RAW_SPINLOCK(dom_lock);
static struct cpumask idle_mask;	/* CPUs in CoreIdle-OFF or deeper (or offline) */
static u8 want[NR_CPUS];		/* deepest state each idle CPU allows */
static atomic_t denied = ATOMIC_INIT(0);
static atomic_t composite[S_NUM];

static unsigned long lookup(const char *name)
{
	static unsigned long (*kln)(const char *);

	if (!kln) {
		struct kprobe kp = { .symbol_name = "kallsyms_lookup_name" };

		if (register_kprobe(&kp) < 0)
			return 0;
		kln = (void *)kp.addr;
		unregister_kprobe(&kp);
	}
	return kln(name);
}

static bool idle_or_off(int cpu)
{
	return cpumask_test_cpu(cpu, &idle_mask) || !cpu_online(cpu);
}

static int min_want(int first, int last)
{
	int cpu, m = S_DRIPS;

	for (cpu = first; cpu <= last; cpu++)
		if (cpu_online(cpu))
			m = min_t(int, m, want[cpu]);
	return m;
}

/* Pick the composite state for this CPU; called with dom_lock held. */
static int pick(int cpu, int index)
{
	int c = CLUSTER(cpu), first = c * 10, i, req;

	want[cpu] = index;
	cpumask_set_cpu(cpu, &idle_mask);
	if (index < S_CLUSTER)
		return S_CORE;
	for (i = first; i < first + 10; i++)
		if (!idle_or_off(i))
			return S_CORE;
	req = min_t(int, index, min_want(first, first + 9));
	if (req < S_CLUSTER)
		return S_CORE;
	if (req == S_CLUSTER)
		return S_CLUSTER;
	for (i = 0; i < NCPU; i++)
		if (!idle_or_off(i))
			return S_CLUSTER;
	req = min_t(int, req, min_want(0, NCPU - 1));
	return max_t(int, req, S_CLUSTER);
}

/* CPU_SUSPEND with the state as-is (original format: StateType bit16 = power-down) */
static DEFINE_PER_CPU(int, cur_req);

static int fw_enter(u32 state)
{
	int r = psci_enter(state);
	int q = this_cpu_read(cur_req);

	if (r == 0)
		WRITE_ONCE(st_down[q], st_down[q] + 1);
	else if (r == -EOPNOTSUPP)
		WRITE_ONCE(st_ret[q], st_ret[q] + 1);
	else if (r == -EPERM)
		WRITE_ONCE(st_denied[q], st_denied[q] + 1);

	switch (r) {
	case 0:		WRITE_ONCE(stats[0], stats[0] + 1); break;
	case -EOPNOTSUPP: WRITE_ONCE(stats[1], stats[1] + 1); return 0;	/* came back without powering down */
	case -EPERM:	WRITE_ONCE(stats[2], stats[2] + 1); break;
	case -EINVAL:	WRITE_ONCE(stats[3], stats[3] + 1); break;
	default:	WRITE_ONCE(stats[4], stats[4] + 1); break;
	}
	return r;
}

static int __osi_enter(struct cpuidle_device *dev, int index, bool s2idle)
{
	int cpu = dev->cpu, req, ret;

	if (index == S_WFI)
		return ffh_lpi_enter(&lpi[S_WFI]);
	if (index > max_depth && !s2idle)
		index = max(max_depth, S_CORE);

	raw_spin_lock(&dom_lock);
	req = pick(cpu, index);
	raw_spin_unlock(&dom_lock);

	/*
	 * Same pairing as the ACPI LPI driver: the states carry CPUIDLE_FLAG_RCU_IDLE and the
	 * _RCU macro leaves ct_cpuidle_enter/exit to psci_cpu_suspend_enter()/cpu_suspend().
	 */
	this_cpu_write(cur_req, req);
	ret = CPU_PM_CPU_IDLE_ENTER_PARAM_RCU(fw_enter, req, (u32)lpi[req].address);
	if (ret < 0 && req > S_CORE) {
		/*
		 * DENIED: another CPU of the domain was not down yet when we asked. Stay idle
		 * with CoreIdle-OFF instead of waking up and going round the idle loop again.
		 */
		WRITE_ONCE(st_fallback[req], st_fallback[req] + 1);
		req = S_CORE;
		this_cpu_write(cur_req, S_CORE);
		ret = CPU_PM_CPU_IDLE_ENTER_PARAM_RCU(fw_enter, S_CORE, (u32)lpi[S_CORE].address);
	}

	raw_spin_lock(&dom_lock);
	cpumask_clear_cpu(cpu, &idle_mask);
	raw_spin_unlock(&dom_lock);

	if (ret < 0)
		atomic_inc(&denied);
	else if (req > S_CORE)
		atomic_inc(&composite[req]);
	return ret;
}

static int osi_enter(struct cpuidle_device *dev, struct cpuidle_driver *drv, int index)
{
	return __osi_enter(dev, index, false);
}

static int osi_enter_s2idle(struct cpuidle_device *dev, struct cpuidle_driver *drv, int index)
{
	__osi_enter(dev, clamp_t(int, READ_ONCE(s2idle_depth), S_CORE, S_DRIPS), true);
	return 0;
}

static struct cpuidle_driver osi_drv = {
	.name = "n1x_osi_idle",
	/* no .owner: module exit unregisters the driver first, so rmmod is allowed */
	.state_count = S_NUM,
	.safe_state_index = 0,
	/* latencies/residencies (us) as the ACPI driver flattened them, worst of E/P cores */
	.states = {
		{ .name = "WFI",     .desc = "CoreIdle-WFI",    .exit_latency = 1,    .target_residency = 1,
		  .enter = osi_enter },
		{ .name = "CORE",    .desc = "CoreIdle-OFF",    .exit_latency = 170,  .target_residency = 2006,
		  .enter = osi_enter, .flags = CPUIDLE_FLAG_RCU_IDLE | CPUIDLE_FLAG_TIMER_STOP },
		{ .name = "CLUSTER", .desc = "PlatIdle-DSUOFF", .exit_latency = 574,  .target_residency = 2635,
		  .enter = osi_enter, .flags = CPUIDLE_FLAG_RCU_IDLE | CPUIDLE_FLAG_TIMER_STOP },
		{ .name = "PKG-SL",  .desc = "PlatIdle-PGKSL",  .exit_latency = 574,  .target_residency = 2635,
		  .enter = osi_enter, .flags = CPUIDLE_FLAG_RCU_IDLE | CPUIDLE_FLAG_TIMER_STOP },
		{ .name = "PKG-LL",  .desc = "PlatIdle-PGKLL",  .exit_latency = 967,  .target_residency = 2635,
		  .enter = osi_enter, .flags = CPUIDLE_FLAG_RCU_IDLE | CPUIDLE_FLAG_TIMER_STOP },
		{ .name = "DRIPS",   .desc = "Standby-DRIPS",   .exit_latency = 7600, .target_residency = 20000,
		  .enter = osi_enter, .enter_s2idle = osi_enter_s2idle,
		  .flags = CPUIDLE_FLAG_RCU_IDLE | CPUIDLE_FLAG_TIMER_STOP },
	},
};

static long set_mode(unsigned long mode)
{
	struct arm_smccc_res res;

	arm_smccc_1_1_invoke(PSCI_1_0_FN_SET_SUSPEND_MODE, mode, &res);
	return (long)(int)res.a0;
}

static void sysram_w32(phys_addr_t pa, u32 val)
{
	void __iomem *p = ioremap(pa, 4);

	if (p) {
		dsb(sy);
		writel(val, p);
		iounmap(p);
	}
}

static void windows_pep_init(void)
{
	acpi_status st = acpi_execute_simple_method(NULL, "\\_SB.PEPD.ELST", 1);

	pr_info("ELST(1): %s\n", ACPI_SUCCESS(st) ? "ok" : acpi_format_exception(st));
	sysram_w32(0x130000, 0x89736C41);
	sysram_w32(0x12FF00, 0x004F5349);
}

/* Hand the CPUs back to the ACPI LPI driver (all CPUs are in WFI when this runs). */
static void restore_acpi(void)
{
	int cpu;

	if (!acpi_drv)
		return;
	if (cpuidle_register_driver(acpi_drv))
		pr_err("could not re-register %s\n", acpi_drv->name);
	for_each_possible_cpu(cpu)
		if (acpi_dev[cpu] && cpuidle_register_device(acpi_dev[cpu]))
			pr_err("cpu%d: could not re-register ACPI idle device\n", cpu);
}

static int __init osi_init(void)
{
	long r;
	int cpu, ret;

	if (!enable) {
		pr_info("disabled (n1x_osi_idle.enable=1 to use)\n");
		return 0;
	}
	if (num_possible_cpus() != NCPU) {
		pr_err("expected %d CPUs, found %u\n", NCPU, num_possible_cpus());
		return -ENODEV;
	}
	ffh_lpi_enter = (void *)lookup("acpi_processor_ffh_lpi_enter");
	psci_enter = (void *)lookup("psci_cpu_suspend_enter");
	cpuidle_devices_p = (void *)lookup("cpuidle_devices");
	/*
	 * The ACPI LPI driver by symbol, not cpuidle_get_driver(): after an unload that could not
	 * switch the firmware back to PC mode no driver is registered (CPUs in WFI) and we must
	 * still be able to load again.
	 */
	acpi_drv = (void *)lookup("acpi_idle_driver");
	acpi_devs = (void *)lookup("acpi_cpuidle_device");
	if (!ffh_lpi_enter || !psci_enter || !cpuidle_devices_p || !acpi_drv || !acpi_devs) {
		pr_err("symbols/driver missing (ffh %d devs %d drv %d)\n",
		       !!ffh_lpi_enter, !!cpuidle_devices_p, !!acpi_drv);
		return -ENOENT;
	}
	pr_info("current cpuidle driver: %s\n", cpuidle_get_driver() ? cpuidle_get_driver()->name : "none");

	for (cpu = 0; cpu < S_NUM; cpu++) {
		lpi[cpu].index = cpu;
		if (osi)
			lpi[cpu].address += level_id[cpu];
	}
	for (cpu = 0; cpu < S_NUM; cpu++)
		atomic_set(&composite[cpu], 0);

	/* 0. check everything before touching anything: only the ACPI LPI driver, or nothing */
	if (cpuidle_get_driver() && cpuidle_get_driver() != acpi_drv) {
		pr_err("unexpected cpuidle driver %s\n", cpuidle_get_driver()->name);
		return -EBUSY;
	}
	for_each_possible_cpu(cpu) {
		struct cpuidle_device *cur = *per_cpu_ptr(cpuidle_devices_p, cpu);

		acpi_dev[cpu] = *per_cpu_ptr(acpi_devs, cpu);
		if (cur && cur != acpi_dev[cpu]) {
			pr_err("cpu%d: unexpected cpuidle device\n", cpu);
			return -EBUSY;
		}
	}

	/*
	 * From here on the load never fails: a failed module is freed at once, and a CPU still
	 * inside its idle code would jump into freed memory (2026-11-19 boot panic). On any
	 * problem the module stays loaded and inactive, the CPUs use WFI until reboot.
	 */

	/* 1. take every CPU off the ACPI driver: they fall back to WFI (PSCI "running") */
	for_each_possible_cpu(cpu)
		if (*per_cpu_ptr(cpuidle_devices_p, cpu))
			cpuidle_unregister_device(acpi_dev[cpu]);
	if (cpuidle_get_driver() == acpi_drv)
		cpuidle_unregister_driver(acpi_drv);
	for_each_possible_cpu(cpu)
		if (*per_cpu_ptr(cpuidle_devices_p, cpu)) {
			pr_err("cpu%d: ACPI idle device still registered; inactive, WFI until reboot\n", cpu);
			return 0;
		}

	/* 2. same steps as nvpep.sys at load */
	r = osi ? set_mode(PSCI_1_0_SUSPEND_MODE_OSI) : 0;
	pr_info("SET_SUSPEND_MODE(OSI) = %ld%s\n", r, osi ? "" : " (skipped: osi=0, PC mode)");
	if (r) {
		/* mode unknown: the ACPI driver would spin if it is OSI, so stay in WFI */
		pr_err("could not switch to OSI; inactive, WFI until reboot\n");
		return 0;
	}
	if (osi && pep)
		windows_pep_init();	/* the OSI marker would be wrong in PC mode */

	/* 3. our driver (cpuidle_register() undoes its own partial registration) */
	ret = cpuidle_register(&osi_drv, NULL);
	if (ret) {
		r = osi ? set_mode(PSCI_1_0_SUSPEND_MODE_PC) : 0;
		pr_err("cpuidle_register: %d; back to PC mode: %ld\n", ret, r);
		if (r == 0)
			restore_acpi();
		else
			pr_err("inactive, WFI until reboot\n");
		return 0;
	}
	active = true;
	pr_info("OSI idle active (max_depth %d, s2idle_depth %d)\n", max_depth, s2idle_depth);
	return 0;
}

static void __exit osi_exit(void)
{
	long r;
	int i;

	if (!active)
		return;

	cpuidle_unregister(&osi_drv);	/* every CPU in WFI from here */
	r = osi ? set_mode(PSCI_1_0_SUSPEND_MODE_PC) : 0;
	pr_info("SET_SUSPEND_MODE(PC) = %ld\n", r);
	/*
	 * The ACPI driver in OSI mode spins on DENIED (SoC 7 -> 25 W, then a crash), so only
	 * give the CPUs back to it if the firmware really is in PC mode. From OSI the firmware
	 * answers DENIED, so the CPUs stay in WFI until reboot.
	 */
	if (r == 0)
		restore_acpi();
	else
		pr_warn("still in OSI mode: CPUs stay in WFI until reboot\n");
	for (i = S_CLUSTER; i < S_NUM; i++)
		pr_info("%s entered %d times\n", lpi[i].desc, atomic_read(&composite[i]));
	pr_info("denied %d\n", atomic_read(&denied));
}

module_init(osi_init);
module_exit(osi_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Surface Laptop Ultra: OS-initiated PSCI idle like Windows");
