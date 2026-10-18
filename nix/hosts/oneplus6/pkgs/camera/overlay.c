// SPDX-License-Identifier: GPL-2.0-only
/* Optional live bring-up helper. Normal boots use the patched static DTB. */
#include <linux/errno.h>
#include <linux/module.h>
#include <linux/of.h>

extern const unsigned char camera_overlay_blob[];
extern const unsigned char camera_overlay_end[];
static int overlay_id;

#ifndef CAMERA_OVERLAY_GUARD_NODE
#define CAMERA_OVERLAY_GUARD_NODE "/soc@0/cci@ac4a000/i2c-bus@0/camera@10"
#endif

static int __init camera_overlay_init(void)
{
	struct device_node *node;

	if (!of_machine_is_compatible("oneplus,enchilada"))
		return -ENODEV;
	/* Applying twice would replace live camera nodes and their phandles. */
	node = of_find_node_by_path(CAMERA_OVERLAY_GUARD_NODE);
	if (node) {
		of_node_put(node);
		return -EALREADY;
	}
	return of_overlay_fdt_apply(camera_overlay_blob,
		camera_overlay_end - camera_overlay_blob, &overlay_id, NULL);
}

static void __exit camera_overlay_exit(void)
{
	of_overlay_remove(&overlay_id);
}

module_init(camera_overlay_init);
module_exit(camera_overlay_exit);
MODULE_DESCRIPTION("OnePlus 6 optional live camera device-tree overlay");
MODULE_LICENSE("GPL");
