#!/bin/bash
apk add e2fsprogs-extra
resize2fs {{ ec2_volume_device }}
