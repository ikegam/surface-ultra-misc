// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra (N1X): record how far each system suspend got, in a
 * non-volatile UEFI variable, so that a suspend which powers the SoC off
 * leaves a trace. The journal cannot help there: everything after
 * "Performing sleep operation" stays in RAM and is lost with the power.
 *
 * The suspend_resume tracepoint marks each phase of the PM core. At the
 * phases listed in stages[] the module rewrites the variable
 * N1XSleepTrace-e592f01a-04b3-4563-8c48-1035716f772f with the phase name,
 * the suspend number in this boot and the wall-clock time the suspend
 * started. After a power-off, the variable still holds the last phase that
 * was reached; n1x-sleep-collect reads it at the next boot.
 *
 * Writes use the non-blocking runtime-service path (as efi-pstore does in
 * panic), so they are safe from the late suspend phases. About ten small
 * writes per suspend/resume cycle.
 */
#include <linux/efi.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/string.h>
#include <linux/timekeeping.h>
#include <trace/events/power.h>

#define TRACE_MAGIC	0x5331584e	/* "NX1S" */
#define TRACE_VERSION	3

static efi_char16_t var_name[] = {
	'N', '1', 'X', 'S', 'l', 'e', 'e', 'p', 'T', 'r', 'a', 'c', 'e', 0 };
static efi_guid_t var_guid = EFI_GUID(0xe592f01a, 0x04b3, 0x4563,
	0x8c, 0x48, 0x10, 0x35, 0x71, 0x6f, 0x77, 0x2f);

struct n1x_sleep_record {
	__le32 magic;
	__le32 version;
	__le32 seq;		/* suspend number in this boot, from 1 */
	__le32 writes;		/* writes in this suspend */
	__le64 started;		/* wall clock (s) at suspend_enter */
	__le64 mono_ms;		/* CLOCK_MONOTONIC (ms) at this write */
	u8 start;		/* 1 = phase begins, 0 = phase done */
	u8 pad;
	__le16 freezes;		/* timekeeping freezes (DRIPS entries) so far */
	__le16 thaws;		/* timekeeping thaws (DRIPS exits) so far */
	u8 pad2[2];
	char stage[24];
} __packed;

/* Phases worth a write. machine_suspend:1 is the s2idle entry itself. */
static const struct { const char *action; bool start; } stages[] = {
	{ "suspend_enter", true },
	{ "freeze_processes", false },
	{ "dpm_suspend", true },
	{ "dpm_suspend_late", true },
	{ "dpm_suspend_noirq", true },
	{ "dpm_suspend_noirq", false },
	{ "machine_suspend", true },
	/*
	 * timekeeping_freeze:1 = the last CPU is about to enter the platform
	 * idle state (DRIPS); :0 = the first CPU is back. Only the first
	 * FREEZE_WRITES of each are written (see n1x_probe).
	 */
	{ "timekeeping_freeze", true },
	{ "timekeeping_freeze", false },
	{ "dpm_resume_noirq", true },
	{ "dpm_complete", false },	/* last resume phase: suspend fully done */
};

static bool enable = true;
module_param(enable, bool, 0644);
MODULE_PARM_DESC(enable, "write the UEFI variable (default: on)");

static struct n1x_sleep_record rec;
static unsigned int seq, failures;
static bool in_s2idle;
static unsigned int freezes, thaws;
#define FREEZE_WRITES	3
module_param(seq, uint, 0444);
MODULE_PARM_DESC(seq, "suspends recorded in this boot");
module_param(failures, uint, 0444);
MODULE_PARM_DESC(failures, "UEFI variable writes that failed");

static void n1x_write(const char *action, bool start)
{
	efi_status_t st;

	rec.writes = cpu_to_le32(le32_to_cpu(rec.writes) + 1);
	rec.mono_ms = cpu_to_le64(ktime_get_ns() / NSEC_PER_MSEC);
	rec.start = start;
	strscpy(rec.stage, action, sizeof(rec.stage));

	st = efi.set_variable_nonblocking(var_name, &var_guid,
			EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS |
			EFI_VARIABLE_RUNTIME_ACCESS, sizeof(rec), &rec);
	if (st != EFI_SUCCESS)
		failures++;
}

static void n1x_probe(void *data, const char *action, int val, bool start)
{
	size_t i;

	if (!enable || !action)
		return;

	if (!strcmp(action, "suspend_enter") && start) {
		seq++;
		in_s2idle = false;
		memset(&rec, 0, sizeof(rec));
		rec.magic = cpu_to_le32(TRACE_MAGIC);
		rec.version = cpu_to_le32(TRACE_VERSION);
		rec.seq = cpu_to_le32(seq);
		rec.started = cpu_to_le64(ktime_get_real_seconds());
		freezes = thaws = 0;
	}
	if (!rec.magic)
		return;		/* loaded in the middle of a suspend */

	/* s2idle re-enters machine_suspend on spurious wakeups: write once. */
	if (!strcmp(action, "machine_suspend") && start) {
		if (in_s2idle)
			return;
		in_s2idle = true;
	}

	/* Count every DRIPS entry/exit, write only the first few. */
	if (!strcmp(action, "timekeeping_freeze")) {
		if (start)
			freezes++;
		else
			thaws++;
		rec.freezes = cpu_to_le16(min(freezes, 0xffffu));
		rec.thaws = cpu_to_le16(min(thaws, 0xffffu));
		if ((start ? freezes : thaws) > FREEZE_WRITES)
			return;
	}

	for (i = 0; i < ARRAY_SIZE(stages); i++) {
		if (stages[i].start == start && !strcmp(stages[i].action, action)) {
			n1x_write(action, start);
			return;
		}
	}
}

static int __init n1x_sleep_trace_init(void)
{
	if (!efi_rt_services_supported(EFI_RT_SUPPORTED_SET_VARIABLE) ||
	    !efi.set_variable_nonblocking) {
		pr_err("n1x_sleep_trace: no UEFI SetVariable at runtime\n");
		return -ENODEV;
	}
	return register_trace_suspend_resume(n1x_probe, NULL);
}

static void __exit n1x_sleep_trace_exit(void)
{
	unregister_trace_suspend_resume(n1x_probe, NULL);
	tracepoint_synchronize_unregister();
}

module_init(n1x_sleep_trace_init);
module_exit(n1x_sleep_trace_exit);

MODULE_DESCRIPTION("Surface Laptop Ultra (N1X): record suspend progress in a UEFI variable");
MODULE_LICENSE("GPL");
