# ==============================
# Stage 1: Builder
# ==============================
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Denver
ENV CONDA_DIR=/opt/conda
ENV PATH=$CONDA_DIR/bin:$PATH
ENV OMNI_KIT_ACCEPT_EULA=yes

# Set HTTP/HTTPS proxy (optional)
ARG http_proxy
ARG https_proxy
ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}

# Use US mirror for faster downloads
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://us.archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list && \
    sed -i 's|http://security.ubuntu.com/ubuntu/|http://security.ubuntu.com/ubuntu/|g' /etc/apt/sources.list

# Install build dependencies + X11 support for GUI rendering
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-12 g++-12 cmake build-essential curl unzip git-lfs wget \
    libglu1-mesa-dev vulkan-tools libvulkan1 \
    libx11-6 libxext6 libxrender1 libxi6 libxrandr2 libxcursor1 libxinerama1 \
    libgl1-mesa-glx libglib2.0-0 libsm6 libxt6 libxkbcommon-x11-0 \
    libssl-dev libusb-1.0-0-dev libudev-dev pkg-config libgtk-3-dev coreutils\
    libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev at v4l-utils udev kmod lsb-release \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100 \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p $CONDA_DIR && \
    rm miniconda.sh && \
    $CONDA_DIR/bin/conda clean -afy

# Accept Conda TOS and create environment
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda create -n humanoid_sim_env python=3.11 -y && \
    conda clean -afy

# Switch to Conda environment
SHELL ["conda", "run", "-n", "humanoid_sim_env", "/bin/bash", "-c"]  

# Install libgcc/libstdc++ for C++17 support
RUN conda install -y -c conda-forge "libgcc-ng>=12" "libstdcxx-ng>=12" && \
    conda clean -afy

# Install PyTorch NIGHTLY for RTX 5070 Ti (50 series) support
RUN pip install --upgrade pip && \
    pip install --upgrade --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128

# Install Isaac Sim
RUN pip install "isaacsim[all,extscache]==5.0.0" --extra-index-url https://pypi.nvidia.com

# Create working directory
RUN mkdir -p /home/code
WORKDIR /home/code

RUN apt update && apt install sudo

#installing librealsense drivers early bc it literally takes forever to build
RUN git clone https://github.com/realsenseai/librealsense.git
WORKDIR /home/code/librealsense
RUN mkdir -p /etc/udev/rules.d/
RUN . scripts/setup_udev_rules.sh
#subsequent step fails when ran in multi-command 'run' command
RUN conda run /bin/bash -c bash -c ". scripts/patch-realsense-ubuntu-lts-hwe.sh"
RUN mkdir build
RUN cd build
WORKDIR /home/code/librealsense/build
RUN cmake ../ -DCMAKE_BUILD_TYPE=Release
RUN make uninstall
RUN make clean
RUN make
RUN make -j$(($(nproc)-1)) install

WORKDIR /home/code

# Clone and install IsaacLab
RUN git clone https://github.com/isaac-sim/IsaacLab.git && \
    cd IsaacLab && \
    git checkout v2.2.0 && \
    ./isaaclab.sh --install

# Build CycloneDDS
RUN git clone https://github.com/eclipse-cyclonedds/cyclonedds -b releases/0.10.x /cyclonedds && \
    cd /cyclonedds && mkdir build install && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=../install && \
    cmake --build . --target install

ENV CYCLONEDDS_HOME=/cyclonedds/install

# Install unitree_sdk2_python
RUN git clone https://github.com/unitreerobotics/unitree_sdk2_python && \
    cd unitree_sdk2_python && pip install -e .

# Clone unitree_sim_isaaclab
RUN git clone https://github.com/correlllab/CL_isaaclab_sim.git /home/code/CL_isaaclab_sim && \
    cd /home/code/CL_isaaclab_sim && pip install -r requirements.txt

RUN cd /home/code/CL_isaaclab_sim && . fetch_assets.sh


# Clone models and ROS
RUN git clone https://huggingface.co/datasets/unitreerobotics/unitree_model /home/code/unitree_model
ENV UNITREE_MODEL_DIR=/home/code/unitree_model

RUN git clone https://github.com/unitreerobotics/unitree_ros.git /home/code/unitree_ros
ENV UNITREE_ROS_DIR=/home/code/unitree_ros


RUN git clone https://github.com/unitreerobotics/unitree_rl_lab.git /home/code/unitree_rl_lab && \
    cd /home/code/unitree_rl_lab && \
    sed -i 's|UNITREE_MODEL_DIR = "path/to/unitree_model"|UNITREE_MODEL_DIR = os.getenv("UNITREE_MODEL_DIR", "/home/code/unitree_model")|g' \
      ./source/unitree_rl_lab/unitree_rl_lab/assets/robots/unitree.py && \
    sed -i 's|UNITREE_ROS_DIR = "path/to/unitree_ros"|UNITREE_ROS_DIR = os.getenv("UNITREE_ROS_DIR", "/home/code/unitree_ros")|g' \
      ./source/unitree_rl_lab/unitree_rl_lab/assets/robots/unitree.py && \
    ./unitree_rl_lab.sh -i


# Clone H12 Lab Docs
RUN git clone https://github.com/correlllab/h12-lab-docs.git /home/code/h12-lab-docs

# Clone H12 Stand
RUN git clone https://github.com/correlllab/h12_stand.git /home/code/h12_stand

#Setup sources
RUN set -eux; \
    ROS_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}'); \
    curl -L -o /tmp/ros2.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_VERSION}/ros2-apt-source_${ROS_VERSION}.$(. /etc/os-release && echo $VERSION_CODENAME)_all.deb"; \
    dpkg -i /tmp/ros2.deb; \
    rm /tmp/ros2.deb

#Install ros humble desktop and rmw cyclonedds cpp implementation
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-desktop \
    ros-humble-rmw-cyclonedds-cpp \
    && rm -rf /var/lib/apt/lists/*

#Set environment variables
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ENV ROS_DISTRO=humble
# ==============================
# Stage 2: Runtime
# ==============================
FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Denver
ENV CONDA_DIR=/opt/conda
ENV PATH=$CONDA_DIR/bin:$PATH
ENV OMNI_KIT_ALLOW_ROOT=1
ENV OMNI_KIT_ACCEPT_EULA=yes
ENV UNITREE_ROS_DIR=/home/code/unitree_ros
ENV UNITREE_MODEL_DIR=/home/code/unitree_model
ENV CYCLONEDDS_HOME=/cyclonedds/install

# Install runtime dependencies + X11 libraries for GUI
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglu1-mesa git-lfs zenity unzip \
    libvulkan1 vulkan-tools \
    libx11-6 libxext6 libxrender1 libxi6 libxrandr2 libxcursor1 libxinerama1 \
    libgl1-mesa-glx libglib2.0-0 libsm6 libxt6 libxkbcommon-x11-0 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy from builder
COPY --from=builder /home/code /home/code
COPY --from=builder /cyclonedds /cyclonedds
COPY --from=builder /opt/conda /opt/conda
COPY --from=builder /opt/ros/humble /opt/ros/humble

COPY conda_overlay_ros2.sh /home/code/conda_overlay_ros2.sh

# Initialize bashrc (removed OMNI_KIT_DISABLE_STARTUP)
RUN echo 'source /opt/conda/etc/profile.d/conda.sh' >> ~/.bashrc && \
    echo 'conda activate humanoid_sim_env' >> ~/.bashrc && \
    echo 'chmod +x /home/code/conda_overlay_ros2.sh && . /home/code/conda_overlay_ros2.sh' >> ~/.bashrc && \
    echo 'source /opt/ros/humble/setup.sh' >> ~/.bashrc && \ 
    echo 'export OMNI_KIT_ALLOW_ROOT=1' >> ~/.bashrc && \
    echo 'export OMNI_KIT_ACCEPT_EULA=yes' >> ~/.bashrc && \
    echo 'export UNITREE_MODEL_DIR=/home/code/unitree_model' >> ~/.bashrc && \
    echo 'export UNITREE_ROS_DIR=/home/code/unitree_ros' >> ~/.bashrc && \
    echo 'export CYCLONEDDS_HOME=/cyclonedds/install' >> ~/.bashrc && \
    echo 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp' >> ~/.bashrc

WORKDIR /home/code

# Default to Conda environment bash
CMD ["conda", "run", "-n", "humanoid_sim_env", "/bin/bash"]
