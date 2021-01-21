#!/bin/sh
echo "Empty files"
for i in $(ls *.txt *.json|xargs)
do
  if [ -f $i ]
  then
    :>$i
  fi
done

echo "Getting queue url and name"
aws sqs list-queues --max-results 1000 --profile dev > queue_list.json
jq -r '.QueueUrls[]' queue_list.json|sed 's/"//g'|sed 's/,//g' > queue_url.txt
while [ $(cat queue_list.json|grep NextToken|wc -l) -gt 0 ]
do
  jq -r '.NextToken' queue_list.json > token.txt
  aws sqs list-queues --next-token $(cat token.txt) --max-results 1000 --profile dev > queue_list.json
  jq -r '.QueueUrls[]' queue_list.json|sed 's/"//g'|sed 's/,//g' >> queue_url.txt
done
sed 's|https://sqs.us-west-2.amazonaws.com/652029311869/||g' queue_url.txt |sed 's|.*-DL||g'|sed '/^$/d' > queue_name.txt

echo "Start filtering queue not received message"
for i in $(cat queue_name.txt|xargs)
do
  if [ -z $(aws cloudwatch get-metric-statistics --metric-name NumberOfMessagesReceived --start-time 2021-01-12T00:00:00Z --end-time 2021-01-19T00:00:00Z --period 86400 --namespace AWS/SQS --statistics Maximum --dimensions="Name=QueueName,Value=$i" --profile dev|jq '.Datapoints[].Maximum'|awk '{sum += $1} END {print sum}') ]
  then
    sum_week=0
  else
    sum_week=$(aws cloudwatch get-metric-statistics --metric-name NumberOfMessagesReceived --start-time 2021-01-12T00:00:00Z --end-time 2021-01-19T00:00:00Z --period 86400 --namespace AWS/SQS --statistics Maximum --dimensions="Name=QueueName,Value=$i" --profile dev|jq '.Datapoints[].Maximum'|awk '{sum += $1} END {print sum}')
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
  grep "$i" queue_url.txt >> queue_for_delete.txt
done