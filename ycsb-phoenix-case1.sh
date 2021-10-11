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
# Number of total rows to insert into hbase ( 150 millions row = 150GB)
RECORDS_TO_INSERT=150000000
# Total operations to perform for a specified workload
TOTAL_OPERATIONS_PER_WORKLOAD="RECORDS_TO_INSERT"
# Throttling (specifies number of operations to perform per sec by ycsb)
#OPERATIONS_PER_SEC=1000
# Number of threads to use in each workload
THREADS=15
# Maximum execution time on seconds ( 15 minutes )
MAX_TIME_EXE=900
# output Result file
RESULT_OUT=~/StressTest-YCSB_Result-Phoenix-Case1

WORKLOAD_LISTS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")

DRIVER="jdbc"

REPEATRUN=3

# Log file to use
LOG="${RESULT_OUT}/phoenix_ycsb.log"
#
# NOTE: DON'T CHANGE BEYOND THIS POINT SCRIPT MAY BREAK
#
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
#phoenix.properties

#db.driver=org.apache.phoenix.jdbc.PhoenixDriver
#db.url=jdbc:phoenix:mtrdlkprd01.corp.bankbtpn.co.id,mtrdlkprd03.corp.bankbtpn.co.id,mtrdlkprd05.corp.bankbtpn.co.id:2181:/hbase
#jdbc.autocommit=false
#db.batchsize=1000


#phoenix-thin.properties

#db.driver=org.apache.phoenix.queryserver.client.Driver
#db.url=jdbc:phoenix:thin:http://my_pqs_host:8765;serialization=PROTOBUF
#jdbc.autocommit=false
#db.batchsize=1000
#jdbc.batchupdateapi=true


#create table usertable(YCSB_KEY VARCHAR(255) NOT NULL PRIMARY KEY, FIELD0 VARCHAR, FIELD1 VARCHAR, FIELD2 VARCHAR, FIELD3 VARCHAR,FIELD4 VARCHAR, FIELD5 VARCHAR,FIELD6 VARCHAR, FIELD7 VARCHAR,FIELD8 VARCHAR, FIELD9 VARCHAR) SALT_BUCKETS=15;

#create index idx1 on usertable(field0, field1) include(field8, field9);

#create index idx2 on usertable(field2, field3) include(field8, field9);


cp ${PHOENIX_HOME}/phoenix-${PHOENIX_VERSION}-client.jar jdbc-binding/lib

cp ${PHOENIX_HOME}/phoenix-${PHOENIX_VERSION}-thin-client.jar jdbc-binding/lib


echo "Insert / Loading intial dataset ${RECORDS_TO_INSERT} row" >> $LOG
echo "Loading data for workloadg"
bin/ycsb load $DRIVER -P workloads/workloadg -p table=${HBASE_TABLE} -P phoenix.properties \
	-p recordcount=${RECORDS_TO_INSERT} \
    -p measurement.interval=both -p measurementtype=hdrhistogram -p hdrhistogram.fileoutput=true -p hdrhistogram.output.path=${RESULT_OUT}/workloadg \
    -threads ${THREADS} -s >> ${RESULT_OUT}/workloadg/workloadg.log


for workloads in "${WORKLOAD_LISTS[@]}"
do	
	mkdir -p ${RESULT_OUT}/$workloads
        echo "Running tests" $workloads
        for r in $(seq 1 $REPEATRUN)
        do
                bin/ycsb run $DRIVER -P workloads/$workloads -p table=${HBASE_TABLE} -P phoenix.properties \ 
                    -p operationcount=${!TOTAL_OPERATIONS_PER_WORKLOAD} \ 
                    -p measurement.interval=both -p measurementtype=hdrhistogram -p hdrhistogram.fileoutput=true -p hdrhistogram.output.path=${RESULT_OUT}/${workloads} \
                    -p maxexecutiontime=${MAX_TIME_EXE} \ 
                    -threads ${THREADS} -s >> ${RESULT_OUT}/$workloads/$workloads"_run_"$r".log"
        done
done

echo "Fin." >> $LOG