// SPDX-License-Identifier: GPL-2.0
#include <linux/acpi.h>
#include <linux/dmi.h>
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/suspend.h>
#include <linux/sysfs.h>

static struct kobject *ec_kobj;
static DEFINE_MUTEX(state_lock);
static bool suspended;

/* F0CN35WW: 0x92 + 高地址 + 低地址读取 EC SRAM，低于 0x1000 时基址为
 * 0x80000。0x25 的 bit 6 是 Fn，bit 4 是左 Ctrl；标准 EC 窗口在 0x80400。
 * ec_transaction 使用内核 EC 锁，不绕过 ACPI，也不提供 RAM/固件写入接口。
 */
static ssize_t modifiers_show(struct kobject *kobj,
                              struct kobj_attribute *attr, char *buf)
{
    const u8 address[] = { 0x00, 0x25 };
    u8 value;
    int ret;

    mutex_lock(&state_lock);
    ret = suspended ? -EHOSTDOWN :
        ec_transaction(0x92, address, sizeof(address), &value, 1);
    mutex_unlock(&state_lock);
    return ret ? ret : sysfs_emit(buf, "%02x\n", value);
}

static struct kobj_attribute modifiers_attr = __ATTR_RO_MODE(modifiers, 0400);

static int sleep_notify(struct notifier_block *block, unsigned long event, void *data)
{
    mutex_lock(&state_lock);
    switch (event) {
    case PM_SUSPEND_PREPARE:
    case PM_HIBERNATION_PREPARE:
    case PM_RESTORE_PREPARE:
        suspended = true;
        break;
    case PM_POST_SUSPEND:
    case PM_POST_HIBERNATION:
    case PM_POST_RESTORE:
        suspended = false;
        break;
    }
    mutex_unlock(&state_lock);
    return NOTIFY_OK;
}

static struct notifier_block sleep_notifier = { .notifier_call = sleep_notify };

static int __init fn_ctrl_init(void)
{
    int ret;
    /* 固件升级后必须重新验证，不能把内部地址套用到未知 EC。 */
    if (!dmi_match(DMI_SYS_VENDOR, "LENOVO") ||
        !dmi_match(DMI_PRODUCT_NAME, "82DM") ||
        !dmi_match(DMI_BIOS_VERSION, "F0CN35WW"))
        return -ENODEV;
    ret = register_pm_notifier(&sleep_notifier);
    if (ret)
        return ret;
    ec_kobj = kobject_create_and_add("fn_ctrl_ec", kernel_kobj);
    if (!ec_kobj) {
        ret = -ENOMEM;
        goto remove_notifier;
    }
    ret = sysfs_create_file(ec_kobj, &modifiers_attr.attr);
    if (!ret)
        return 0;
    kobject_put(ec_kobj);
remove_notifier:
    unregister_pm_notifier(&sleep_notifier);
    return ret;
}

static void __exit fn_ctrl_exit(void)
{
    sysfs_remove_file(ec_kobj, &modifiers_attr.attr);
    kobject_put(ec_kobj);
    unregister_pm_notifier(&sleep_notifier);
}

module_init(fn_ctrl_init);
module_exit(fn_ctrl_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Read-only Fn state for Lenovo 82DM F0CN35WW");
