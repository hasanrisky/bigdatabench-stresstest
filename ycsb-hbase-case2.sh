#!/usr/bin/env bash
#
# Running mixed workload on HBase using YCSB
# Author: Hasan (hasanrisky at gmail dot com)
# Date: 2021-10-05
#
# Note: run from ycsb-0.17.0 directory 
#
# prereq:    hbase-site.xml (usually in /etc/hbase/conf directory) is copied to ycsb-0.17.0/hbase20-binding/conf directory
# kinit as hbase
# hbase(main):001:0> n_splits = 200 # HBase recommends (10 * number of regionservers)
# hbase(main):002:0> create 'usertable', 'family', {SPLITS => (1..n_splits).map {|i| "user#{1000+i*(9999-1000)/n_splits}"}}
# or
# create 'usertable', 'family', {SPLITS => (1..200).map {|i| "user#{1000+i*(9999-1000)/200}"}, MAX_FILESIZE => 4*1024**3}
#
# btpn prod with 15 regionservers 
#
#create 'usertable', 'family', {SPLITS => (1..150).map {|i| "user#{1000+i*(9999-1000)/150}"}} 
#
# Threads :
# lscpu | egrep 'Model name|Socket|Thread|NUMA|CPU\(s\)'
# Total threads = ( CPU core * Thread per core )
# You may want to tweak these variables to change the workload's behavior
# env prod
# cpu core 32
# thread 2
# ulimit nproc 10000 & nofile 10000
# master1-5 ram 125GB
# master6-worker1..15 377GB
#
YCSB_HOME=ycsb-0.17.0
# Default data size: 1 KB records (10 fields, 100 bytes each, plus key)
#
# Number of total rows to insert into hbase ( 5 billions row = 5TB)
RECORDS_TO_INSERT=5000000000
# Total operations to perform for a specified workload
TOTAL_OPERATIONS_PER_WORKLOAD="RECORDS_TO_INSERT"
# Throttling (specifies number of operations to perform per sec by ycsb)
#OPERATIONS_PER_SEC=1000
# Number of threads to use in each workload
THREADS=15
# Name of hbase table
HBASE_TABLE="usertable"
# Name of the hbase column family
HBASE_CFM="family"
# Number of hbase regions to create initially while creating the table in hbase
#HBASE_RC=16
# Maximum execution time on seconds ( 15 minutes )
MAX_TIME_EXE=900
# output Result file
RESULT_OUT=~/StressTest-YCSB_Result-Hbase-Case1

WORKLOAD_LISTS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")

DRIVER="hbase20"

REPEATRUN=3

# Log file to use
LOG="${RESULT_OUT}/hbase_ycsb.log"
#
# NOTE: DON'T CHANGE BEYOND THIS POINT SCRIPT MAY BREAK
#
export HBASE_CONF_DIR=/etc/hbase/conf
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export PATH=$PATH:$(dirname $(readlink -f $(which java)))

echo "nofile: The maximum number of open files. Recommended value: 32768"
echo "current is $(ulimit -n)"
echo "set to $(ulimit -n 32768)" 
echo "nproc: The maximum number of processes. Recommended value: 65536"
echo "current is $(ulimit -u)"
echo "set to $(ulimit -u 65536)" 

echo -e "Set ulimit recommendationon secure Region Server (workers) \n"
for i in wrkdlkprd{01..15}; do
	ssh ${i} 'hostname; ulimit -n 32768; ulimit -u 65536'
done

cd "${YCSB_HOME}"
# checking classpath hbase conf
[[ -d "hbase20-binding/conf" ]] || mkdir -p hbase20-binding/conf && cp /etc/hbase/conf/hbase-site.xml hbase20-binding/conf/
  
# checking result directory
[[ -d "${RESULT_OUT}" ]] || mkdir -p "${RESULT_OUT}/workloadg"

# Create a table with specfied regions and with one column family
#echo "Creating pre-splitted table"
#hbase org.apache.hadoop.hbase.util.RegionSplitter ${HBASE_TABLE} HexStringSplit \
#  -c ${HBASE_RC} -f ${HBASE_CFM} >> $LOG
# HBase recommends (10 * number of regionservers)

tsplit='{SPLITS => (1..150).map {|i| "user#{1000+i*(9999-1000)/150}"}}'

echo "create 'usertable', 'family', ${tsplit} " | hbase shell >> $LOG


echo "Insert / Loading intial dataset ${RECORDS_TO_INSERT} row" >> $LOG
echo "Loading data for workloadg"
bin/ycsb load $DRIVER -cp hbase20-binding/conf -P workloads/workloadg -p table=${HBASE_TABLE} -p columnfamily=${HBASE_CFM} \
	-p recordcount=${RECORDS_TO_INSERT} \
	-p measurement.interval=both -p measurementtype=hdrhistogram+histogram -p hdrhistogram.fileoutput=true -p hdrhistogram.output.path=${RESULT_OUT}/workloadg/ \
    -threads ${THREADS} -s >> ${RESULT_OUT}/workloadg/workloadg.log


for workloads in "${WORKLOAD_LISTS[@]}"
do	
	mkdir -p ${RESULT_OUT}/$workloads
        echo "Running tests" $workloads

        for r in $(seq 1 $REPEATRUN)
        do
		mkdir -p ${RESULT_OUT}/$workloads/$workloads"_hdrhistogram_"$r

            bin/ycsb run $DRIVER -cp hbase20-binding/conf -P workloads/$workloads -p table=${HBASE_TABLE} -p columnfamily=${HBASE_CFM} \
			    -p operationcount=${!TOTAL_OPERATIONS_PER_WORKLOAD} \
			    -p measurement.interval=both -p measurementtype=hdrhistogram+histogram -p hdrhistogram.fileoutput=true -p hdrhistogram.output.path=${RESULT_OUT}/$workloads/$workloads"_hdrhistogram_"$r/ \
			    -p maxexecutiontime=${MAX_TIME_EXE} \
			    -threads ${THREADS} -s >> ${RESULT_OUT}/$workloads/$workloads"_run_"$r".log"
        done
done

#Truncate , Disable, Drop table and start over
#hbase shell ./hbase_truncate

# Count rows in a table
echo "count 'usertable'" | hbase shell >> $LOG

# Delete the table contents
echo "truncate 'usertable'" | hbase shell >> $LOG

# Disable and Drop table existing
echo "Disabling and dropping table" >> $LOG
echo "disable 'usertable'" | hbase shell >> $LOG
echo "drop 'usertable'" | hbase shell >> $LOG

echo "Fin." >> $LOG