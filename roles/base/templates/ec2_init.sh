#!/bin/sh
#
# Init script for new EC2 nodes
#
echo 'Initializing EC2 node.'

echo 'Mounting NFS volume ${nfs_id}'.
mount -t efs -o tls ${nfs_id}:/ /opt
echo '${nfs_id}:/ /opt efs _netdev,tls 0 0' >> /etc/fstab

echo 'Starting Elastic Container Service agent for cluster ${cluster}.'
echo 'ECS_CLUSTER=${cluster}' >> /etc/ecs/ecs.config
docker run --name ecs-agent \
    --detach=true \
    --restart=on-failure:10 \
    --volume=/var/run/docker.sock:/var/run/docker.sock \
    --volume=/var/log/ecs:/log \
    --volume=/var/lib/ecs/data:/data \
    --net=host \
    --env-file=/etc/ecs/ecs.config \
    --env=ECS_LOGFILE=/log/ecs-agent.log \
    --env=ECS_DATADIR=/data/ \
    --env=ECS_ENABLE_TASK_IAM_ROLE=true \
    --env=ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true \
    amazon/amazon-ecs-agent:latest
