#!/bin/bash

#source conda rq
source /opt/conda/etc/profile.d/conda.sh

#update and install required python packages
echo 'installing: python3.10; libpython3.10-dev; libspdlog-dev; pip'
apt update > /dev/null 2>&1 && apt install python3.10 libpython3.10-dev libspdlog-dev pip -y > /dev/null 2>&1

#symlink target /usr/bin/python3.10 to link /usr/bin/python
echo 'symlinking file /usr/bin/python3.10 to link /usr/bin/python'
ln -s /usr/bin/python3.10 /usr/bin/python > /dev/null 2>&1

#setting up python3.10 executable along with conda's executable
echo 'updating python w/ update-alternatives'
update-alternatives --install /usr/bin/python python /usr/bin/python3.10 2 > /dev/null 2>&1

#momentarily deactivate conda and set the python executable in /usr/bin to take precendence
conda deactivate
export PATH=/usr/bin:$PATH

#install required pip packages
echo 'pip installing: packaging; numpy; netifaces; pyyaml'
python -m pip install packaging numpy netifaces pyyaml > /dev/null 2>&1

#reactivate conda env
conda activate humanoid_sim_env

