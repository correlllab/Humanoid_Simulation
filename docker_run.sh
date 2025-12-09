#!/bin/bash

xhost +local:docker

# Get host video and input group IDs
VIDEO_GID=$(getent group video | cut -d: -f3)
INPUT_GID=$(getent group input | cut -d: -f3)

docker run --gpus all -it --rm \
  --network host \
  --ipc=host \
  --shm-size=16g \
  --privileged \
  --group-add ${VIDEO_GID} \
  --group-add ${INPUT_GID} \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -e DISPLAY=$DISPLAY \
  -e QT_X11_NO_MITSHM=1 \
  -e LIBGL_ALWAYS_INDIRECT=0 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
  -v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro \
  -v /dev/input:/dev/input:ro \
  -v /dev/dri:/dev/dri:rw \
  -v /run/udev:/run/udev:ro \
  --publish 8211:8211 \
  --publish 8899:8899 \
  humanoid-sim:latest \
  /bin/bash