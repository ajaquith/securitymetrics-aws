#!/usr/bin/sh
/usr/bin/acme-tiny --account-key {{ letsencrypt_account_dir }}/account.key --csr {{ certificate_data }}/letsencrypt-csr.pem --acme-dir {{ acme_challenge_data }} > {{ certificate_data }}/fullchain.pem.tmp || exit
mv {{ certificate_data }}/fullchain.pem.tmp {{ certificate_data }}/fullchain.pem
chown {{certificate_user}}:{{certificate_user}} {{ certificate_data }}/fullchain.pem
service docker restart
