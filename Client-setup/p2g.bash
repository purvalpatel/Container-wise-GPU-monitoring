#!/bin/bash -e

Help() {

        echo -e "Usage: <p2g.bash> [options] <No options required>"
        echo -e ""
        echo -e "Ouput description:"
        echo -e "PID: PID that uses the GPU"
        echo -e "CONTAINER_NAME: Container name that uses the GPU"
        echo -e "GPU util: {GPU id} {PID} {SM utilization} {GPU Memory utilization}"
        echo -e "GPU usage: GPU usage of the memory"

}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  Help
  exit 0
fi

my_pids=$(nvidia-smi | sed '1,/Processes:/d' | awk '{print $5}' | grep -v 'PID' | grep -v '|' | awk '!NF || !seen[$0]++')
docker ps --format "{{.Names}}" | awk '{print "echo name "$1"; docker top "$1}' | sh >>/tmp/.full_cpid_detail.txt

for pid in $my_pids; do
	p2g_util=$(nvidia-smi pmon -c 1 | grep "$pid" | awk '{print $1, $2, $4, $5}' | head -1)
	if [ ! -n "$p2g_util" ]; then
		p2g_util="0 0 0 0"
	fi
	#echo -e $p2g_util
    	p2g_usage=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv | grep "$pid" | awk '{print $3, $4}' | awk '{sum += $1} END {print sum ""}')
	if [ ! -n "$p2g_usage" ]; then
		p2g_usage=$(python3 /home/script/docker_container_gpu_exporter/get_memory_MIG.py "$pid")
		if [ ! -n "$p2g_usage" ]; then
			p2g_usage="0 MiB"
		fi
	fi

	p2c=$(cat /tmp/.full_cpid_detail.txt | awk -v PID="$pid" 'BEGIN{split(PID,pids," ")}{if (NF==2 && $1=="name") name=$2; for(pid in pids){pid=pids[pid];if (NF>2 && $2==pid) print "CONTAINER_NAME: "name"\n"}}')
#	p2c=$(docker ps --format "{{.Names}}" | awk '{print "echo name "$1"; docker top "$1}' | sh | awk -v PID="$pid" 'BEGIN{split(PID,pids," ")}{if (NF==2 && $1=="name") name=$2; for(pid in pids){pid=pids[pid];if (NF>2 && $2==pid) print "CONTAINER_NAME: "name"\n"}}')
	if [ ! -n "$p2c" ]; then
		p2c=$(ps -eo pid,user:32,comm | grep -i $pid | awk '{print$2} END {print sum ""}')
		p2c="CONTAINER_NAME: $p2c"
		if [ ! -n $p2c ]; then
			p2c="NA"
		fi
	fi
	echo "$p2c,$p2g_util,$p2g_usage,$pid" >>/tmp/.cinfo.txt 

done

## Create loop on list, which have same container name the sum of memory utilization will be in total

awk -F',' '
{
    # extract container name (remove "CONTAINER_NAME: ")
    split($1, a, ": ")
    cname = a[2]

    # extract memory (remove MiB)
    gsub(/MiB/, "", $3)
    mem = $3 + 0

    # accumulate memory per container
    total[cname] += mem
    util[cname]  = $2

    # store first PID only
    if (!(cname in pid)) {
        pid[cname] = $4
    }
}
END {
    for (c in total) {
        print "CONTAINER_NAME: " c "," util[c] "," total[c] " MiB," pid[c]
    }
}' /tmp/.cinfo.txt > /tmp/.container_info.txt
## Create loop on list, which have same container name the sum of memory utilization will be in total


i=1
n=`wc -l < /tmp/.container_info.txt`
while [ $i -le $n ]
do
	p2c=$(awk "NR==$i" /tmp/.container_info.txt | cut -d ',' -f1)
	p2g_util=$(awk "NR==$i" /tmp/.container_info.txt | cut -d ',' -f2)
	p2g_usage=$(awk "NR==$i" /tmp/.container_info.txt | cut -d ',' -f3)
	pid=$(awk "NR==$i" /tmp/.container_info.txt | cut -d ',' -f4)
	if [ ! -z "$p2c" ]
	then
		echo -e PID: $pid
		echo -e $p2c
		echo -e GPU util: $p2g_util
		echo -e GPU usage: $p2g_usage 
		echo -e "\n"
	else
                echo -e PID: $pid
		p2c=$(ps -ef | grep -i $pid | grep -v grep | awk '{print$1}')
                echo -e "CONTAINER_NAME: '$p2c'_systemuser"
                echo -e "GPU util: 0 0 - -"
                echo -e "GPU usage: 0 MiB"
                echo -e "\n"
	fi
i=$((i+1))
done

rm /tmp/.container_info.txt
rm /tmp/.cinfo.txt
rm /tmp/.full_cpid_detail.txt
