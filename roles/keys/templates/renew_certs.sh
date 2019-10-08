tls_data#!/usr/bin/sh
/usr/bin/acme-tiny --account-key {{ letsencrypt_account_dir }}/account.key --csr {{ tls_data }}/letsencrypt-csr.pem --acme-dir {{ acme_challenge }} > {{ tls_data }}/fullchain.pem.tmp || exit
mv {{ tls_data }}/fullchain.pem.tmp {{ tls_data }}/fullchain.pem
chown root:root {{ tls_data }}/fullchain.pem
service docker restart
