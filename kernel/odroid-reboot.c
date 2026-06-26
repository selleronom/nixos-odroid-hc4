/*
 * odroid-reboot.c — SD card power-cycle on reboot for ODROID HC4
 *
 * Based on Armbian's odroid-reboot driver. Simplified for out-of-tree use:
 * hardcodes the HC4 aobus GPIO offsets instead of requiring a DT node.
 *
 * On Amlogic S905X3 (Meson SM1) the BL2 firmware hangs during SD card
 * initialisation after a warm reboot because the card retains state from
 * Linux. This module registers a restart handler (priority 192, above PSCI
 * at 128) that power-cycles the SD card via three aobus GPIO pins just
 * before the PSCI SYSTEM_RESET call.
 *
 * GPIO pins (aobus / gpiochip1):
 *   GPIOAO_3  (offset 3)  = tflash_vdd — 3.3V card power (open-drain)
 *   GPIOAO_6  (offset 6)  = tf_io voltage select (open-source)
 *   GPIOE_2   (offset 14) = tf_io enable (open-drain)
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#include <linux/delay.h>
#include <linux/gpio/driver.h>
#include <linux/gpio.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/reboot.h>

/* Aobus GPIO line offsets on the HC4 */
#define VMMC_OFFSET  3   /* GPIOAO_3 — tflash_vdd */
#define VQSW_OFFSET  6   /* GPIOAO_6 — tf_io voltage select */
#define VQEN_OFFSET  14  /* GPIOE_2  — tf_io enable */

static int gpio_vmmc;
static int gpio_vqsw;
static int gpio_vqen;

/*
 * Find the aobus GPIO chip.  On Meson SM1 it is the only chip with
 * exactly 15 lines (GPIOAO_0-11 + GPIOE_0-2).
 */
static int match_aobus(struct gpio_chip *gc, const void *data)
{
	return gc->ngpio == 15;
}

static void odroid_card_reset(void)
{
	int ret;

	if (!gpio_vmmc)
		return;

	/* Free lines from regulator / pinctrl drivers */
	gpio_free(gpio_vqsw);
	gpio_free(gpio_vqen);
	gpio_free(gpio_vmmc);

	/* Request all three as output LOW — cuts SD card power */
	ret = gpio_request_one(gpio_vqsw, GPIOF_OUT_INIT_LOW, "REBOOT");
	if (ret)
		pr_err("odroid-reboot: vqsw request: %d\n", ret);
	ret = gpio_request_one(gpio_vqen, GPIOF_OUT_INIT_LOW, "REBOOT");
	if (ret)
		pr_err("odroid-reboot: vqen request: %d\n", ret);
	ret = gpio_request_one(gpio_vmmc, GPIOF_OUT_INIT_LOW, "REBOOT");
	if (ret)
		pr_err("odroid-reboot: vmmc request: %d\n", ret);

	/* Wait for capacitors to discharge */
	mdelay(100);

	/* Release to input — pull-ups restore default power-on state */
	gpio_direction_input(gpio_vqen);
	gpio_direction_input(gpio_vmmc);
	gpio_direction_input(gpio_vqsw);
	mdelay(5);

	gpio_free(gpio_vqen);
	gpio_free(gpio_vmmc);
	gpio_free(gpio_vqsw);
}

static int odroid_reset_handler(struct notifier_block *this,
				unsigned long mode, void *cmd)
{
	odroid_card_reset();
	return NOTIFY_DONE;
}

static struct notifier_block odroid_reset_nb = {
	.notifier_call = odroid_reset_handler,
	.priority = 192,
};

static int __init odroid_reboot_init(void)
{
	struct gpio_device *gdev;
	struct gpio_chip *ao_chip;

	/* Only run on Hardkernel ODROID-HC4 */
	if (!of_machine_is_compatible("hardkernel,odroid-hc4"))
		return -ENODEV;

	gdev = gpio_device_find(NULL, match_aobus);
	if (!gdev) {
		pr_err("odroid-reboot: aobus GPIO chip not found\n");
		return -ENODEV;
	}

	ao_chip = gpio_device_get_chip(gdev);
	gpio_vmmc = ao_chip->base + VMMC_OFFSET;
	gpio_vqsw = ao_chip->base + VQSW_OFFSET;
	gpio_vqen = ao_chip->base + VQEN_OFFSET;

	pr_info("odroid-reboot: vmmc=%d vqsw=%d vqen=%d (base=%d)\n",
		gpio_vmmc, gpio_vqsw, gpio_vqen, ao_chip->base);

	gpio_device_put(gdev);
	return register_restart_handler(&odroid_reset_nb);
}

static void __exit odroid_reboot_exit(void)
{
	unregister_restart_handler(&odroid_reset_nb);
}

module_init(odroid_reboot_init);
module_exit(odroid_reboot_exit);

MODULE_DESCRIPTION("ODROID HC4 SD card power-cycle on reboot");
MODULE_LICENSE("GPL v2");
