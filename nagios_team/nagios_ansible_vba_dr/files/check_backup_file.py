#Help
#pip install paramiko
#python testNAS.py 10.22.99.37 nagios vnpay@123 "/SFTP/nagios_backup"

import paramiko
import sys
import os
from datetime import datetime, date

sftpServer  = '10.22.99.60'
sftpUser = 'nagios'
sftpPass = 'vnpay@123'
#sftpDir = 'SFTP/nagios_backup'
sftpDir = '/DatabaseTest/Backup/Oracle/10.22.7.24'
DIR ='/backup/rman/data'

if len(sys.argv) > 1:
        sftpServer = sys.argv[1]
if len(sys.argv) > 2:
        sftpUser = sys.argv[2]
if len(sys.argv) > 3:
        sftpPass = sys.argv[3]
if len(sys.argv) > 4:
        sftpDir = sys.argv[4]
		
ssh = paramiko.SSHClient()

# automatically add keys without requiring human intervention
ssh.set_missing_host_key_policy( paramiko.AutoAddPolicy() )
ssh.connect(sftpServer, username=sftpUser, password=sftpPass)
sftp = ssh.open_sftp()
files = 0
for i in sftp.listdir_attr(sftpDir):
		#if i.st_mode & 100000 : print i, 'is a file'
		#print i.filename, i.st_mode, datetime.fromtimestamp(i.st_mtime)
		if (datetime.fromtimestamp(i.st_mtime).date() == datetime.today().date()) and (i.st_mode & 100000):
				#print i
				files += 1
sftp.close()
ssh.close()

files_os = 0
for i in os.listdir(DIR): 
    a = os.stat(os.path.join(DIR,i))
    if (datetime.fromtimestamp(a.st_mtime).date() == datetime.today().date()) and os.path.isfile(os.path.join(DIR, i)):
	    files_os += 1

if (files == 0):
        if datetime.today().time().hour > 8:
                print ('Ngay', datetime.today().date(), 'khong co file nao duoc backup|backup_files=',files)
                sys.exit(2)
        else:
                print ('Ngay', datetime.today().date(), 'chua co file nao duoc backup|backup_files=',files)
                sys.exit(3)
else:
    if (files == files_os):
        print ('Ngay', datetime.today().date(), 'co',files,'file duoc backup va dong bo|backup_files=',files, 'backup_files_os=',files_os)
        sys.exit(0)
    else:
        print ('Files khong dong bo. (file tren server:',files_os, 'File tren NAS:',files,')')