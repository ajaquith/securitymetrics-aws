#!/usr/bin/python
import re

class FilterModule(object):
    ''' Accepts a PEM-formatted public key and creates a properly formatted
    DKIM record. Example:

        {{ '-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...' | dkim_record }}"
        
    See: http://knowledge.ondmarc.com/en/articles/2141592-generating-2048-bits-dkim-public-and-private-keys-using-openssl-on-a-mac
    See: https://mediatemple.net/community/products/dv/115003098072/how-do-i-add-a-dkim-txt-record-to-my-domain
    
    '''
    def filters(self):
        return {
            'dkim_record': self.dkim_record
        }
    
    def dkim_record(self, pubkey):
        key_type = "rsa"
        p = re.sub('-----BEGIN PUBLIC KEY-----|-----END PUBLIC KEY-----|\\s','', pubkey)
        dkim = 'v=DKIM1; k=%s; p=%s' % (key_type, p)
        dkim_out = ''
        chunks = ('"%s" ' % dkim[0+i:255+i] for i in range(0, len(dkim), 255))
        for chunk in chunks:
            dkim_out += chunk
        return dkim_out[:-1]
