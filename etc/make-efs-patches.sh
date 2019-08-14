#!/bin/bash
#
# Execute from the project root directory.
#
cd etc/local/efs-utils
git diff src/watchdog/__init__.py > ../../../roles/amazon/files/amazon-efs-mount-watchdog.patch
git diff src/mount_efs/__init__.py > ../../../roles/amazon/files/mount.efs.patch
cd ../../../
