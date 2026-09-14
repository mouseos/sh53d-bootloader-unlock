// SPDX-License-Identifier: GPL-2.0
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/reboot.h>

#define EXPECTED_SECURITY_AO_BASE 0x1001a000ULL
#define BOOT_MISC0_OFFSET         0x080
#define MISC_LOCK_KEY_OFFSET      0x100
#define RST_CON_OFFSET            0x108
#define SECURITY_AO_MIN_SIZE      0x10c

#define MISC_LOCK_KEY_MAGIC       0x0000ad98
#define USBDL_MAGIC               0x444c0000
#define USBDL_BIT_ENABLE          BIT(0)
#define USBDL_BROM_SELECT         BIT(1)
#define USBDL_TIMEOUT_MASK        0x0000fffc

static bool execute;
module_param(execute, bool, 0400);
MODULE_PARM_DESC(execute,
                 "Actually program the retained BROM request and reset");

static uint timeout_ms = 5000;
module_param(timeout_ms, uint, 0400);
MODULE_PARM_DESC(timeout_ms, "BootROM download window in milliseconds");

static u32 make_usbdl_value(uint milliseconds)
{
	u32 seconds = milliseconds / 1000;

	return USBDL_MAGIC |
	       ((seconds << 2) & USBDL_TIMEOUT_MASK) |
	       USBDL_BIT_ENABLE;
}

static int __init sh53d_brom_entry_init(void)
{
	struct device_node *node;
	struct resource resource;
	void __iomem *base;
	u32 original_boot_misc0;
	u32 original_reset_retention;
	u32 reset_retention;
	u32 usbdl_value;
	u32 readback;
	int status;

	if (timeout_ms < 1000 || timeout_ms > 60000 || timeout_ms % 1000) {
		pr_err("sh53d_brom_entry: timeout_ms must be a whole second from 1000 to 60000\n");
		return -EINVAL;
	}

	usbdl_value = make_usbdl_value(timeout_ms);
	if (usbdl_value & USBDL_BROM_SELECT) {
		pr_err("sh53d_brom_entry: internal error: bootloader-download bit set\n");
		return -EINVAL;
	}

	pr_notice("sh53d_brom_entry: planned BOOT_MISC0=0x%08x timeout_ms=%u execute=%u\n",
		  usbdl_value, timeout_ms, execute);
	if (!execute) {
		pr_notice("sh53d_brom_entry: dry run only; no MMIO or storage write performed\n");
		return 0;
	}

	node = of_find_compatible_node(NULL, NULL, "mediatek,security_ao");
	if (!node) {
		pr_err("sh53d_brom_entry: mediatek,security_ao not found\n");
		return -ENODEV;
	}
	status = of_address_to_resource(node, 0, &resource);
	if (status) {
		of_node_put(node);
		return status;
	}
	if (resource.start != EXPECTED_SECURITY_AO_BASE ||
	    resource_size(&resource) < SECURITY_AO_MIN_SIZE) {
		pr_err("sh53d_brom_entry: refusing unexpected security_ao resource %pa-%pa\n",
		       &resource.start, &resource.end);
		of_node_put(node);
		return -EINVAL;
	}

	base = of_iomap(node, 0);
	of_node_put(node);
	if (!base)
		return -ENOMEM;

	/* Exact transaction used by stock Preloader SetBromDownloadFlag(). */
	original_boot_misc0 = readl(base + BOOT_MISC0_OFFSET);
	original_reset_retention = readl(base + RST_CON_OFFSET);
	writel(MISC_LOCK_KEY_MAGIC, base + MISC_LOCK_KEY_OFFSET);
	readl(base + MISC_LOCK_KEY_OFFSET);
	reset_retention = original_reset_retention | BIT(0);
	writel(reset_retention, base + RST_CON_OFFSET);
	readl(base + RST_CON_OFFSET);
	writel(0, base + MISC_LOCK_KEY_OFFSET);
	readl(base + MISC_LOCK_KEY_OFFSET);
	writel(usbdl_value, base + BOOT_MISC0_OFFSET);
	readback = readl(base + BOOT_MISC0_OFFSET);

	if (readback != usbdl_value) {
		pr_emerg("sh53d_brom_entry: BOOT_MISC0 readback mismatch wrote=0x%08x read=0x%08x; not resetting\n",
			 usbdl_value, readback);
		writel(MISC_LOCK_KEY_MAGIC, base + MISC_LOCK_KEY_OFFSET);
		readl(base + MISC_LOCK_KEY_OFFSET);
		writel(original_reset_retention, base + RST_CON_OFFSET);
		readl(base + RST_CON_OFFSET);
		writel(0, base + MISC_LOCK_KEY_OFFSET);
		readl(base + MISC_LOCK_KEY_OFFSET);
		writel(original_boot_misc0, base + BOOT_MISC0_OFFSET);
		readl(base + BOOT_MISC0_OFFSET);
		iounmap(base);
		return -EIO;
	}
	pr_emerg("sh53d_brom_entry: retained BROM request verified; watchdog restart now\n");
	iounmap(base);
	mdelay(20);
	emergency_restart();
	return -EIO;
}

static void __exit sh53d_brom_entry_exit(void)
{
}

module_init(sh53d_brom_entry_init);
module_exit(sh53d_brom_entry_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guarded SH-53D retained BootROM download entry");
