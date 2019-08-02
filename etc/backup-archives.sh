#!/bin/bash
scp -i ~/.ssh/id_rsa root@www.securitymetrics.org:/var/lib/mailman/archives/private/discuss.mbox/discuss.mbox etc/
scp -i ~/.ssh/id_rsa root@www.securitymetrics.org:/var/lib/mailman/lists/discuss/config.pck etc/
