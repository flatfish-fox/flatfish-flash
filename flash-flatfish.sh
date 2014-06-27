#!/bin/bash
# 
# Description: Script to flash FxOS images for Flatfish
# Features:
#   - Flash images from witin the flatfish B2G source directory
#   - Flash images from any given directory
#   - Allow the user to provide the path to the B2G source, in order to use the 'adb' in there.
#   - Multiple checkings, including image file existence, adb status and running mode, device status, etc.
#   - Convert Flatfish into fastboot mode, flash, and reboot it.
#   - Allow the device to be running under the 'adb' or 'fastboot' mode.
# 
# Author: William Liang
#
# Date: $Date: 2014/06/21 05:19:40 $
# Version: $Revision: 1.5 $
#
# History:
#
# $Log: flash-flatfish,v $
# Revision 1.5  2014/06/21 05:19:40  wyliang
# Fix: 1. The bug of wrong B2G source path detection. 2. Solve the case when the udev rule is not well set which makes the fastboot fail to run.
#
# Revision 1.4  2014/06/19 05:40:49  wyliang
# Allow the device to already exist in fastboot mode; fix some bugs; add some new checkings
#
# Revision 1.3  2014/06/18 09:14:26  wyliang
# Support flashing images in any directory
#
# Revision 1.2  2014/03/16 14:14:53  wyliang
# Support extract version
#
# Revision 1.1  2013/11/20 09:04:14  wyliang
# First time to create the flash-flatfish script
#
#

OUT=out/target/product/flatfish
BOOT=boot.img 
SYSTEM=system.img 
DATA=userdata.img 
B2G_DIR=""
FBT_SUDO=""
IN_B2G=1

usage() {
  PROG=`basename $0`
  echo -e "\n=== Usage ==="
  echo "Usage: $PROG [-h] [<path_to_images> [<path_to_b2g_root>]]"
  echo "Options:"
  echo "  -h: help"
  echo "  <path_to_images>: default to ./$OUT/"
  echo "  <path_to_b2g_root>: path to the root of the B2G source, for using 'adb' only. "\
                             "If 'adb' can be found in \$PATH, this option can be ignored."
  echo "Example:"
  echo "  1. Run in B2G root directory." 
  echo "    $ $PROG"
  echo "  2. flash images in the current directory"
  echo "    $ $PROG ."
  echo "  3. flash images in ~/flatfish-images"
  echo "    $ $PROG ~/flatfish-images"
  echo "  3. flash images in ~/flatfish-images, and specify the source path of B2G for using 'adb'"
  echo "    $ $PROG ~/flatfish-images ~/dev_fxos/a31-b2g"
  exit 1
}

run() {
  printf "\n[[ Execute: $* ]]\n"
  if ! $*; then
    echo "Problem occured. Process abort!"
    usage
  fi
}

# Apply B2G environment
apply_b2g_env() {
  [ ! -r "$B2G_DIR/build/envsetup.sh" ] && return

  printf "B2G_DIR found, setup the flatfish build environment to enable 'adb' and 'fastboot' ... "
  (
    pushd $B2G_DIR
    run source $B2G_DIR/build/envsetup.sh
    lunch 5
    popd 
  ) > /dev/null
  echo "Done.."
}
  
# File checking 
check_images() {
  printf "\n--- Image files checking ---\n"
  if [ "$IN_B2G" = 0 ]; then
    [ ! -d "$OUT" ] && echo "Error: the specified directory '$OUT' is not a directory!" && usage
  else
    echo "No specified image directory. We are supposed to be in the root directory of B2G. Verify the path now."
    if [ -d device/allwinners/flatfish ]; then # Internal source
      [ ! -f "$OUT/$BOOT" ] && echo "Error: '$OUT/$BOOT' does not exist." && usage
    elif [ ! -d device/allwinner/flatfish ]; then # open source
      echo "Error: You need to go to the root directory of the B2G flatfish source, or specify the directory in which images exist."
      usage
    fi
    echo "Yes, we are now in the root directory of B2G."
  fi
  
  DOFLASH=0
  [ ! -f "$OUT/$BOOT" ] && echo "Warning: '$OUT/$BOOT' does not exist." && DOIT=1
  [ ! -f "$OUT/$SYSTEM" ] && echo "Warning: '$OUT/$SYSTEM' does not exist!" 
  [ ! -f "$OUT/$DATA" ] && echo "Warning: '$OUT/$DATA' does not exist!" 
  
  echo "Good, image files are in position now."
}

# Enable adb 
adb_to_fastboot() {
  printf "\n--- Check to see if the adb works properly (for Android 4.2 and above) ---\n"
  
  if ! which adb > /dev/null 2>&1; then
    echo "'adb' is not found. Please add the path of adb in the PATH environment variable."
    return 1
  fi
  
  if adb devices | grep 'no permissions' > /dev/null 2>&1; then
    echo "Warning: It seems that the 'adb' command was not run correctly (in superuser mode)."
    echo "--> Re-activate adb by 'sudo adb devices'. (Note: your password is required.)"
    run adb kill-server
    run sudo `which adb` devices
  fi
  
  echo "'adb' works fine."
  
  # Check the readiness of the device
  printf "\n--- Check to see if the flatfish device is ready ---\n"
  
  if adb devices 2> /dev/null | grep FLATFISH > /dev/null 2>&1; then
    echo "Good, it looks to be Okay."
  else
    echo "Oh, the flatfish device is not there, or is not turned on in a mode where 'adb' can be used."
    return 1
  fi
  
  # Enable fastboot
  printf "\n--- Change into the fastboot mode ---\n"
  if ! run adb shell reboot boot-fastboot && ! run adb shell su -c reboot boot-fastboot; then
    echo "'adb' failed to reboot to fastboot mode."
  fi

  # wait for the fastboot to take effect
  printf "Wait for 10 seconds for the device to get ready in the fastboot mode ...  "
  i=9; while [ $i -gt 0 ]; do printf "\b$i"; i=$(($i-1)); sleep 1; done
  printf "\bDone.\n"
}

# Try to use fastboot directly
check_fastboot() {
  printf "\n--- Let's see if it's already in the fastboot mode ---\n"
  
  FBT_CHK=`fastboot devices`
  if echo "$FBT_CHK" | grep fastboot > /dev/null 2>&1; then
    echo "Fastboot mode detected."
    if echo "$FBT_CHK" | grep 'no permissions' > /dev/null 2>&1; then
      echo "However, the udev rule for the device may not be well configured. Will request the user to run in sudo mode"
      FBT_SUDO="sudo"
    fi
  else
    echo "Error: Fastboot mode is not detected. Check to see if the device is not turned on."
    echo "*Note: If it is powered but both 'adb' and 'fastboot' could not work, "
    echo "       please check to see if the device has become brick. (Bug 1026963)"
    usage
  fi
}

echo "Start the flash-flatfish.sh procedure." 

# Check for help option
[ "$1" = "-h" ] && usage

if [ -z "$1" ]; then
  IN_B2G=1
  B2G_DIR="."
  apply_b2g_env
else
  IN_B2G=0
  OUT="$1"
  if [ -n "$2" ]; then
    B2G_DIR="$2"
    apply_b2g_env
  fi 
fi

# Check images, adb, and fastboot mode
check_images
adb_to_fastboot 
check_fastboot

# Start the flashing process
printf "\n--- Start to flash boot, system, and data partitions ---\n"

FASTBOOT=`which fastboot`
[ ! -x "$FASTBOOT" ] && echo "Error: Fastboot not found! Abort." && usage

[ -f "$OUT/$BOOT" ] && run $FBT_SUDO $FASTBOOT flash boot $OUT/boot.img 
run $FBT_SUDO $FASTBOOT flash system $OUT/system.img 
run $FBT_SUDO $FASTBOOT flash data $OUT/userdata.img 

# Reboot the system
printf "\n--- Reboot the device ---\n"

run $FBT_SUDO $FASTBOOT reboot
