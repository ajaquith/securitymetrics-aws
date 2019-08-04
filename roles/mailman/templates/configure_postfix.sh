#!/bin/sh
#
# Based on the Mailman configuration guidelines from:
#    http://docs.mailman3.org/en/latest/config-core.html
#
# ...and security hardening guidelines from:
#    https://linux-audit.com/postfix-hardening-guide-for-security-and-privacy/
#    https://xdeb.org/post/2017/12/20/mail-relay-mx-backup-and-spam-filtering-with-postfix/
#    https://isc.sans.edu/forums/diary/Hardening+Postfix+Against+FTP+Relay+Attacks/22086/
#
postconf -e disable_vrfy_command=yes
postconf -e smtpd_relay_restrictions=permit_mynetworks,reject_unauth_destination
postconf -e relay_domains={{ server_domain }},regexp:/var/data/mailman/postfix_domains
postconf -e mydestination=localhost,localhost.{{ server_domain }},{{ server_name }},{{ server_domain }}
echo "Configuring Postfix for use with Mailman."
postconf -e recipient_delimiter=+
postconf -e unknown_local_recipient_reject_code=550
postconf -e owner_request_special=no
postconf -e local_recipient_maps=regexp:/var/data/mailman/postfix_lmtp
postconf -e transport_maps=regexp:/var/data/mailman/postfix_lmtp
echo "Tightening Postfix security."
postconf -e maximal_queue_lifetime=10d
#postconf -e postscreen_access_list=permit_mynetworks
#postconf -e postscreen_cache_map=proxy:btree:$data_directory/postscreen_cache
#postconf -e postscreen_greet_action=enforce
postconf -e smtp_starttls_timeout=60s
postconf -e smtp_tls_loglevel=1
postconf -e smtp_tls_note_starttls_offer=yes
postconf -e smtp_tls_security_level=may
postconf -e smtpd_forbidden_commands=CONNECT,GET,POST,USER,PASS
postconf -e smtpd_helo_required=yes
postconf -e smtpd_recipient_restrictions=reject_unauth_pipelining,reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_mynetworks,reject_unknown_reverse_client_hostname,reject_unlisted_recipient,permit
postconf -e smtpd_starttls_timeout=60s
postconf -e smtpd_timeout=60s
postconf -e smtpd_tls_cert_file=/etc/tls/fullchain.pem
postconf -e smtpd_tls_key_file=/etc/tls/privkey.pem
postconf -e smtpd_tls_loglevel=1
postconf -e smtpd_tls_security_level=may
echo "Completed Postfix config."
