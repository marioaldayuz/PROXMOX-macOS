#!/bin/bash
# boot-img-compare.sh

WORKING_ISO="ignore/ISOs-ignored/Old ISOs/LongQT-OpenCore-v0.5.iso"
YOUR_ISO="ignore/ISOs-ignored/OpenCore-C02TQFZUHX87.iso"  # UPDATE THIS

echo "=== BOOT.img Diagnostic Tool ==="
echo

# Extract BOOT.img from both ISOs
mkdir -p /tmp/bootimg_test
cd /tmp/bootimg_test

echo "1. Extracting working BOOT.img..."
7z x "$WORKING_ISO" BOOT.img -o./working/ 2>/dev/null || {
    hdiutil attach "$WORKING_ISO" -readonly -mountpoint ./working_mount
    cp ./working_mount/BOOT.img ./working/
    hdiutil detach ./working_mount
}

echo "2. Extracting your BOOT.img..."
7z x "$YOUR_ISO" BOOT.img -o./ours/ 2>/dev/null || {
    hdiutil attach "$YOUR_ISO" -readonly -mountpoint ./our_mount
    cp ./our_mount/BOOT.img ./ours/
    hdiutil detach ./our_mount
}

echo "3. Comparing file info..."
echo "Working:" && file working/BOOT.img
echo "Ours:" && file ours/BOOT.img

echo
echo "4. Size comparison:"
ls -lh working/BOOT.img ours/BOOT.img

echo
echo "5. Trying to mount working..."
hdiutil attach working/BOOT.img -readonly && echo "✓ Success" || echo "✗ Failed"

echo
echo "6. Trying to mount ours..."
hdiutil attach ours/BOOT.img -readonly && echo "✓ Success" || echo "✗ Failed"