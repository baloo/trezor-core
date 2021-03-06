.PHONY: vendor

JOBS = 4
MAKE = make -j $(JOBS)
SCONS = scons -Q -j $(JOBS)

BOARDLOADER_BUILD_DIR = build/boardloader
BOOTLOADER_BUILD_DIR  = build/bootloader
FIRMWARE_BUILD_DIR    = build/firmware

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
UNIX_PORT_OPTS ?= TREZOR_X86=0
else
UNIX_PORT_OPTS ?= TREZOR_X86=1
endif
CROSS_PORT_OPTS ?= MICROPY_FORCE_32BIT=1

ifeq ($(DISPLAY_ILI9341V), 1)
CFLAGS += -DDISPLAY_ILI9341V=1
CFLAGS += -DDISPLAY_ST7789V=0
endif

ifeq ($(DISPLAY_VSYNC), 0)
CFLAGS += -DDISPLAY_VSYNC=0
endif

ifeq ($(STLINKv21), 1)
OPENOCD = openocd -f interface/stlink-v2-1.cfg -c "transport select hla_swd" -f target/stm32f4x.cfg
else
OPENOCD = openocd -f interface/stlink-v2.cfg -f target/stm32f4x.cfg
endif

## help commands:

help: ## show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m  make %-20s\033[0m %s\n", $$1, $$2} /^##(.*)/ {printf "\033[33m%s\n", substr($$0, 4)}' $(MAKEFILE_LIST)

## dependencies commands:

vendor: ## update git submodules
	git submodule update --init

res: ## update resources
	./tools/res_collect

## emulator commands:

run: ## run unix port
	cd src ; ../build/unix/micropython

emu: ## run emulator
	./emu.sh

## test commands:

test: ## run unit tests
	cd tests ; ./run_tests.sh

testpy: ## run selected unit tests from python-trezor
	cd tests ; ./run_tests_device.sh

pylint: ## run pylint on application sources
	pylint -E $(shell find src -name *.py)

style: ## run code style check on application sources
	flake8 $(shell find src -name *.py)

## build commands:

build: build_boardloader build_bootloader build_firmware build_unix build_cross ## build all

build_boardloader: ## build boardloader
	$(SCONS) CFLAGS="$(CFLAGS)" build/boardloader/boardloader.bin

build_bootloader: ## build bootloader
	$(SCONS) CFLAGS="$(CFLAGS)" build/bootloader/bootloader.bin

build_firmware: res build_cross ## build firmware with frozen modules
	$(SCONS) CFLAGS="$(CFLAGS)" build/firmware/firmware.bin
	$(SCONS) CFLAGS="$(CFLAGS)" build/firmware/firmware0.bin

build_unix: ## build unix port
	$(SCONS) build/unix/micropython $(UNIX_PORT_OPTS)

build_unix_noui: ## build unix port without UI support
	$(SCONS) build/unix/micropython $(UNIX_PORT_OPTS) TREZOR_NOUI=1

build_cross: ## build mpy-cross port
	$(MAKE) -C vendor/micropython/mpy-cross $(CROSS_PORT_OPTS)

## clean commands:

clean: clean_boardloader clean_bootloader clean_firmware clean_unix clean_cross ## clean all

clean_boardloader: ## clean boardloader build
	rm -rf build/boardloader

clean_bootloader: ## clean bootloader build
	rm -rf build/bootloader

clean_firmware: ## clean firmware build
	rm -rf build/firmware

clean_unix: ## clean unix build
	rm -rf build/unix

clean_cross: ## clean mpy-cross build
	$(MAKE) -C vendor/micropython/mpy-cross clean $(CROSS_PORT_OPTS)

## flash commands:

flash: flash_boardloader flash_bootloader flash_firmware ## flash everything using OpenOCD

flash_boardloader: $(BOARDLOADER_BUILD_DIR)/boardloader.bin ## flash boardloader using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< 0x08000000; exit"

flash_bootloader: $(BOOTLOADER_BUILD_DIR)/bootloader.bin ## flash bootloader using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< 0x08010000; exit"

flash_firmware: $(FIRMWARE_BUILD_DIR)/firmware.bin ## flash firmware using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< 0x08020000; exit"

flash_firmware0: $(FIRMWARE_BUILD_DIR)/firmware0.bin ## flash firmware0 using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< 0x08000000; exit"

flash_combine: $(FIRMWARE_BUILD_DIR)/combined.bin ## flash combined using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< 0x08000000; exit"

flash_erase: ## erase all sectors in flash bank 0
	$(OPENOCD) -c "init; reset halt; flash info 0; flash erase_sector 0 0 last; flash erase_check 0; exit"

## openocd debug commands:

openocd: ## start openocd which connects to the device
	$(OPENOCD)

gdb: ## start remote gdb session which connects to the openocd
	arm-none-eabi-gdb $(FIRMWARE_BUILD_DIR)/firmware.elf -ex 'target remote localhost:3333'

## misc commands:

vendorheader: ## construct default vendor header
	./tools/build_vendorheader 'e28a8970753332bd72fef413e6b0b2ef1b4aadda7aa2c141f233712a6876b351:d4eec1869fb1b8a4e817516ad5a931557cb56805c3eb16e8f3a803d647df7869:772c8a442b7db06e166cfbc1ccbcbcde6f3eba76a4e98ef3ffc519502237d6ef' 1 0.0 SatoshiLabs assets/satoshilabs_120.toif embed/firmware/vendorheader.bin
	./tools/binctl embed/firmware/vendorheader.bin -s 1 4444444444444444444444444444444444444444444444444444444444444444

binctl: ## print info about binary files
	./tools/binctl $(BOOTLOADER_BUILD_DIR)/bootloader.bin
	./tools/binctl embed/firmware/vendorheader.bin
	./tools/binctl $(FIRMWARE_BUILD_DIR)/firmware.bin

bloaty: ## run bloaty size profiler
	bloaty -d symbols -n 0 -s file $(FIRMWARE_BUILD_DIR)/firmware.elf | less
	bloaty -d compileunits -n 0 -s file $(FIRMWARE_BUILD_DIR)/firmware.elf | less

sizecheck: ## check sizes of binary files
	test 32768 -ge $(shell stat -c%s $(BOARDLOADER_BUILD_DIR)/boardloader.bin)
	test 65536 -ge $(shell stat -c%s $(BOOTLOADER_BUILD_DIR)/bootloader.bin)
	test 917504 -ge $(shell stat -c%s $(FIRMWARE_BUILD_DIR)/firmware.bin)
	test 1048576 -ge $(shell stat -c%s $(FIRMWARE_BUILD_DIR)/firmware0.bin)

combine: ## combine boardloader + bootloader + firmware into one combined image
	./tools/combine_firmware \
		0x08000000 $(BOARDLOADER_BUILD_DIR)/boardloader.bin \
		0x08010000 $(BOOTLOADER_BUILD_DIR)/bootloader.bin \
		0x08020000 $(FIRMWARE_BUILD_DIR)/firmware.bin \
		> $(FIRMWARE_BUILD_DIR)/combined.bin \
