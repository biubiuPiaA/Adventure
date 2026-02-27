# keytabextract krb5.keytab → the output result will display and saved in keytabextract.txt at the current directory                                                           
#!/bin/bash

python3 /home/kali/all/tools/win/keytabextract.py "$@" | tee keytabextract.txt
