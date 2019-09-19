#!/bin/sh
#
# Init script for new EC2 nodes. The EC2 instance tags 'Environment' and
# 'EfsVolume' must be available. These supply the cluster name and EFS volume
# to auto-mount, respectively. All tags are added as ECS attributes to aid in
# task placement.
#
echo "Initializing EC2 node."
apk update
apk add jq

echo "Reading EC2 metadata."
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
CLUSTER_TAG="Environment"
EFS_VOLUME_TAG="EfsVolume"
CLUSTER=""
while [ "$CLUSTER" == "" ]
do
  sleep 1
  CLUSTER=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$CLUSTER_TAG" --region=$REGION --output=text | cut -f5)
  EFS_VOLUME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$EFS_VOLUME_TAG" --region=$REGION --output=text | cut -f5)
  TAGS_JSON=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" --region=$REGION)
  ECS_ATTRIBUTES=$(echo $TAGS_JSON | jq --compact-output '.Tags[] | { (.Key): (.Value)}' | tr -d '\n' | sed 's/}{/, /g')
done

# Mount NFS volume
if [[ -n $EFS_VOLUME ]]
then
  echo "Mounting Elastic File System volume $EFS_VOLUME."
  mount -t efs -o tls $EFS_VOLUME:/ /opt
  echo "$EFS_VOLUME:/ /opt efs _netdev,tls 0 0" >> /etc/fstab
else
  echo "EFS volume tag $EFS_VOLUME_TAG not found; skipping."
fi

echo "Configuring Elastic Container Service."
cat << EOF > /etc/ecs/ecs.config
ECS_CLUSTER=$CLUSTER
ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","syslog","awslogs","none"]
ECS_INSTANCE_ATTRIBUTES=$ECS_ATTRIBUTES
ECS_LOGFILE=/log/ecs-agent.log
ECS_DATADIR=/data/
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
EOF

echo "Starting Elastic Container Service agent for cluster $CLUSTER."
docker run --name ecs-agent \
    --detach=true \
    --restart=on-failure:10 \
    --volume=/var/run/docker.sock:/var/run/docker.sock \
    --volume=/var/log/ecs:/log \
    --volume=/var/lib/ecs/data:/data \
    --net=host \
    --env-file=/etc/ecs/ecs.config \
    amazon/amazon-ecs-agent:latest

echo 'Completed initialization.'
