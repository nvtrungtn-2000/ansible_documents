#!/bin/bash
cd /etc/yum.repos.d
for f in *.*; do mv $f `basename $f .repo`.bk; done;
