#!/bin/bash

x=''
while [ t ];
do
	$(`$x < RAFTNODESENDMSGRESPPIPE`);
  echo "$($x)" > RAFTNODERECEIVEMSGPIPE;
done
