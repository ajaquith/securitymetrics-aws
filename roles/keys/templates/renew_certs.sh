#!/usr/bin/sh
/usr/bin/acme-tiny --account-key {{ letsencrypt_account_dir }}/account.key --csr {{ certificate_data }}/{{ ec2_role }}/letsencrypt-csr.pem --acme-dir {{ acme_challenge_data }} > {{ certificate_data }}/{{ ec2_role }}/fullchain.pem.tmp || exit
mv {{ certificate_data }}/{{ ec2_role }}/fullchain.pem.tmp {{ certificate_data }}/{{ ec2_role }}/fullchain.pem
chown root:root {{ certificate_data }}/{{ ec2_role }}/fullchain.pem
service docker restart
