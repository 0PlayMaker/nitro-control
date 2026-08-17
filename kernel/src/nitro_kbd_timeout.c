// SPDX-License-Identifier: GPL-2.0
/*
 * nitro_kbd_timeout - expose the Acer EC's keyboard-backlight idle timeout.
 *
 * The EC blanks the keyboard backlight ~30 s after the last physical keypress
 * and re-lights it on the next one, regardless of what anything else writes
 * over WMI. NitroSense on Windows toggles this through the Acer gaming WMI
 * interface; nothing in the mainline acer-wmi / facer drivers exposes it.
 *
 * /sys/kernel/nitro_kbd/backlight_timeout
 *      seconds before the EC blanks the backlight; 0 disables it entirely.
 *
 * The 48-bit word this interface passes around is laid out as
 *
 *      [ 47:40 timeout secs ][ 39:32 aux ][ 31:0 subcommand ]
 *
 * where the subcommand is 0x00088401 to read and 0x00088402 to write, and the
 * read-back reports 0x00080000 there instead. "aux" is some second setting
 * that shares the word - it reads 0x64 (100) on this AN517-41, so it is most
 * likely a brightness percentage. Nothing here needs to know what it is; it
 * is read and written straight back so a timeout change cannot disturb it.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/acpi.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>

#define WMID_GUID3		"61EF69EA-865C-4BC3-A502-A0DEBA0CB531"

#define ACER_WMID_SET_FUNCTION	1
#define ACER_WMID_GET_FUNCTION	2

#define KBT_CMD_GET		0x00088401ULL
#define KBT_CMD_SET		0x00088402ULL

#define KBT_SECS(raw)		((u8)(((raw) >> 40) & 0xFF))
#define KBT_AUX(raw)		((u8)(((raw) >> 32) & 0xFF))
#define KBT_WORD(secs, aux)	(((u64)(secs) << 40) | ((u64)(aux) << 32) | KBT_CMD_SET)

static int timeout = -1;
module_param(timeout, int, 0444);
MODULE_PARM_DESC(timeout, "seconds to apply at load: 0 = disable, -1 = leave alone");

static struct kobject *nitro_kobj;

static acpi_status acer_gaming_u64(u32 method_id, u64 in, u64 *out)
{
	struct acpi_buffer input = { (acpi_size)sizeof(u64), (void *)&in };
	struct acpi_buffer result = { ACPI_ALLOCATE_BUFFER, NULL };
	union acpi_object *obj;
	acpi_status status;
	u64 tmp = 0;

	status = wmi_evaluate_method(WMID_GUID3, 0, method_id, &input, &result);
	if (ACPI_FAILURE(status))
		return status;

	obj = (union acpi_object *)result.pointer;
	if (obj) {
		if (obj->type == ACPI_TYPE_BUFFER) {
			if (obj->buffer.length == sizeof(u32))
				tmp = *((u32 *)obj->buffer.pointer);
			else if (obj->buffer.length == sizeof(u64))
				tmp = *((u64 *)obj->buffer.pointer);
		} else if (obj->type == ACPI_TYPE_INTEGER) {
			tmp = (u64)obj->integer.value;
		}
	}

	if (out)
		*out = tmp;

	kfree(result.pointer);
	return status;
}

static int kbt_get(u64 *raw)
{
	acpi_status status = acer_gaming_u64(ACER_WMID_GET_FUNCTION,
					     KBT_CMD_GET, raw);

	if (ACPI_FAILURE(status)) {
		pr_err("nitro_kbd_timeout: get failed: %s\n",
		       acpi_format_exception(status));
		return -ENODEV;
	}
	return 0;
}

static int kbt_set(u8 secs)
{
	acpi_status status;
	u64 cur = 0, word, result = 0;
	int err;

	/* Read first so the field sharing this word is written back untouched. */
	err = kbt_get(&cur);
	if (err)
		return err;

	word = KBT_WORD(secs, KBT_AUX(cur));
	status = acer_gaming_u64(ACER_WMID_SET_FUNCTION, word, &result);
	if (ACPI_FAILURE(status)) {
		pr_err("nitro_kbd_timeout: set failed: %s\n",
		       acpi_format_exception(status));
		return -ENODEV;
	}
	pr_info("nitro_kbd_timeout: set %us (word 0x%llx) -> 0x%llx\n",
		secs, word, result);
	return 0;
}

static ssize_t backlight_timeout_show(struct kobject *kobj,
				      struct kobj_attribute *attr, char *buf)
{
	u64 raw = 0;
	int err = kbt_get(&raw);

	if (err)
		return err;

	return sysfs_emit(buf, "%u\n", KBT_SECS(raw));
}

static ssize_t backlight_timeout_store(struct kobject *kobj,
				       struct kobj_attribute *attr,
				       const char *buf, size_t count)
{
	u8 secs;
	int err;

	err = kstrtou8(buf, 10, &secs);
	if (err)
		return err;

	err = kbt_set(secs);
	return err ? err : count;
}

static struct kobj_attribute backlight_timeout_attr =
	__ATTR(backlight_timeout, 0644, backlight_timeout_show, backlight_timeout_store);

/* Raw read-out, so the encoding can be checked without guessing. */
static ssize_t raw_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	u64 raw = 0;
	int err = kbt_get(&raw);

	if (err)
		return err;
	return sysfs_emit(buf, "0x%llx\n", raw);
}

static struct kobj_attribute raw_attr = __ATTR_RO(raw);

static struct attribute *kbt_attrs[] = {
	&backlight_timeout_attr.attr,
	&raw_attr.attr,
	NULL,
};

static const struct attribute_group kbt_group = {
	.attrs = kbt_attrs,
};

static int __init kbt_init(void)
{
	u64 raw = 0;
	int err;

	if (!wmi_has_guid(WMID_GUID3)) {
		pr_err("nitro_kbd_timeout: WMI GUID %s not present\n", WMID_GUID3);
		return -ENODEV;
	}

	if (!kbt_get(&raw))
		pr_info("nitro_kbd_timeout: EC reports raw 0x%llx (timeout %us, aux %u)\n",
			raw, KBT_SECS(raw), KBT_AUX(raw));

	nitro_kobj = kobject_create_and_add("nitro_kbd", kernel_kobj);
	if (!nitro_kobj)
		return -ENOMEM;

	err = sysfs_create_group(nitro_kobj, &kbt_group);
	if (err) {
		kobject_put(nitro_kobj);
		return err;
	}

	if (timeout >= 0 && timeout <= 255)
		kbt_set((u8)timeout);

	return 0;
}

static void __exit kbt_exit(void)
{
	if (nitro_kobj) {
		sysfs_remove_group(nitro_kobj, &kbt_group);
		kobject_put(nitro_kobj);
	}
}

module_init(kbt_init);
module_exit(kbt_exit);

MODULE_AUTHOR("PlayMaker");
MODULE_DESCRIPTION("Acer Nitro keyboard-backlight EC idle timeout control");
MODULE_LICENSE("GPL");
