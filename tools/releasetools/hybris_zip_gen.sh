#!/bin/bash
# First, we make standard hybris-boot.img and create the dirs needed to create the hybris-boot.zip
# Since mka won't be included (it will say command not found), we can't automatically use the max number of cores
# But we let the user decide how many cores he want to use for parallel build.
mkdir -p /tmp/hybris-boot_zip/META-INF/com/google/android
read -p 'Enter the number of cores you want to use for parallel build (min 1): ' N
make -j$N hybris-boot

# Since fstab is copied during the build of system.img, we have to make it, too
make -j$N systemimage

# Since this is a bash script, we don't have variables like $(PRODUCT_OUT) and $(ANDROID_BUILD_TOP) defined in android makefiles,
# so, we have to create them in a different way
export HALIUM_BUILD_TOP=$(pwd)
FSTAB_PATH='/tmp/hybris-boot_zip/fstab'

# Make sure that pwd is the root of android tree, by checking if build/envsetup.sh (for example) if present
# if the user isn't in halium tree, hybris-boot wouldn't neither start building, but we check it anyway
# Also, make these and the next error's messages red
if [ ! -f $HALIUM_BUILD_TOP/build/envsetup.sh ]; then
    echo -e '\033[0;31mYou are not in the root of halium tree'
    echo -e "\033[0;31mPlease cd to halium tree's root and run the script again"
    exit 1
fi

# Now, ask user for the codename of his device, needed for out/target/product/CODENAME
# Then, create PRODUCT_OUT variable which is halium_tree_dir/out/target/product/codename
read -p 'Enter device codename: ' CODENAME
PRODUCT_OUT=$(echo $HALIUM_BUILD_TOP'/out/target/product/'$CODENAME)

# Make sure that the user entered the right codename by veryfing if out/target/product/CODENAME is present.
# Also, we can verify if it's the directory of a device which has built halium hybris-boot, by checking if hybris-boot.img
# is also present. This is not because we need to check if the build of hybris-boot failed, in fact, in that case it would stop at 'make -j$N hybris-boot',
# but because there could be other directories in out/target/product/ which aren't of the device they want to build a zip for
if [ ! -f $PRODUCT_OUT/hybris-boot.img ]; then
    echo -e '\033[0;31mYou entered a wrong codename'
    echo -e '\033[0;31mPlease check CODENAME variable in you tree'
    echo -e '\033[0;31mOtherwise the codename is also the out/target/product/your_device_name directory'
    exit 1
fi

# Check if fstab file is present in OUT_DIR/target/product/CODENAME/root/
# It should be copied during build, but it might be copied to a different place chosen by the user.
# Fstab is needed to get boot partition location, and we can't continue without it
if [ ! -f $PRODUCT_OUT/root/*fstab* ]; then
    echo -e '\033[0;31mWe cannot continue without the fstab'
    echo -e '\033[0;31mYou have to add it in '$PRODUCT_OUT'/root/'
    exit 1
fi

# Now we copy the fstab;
cp $PRODUCT_OUT/root/*fstab* $FSTAB_PATH

# Fstab V2: First replace any tab (if present) with 1 space, so that sed will work either if the fstab contains tabs instead of multiple spaces
# Then remove everything after ' /boot' and possibly remained spaces after partition's name.
# The result will be the boot partition's name
PARTITION=$(expand -t 1 $FSTAB_PATH |grep -oP '.*?(?= /boot)' | sed -n 's/ .*//p')

# Fstab V1: First replace any tab (if present) with 1 space, so that sed will work either if the fstab contains tabs instead of multiple spaces
# Then remove '/boot' and 'emmc', but displays the line which contains '/boot '.
# This prevents other partitions like recovery (emmc) to be included.
# Finally it removes spaces remained before the partition's name
PARTITION=$(expand -t 1 $FSTAB_PATH | sed -n 's/emmc//p' | sed -n 's-/boot --p' | sed -n 's/.* //p')$PARTITION

# Let's create the updater-script, and fix possible "defaults" if using the fstab V2 and duplicate lines
# caused by the sed if using V1
printf 'package_extract_file("boot.img", %s'\""$PARTITION"\"');\n' | sed 's/defaults//p'|uniq > /tmp/hybris-boot_zip/META-INF/com/google/android/updater-script
echo 'set_progress(1.000000);' >> /tmp/hybris-boot_zip/META-INF/com/google/android/updater-script

# Since the fstab was needed only to know the boot partition's name for the updater-script, we can remove it now
rm $FSTAB_PATH

# Now copy the update-binary and hybris-boot.img
cp $HALIUM_BUILD_TOP/build/tools/releasetools/boot_installer/update-binary /tmp/hybris-boot_zip/META-INF/com/google/android/update-binary
cp $PRODUCT_OUT/hybris-boot.img /tmp/hybris-boot_zip/boot.img

# Now that we have updater-script, update-binary and hybris-boot.img, it's time to create the zip.
# But let's check if zip command is present before proceeding
if ! hash zip 2>/dev/null; then
    echo -e '\033[0;31mzip command is needed to generate hybris-boot zip'
    echo -e '\033[0;31mMake sure to install zip before proceeding again'
    exit 1
fi

# Now we can make the zip. Since if we specify /tmp/hybris-boot_zip/* in zip command, it will create a zip with tmp/hybris-boot_zip directories,
# we have to temporary cd in /tmp/hybris-boot_zip so that those directories won't be included in the zip
(cd /tmp/hybris-boot_zip && zip -r $PRODUCT_OUT/hybris-boot.zip *)

# Cleanup /tmp and success message
rm -rf /tmp/hybris-boot_zip
echo -e '\033[0;34mBuild completed. Zip is located at '$PRODUCT_OUT'/hybris-boot.zip'
