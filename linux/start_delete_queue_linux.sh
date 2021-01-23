#!/bin/bash
echo "Empty files"
for i in $(ls *.txt *.json|xargs)
do
  if [ -f $i ]
  then
    >$i
  fi
done

echo "Getting queue url and name"
/usr/local/bin/aws sqs list-queues --max-results 1000  > queue_list.json
jq -r '.QueueUrls[]' queue_list.json > queue_url.txt
while [ $(cat queue_list.json|grep NextToken|wc -l) -gt 0 ]
do
  jq -r '.NextToken' queue_list.json > token.txt
  /usr/local/bin/aws sqs list-queues --next-token $(cat token.txt) --max-results 1000  > queue_list.json
  jq -r '.QueueUrls[]' queue_list.json >> queue_url.txt
done
sed 's|https://sqs.us-west-2.amazonaws.com/652029311869/||g' queue_url.txt |sed 's|.*-DL||g'|sed '/^$/d' > queue_name.txt

echo "Start filtering queue not received message"
for i in $(cat queue_name.txt|xargs)
do
  if [ -z $(/usr/local/bin/aws cloudwatch get-metric-statistics --metric-name NumberOfMessagesReceived --start-time $(date --date="-7 day" '+%FT00:00:00Z') --end-time $(date '+%FT%H:%M:%SZ') --period 86400 --namespace AWS/SQS --statistics Maximum --dimensions="Name=QueueName,Value=$i" |jq '.Datapoints[].Maximum'|awk '{sum += $1} END {print sum}') ]
  then
    sum_week=0
  else
    sum_week=$(/usr/local/bin/aws cloudwatch get-metric-statistics --metric-name NumberOfMessagesReceived --start-time $(date --date="-7 day" '+%FT00:00:00Z') --end-time $(date '+%FT%H:%M:%SZ') --period 86400 --namespace AWS/SQS --statistics Maximum --dimensions="Name=QueueName,Value=$i" |jq '.Datapoints[].Maximum'|awk '{sum += $1} END {print sum}')
  fi
  if [ $sum_week -gt 0 ]
  then
    echo $i >> queue_I.txt
  else
    echo $i >> queue_O.txt
  fi
done

echo "Start getting queue URL for delete"
for i in $(cat queue_O.txt|xargs)
do
  echo "https://sqs.us-west-2.amazonaws.com/652029311869/$i" >> queue_for_delete.txt
  if [ $(grep "$i-DL" queue_url.txt|wc -l) -gt 0 ]
  then
    grep "$i-DL" queue_url.txt >> dlq.txt
  fi
done
sort dlq.txt |uniq -u >> queue_for_delete.txt

for i in $(cat queue_for_delete.txt|xargs)
do
  aws sqs delete-queue --queue-url $i
done