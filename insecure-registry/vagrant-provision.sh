#!/bin/bash
#
# provision script; install Docker engine & some handy tools.
#
# @see https://docs.docker.com/installation/ubuntulinux/
#


export DEBIAN_FRONTEND=noninteractive
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8


readonly COMPOSE_VERSION=1.5.1
readonly MACHINE_VERSION=v0.5.1

readonly DOCKVIZ_VERSION=v0.3
readonly DOCKVIZ_EXE_URL=https://github.com/justone/dockviz/releases/download/$DOCKVIZ_VERSION/dockviz_linux_amd64

readonly DOCKERGEN_VERSION=0.4.3
readonly DOCKERGEN_TARBALL=docker-gen-linux-amd64-$DOCKERGEN_VERSION.tar.gz

readonly DOCKERIZE_VERSION=v0.0.4
readonly DOCKERIZE_TARBALL=dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

readonly CADVISOR_VERSION=0.19.3
readonly CADVISOR_EXE_URL=https://github.com/google/cadvisor/releases/download/$CADVISOR_VERSION/cadvisor


#==========================================================#

#
# error handling
#

do_error_exit() {
    echo { \"status\": $RETVAL, \"error_line\": $BASH_LINENO }
    exit $RETVAL
}

trap 'RETVAL=$?; echo "ERROR"; do_error_exit '  ERR
trap 'RETVAL=$?; echo "received signal to stop";  do_error_exit ' SIGQUIT SIGTERM SIGINT


#---------------------------------------#
# fix base box
#

sudo cat <<-HOSTNAME > /etc/hostname
  localhost
HOSTNAME

cat <<-EOBASHRC  >> /home/vagrant/.bashrc
  export PS1='\[\033[01;32m\]\u@\h\[\033[01;34m\] \w \$\[\033[00m\] '
  export LC_CTYPE=C.UTF-8
EOBASHRC


# disable the warning "Your environment specifies an invalid locale"
sudo touch /var/lib/cloud/instance/locale-check.skip  || true


# update packages
#sudo apt-get update
sudo apt-get install -y curl unzip
#sudo apt-get -y -q upgrade
#sudo apt-get -y -q dist-upgrade


#==========================================================#


#---------------------------------------#
# Docker-related stuff
#

# install Docker
curl -sL https://get.docker.io/ | sudo sh

# add 'vagrant' user to docker group
sudo usermod -aG docker vagrant

# enable memory and swap accounting
sed -i -e \
  's/^GRUB_CMDLINE_LINUX=.+/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"/' \
  /etc/default/grub
sudo update-grub

# enable UFW forwarding
sed -i -e \
  's/^DEFAULT_FORWARD_POLICY=.+/DEFAULT_FORWARD_POLICY="ACCEPT"/' \
  /etc/default/ufw  \
  || true
#sudo ufw reload


#
# override "insecure-registry" error for private registry to ease testing
# @see http://stackoverflow.com/a/27163607/714426
#
cat << "EOF_REGISTRY" >> /etc/default/docker

# allow Docker Remote API
DOCKER_OPTS="$DOCKER_OPTS -H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock"

# allow HTTP access to private registry "registry.com"
DOCKER_OPTS="$DOCKER_OPTS --insecure-registry registry.com"
#DOCKER_OPTS="--insecure-registry 10.0.0.0/24 --insecure-registry registry.com"

EOF_REGISTRY



# install Docker Compose (was: Fig)
# @see http://docs.docker.com/compose/install/
curl -o docker-compose -L https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-`uname -s`-`uname -m`
chmod a+x docker-compose
sudo mv docker-compose /usr/local/bin


# install Docker Machine
# @see https://docs.docker.com/machine/
curl -o docker-machine.zip -L https://github.com/docker/machine/releases/download/$MACHINE_VERSION/docker-machine_linux-amd64.zip
unzip docker-machine.zip
rm docker-machine.zip
chmod a+x docker-machine*
sudo mv docker-machine* /usr/local/bin


# install dockviz
curl -o /usr/local/bin/dockviz -L $DOCKVIZ_EXE_URL
chmod a+x /usr/local/bin/dockviz


# install Pipework
# @see https://github.com/jpetazzo/pipework
curl -o pipework -L https://raw.githubusercontent.com/jpetazzo/pipework/master/pipework
chmod a+x pipework
sudo mv pipework /usr/local/bin


# install docker-gen
# @see https://github.com/jwilder/docker-gen
curl -o docker-gen.tar.gz -L https://github.com/jwilder/docker-gen/releases/download/$DOCKERGEN_VERSION/$DOCKERGEN_TARBALL
tar xvzf docker-gen.tar.gz
sudo chown root docker-gen
sudo chgrp root docker-gen
sudo mv docker-gen /usr/local/bin
rm *.tar.gz


# install dockerize
# @see https://github.com/jwilder/dockerize
curl -o dockerize.tar.gz -L https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/$DOCKERIZE_TARBALL
tar xzvf dockerize.tar.gz
sudo chown root dockerize
sudo chgrp root dockerize
sudo mv dockerize /usr/local/bin
rm *.tar.gz


# install swarm
sudo docker pull swarm


# install docker-bench-security
docker pull diogomonica/docker-bench-security
cat << EOF_BENCH_SECURITY > /usr/local/bin/docker-bench-security
#!/bin/sh

exec docker run -it --label docker-bench-security="" \
    --net host --pid host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /usr/lib/systemd:/usr/lib/systemd  \
    -v /etc:/etc \
    diogomonica/docker-bench-security

EOF_BENCH_SECURITY
chmod a+x /usr/local/bin/docker-bench-security


# install cAdvisor
curl -o /usr/local/bin/cadvisor -L $CADVISOR_EXE_URL
chmod a+x /usr/local/bin/cadvisor
docker pull google/cadvisor:latest

cat << EOF_CADVISOR > /etc/init/cadvisor.conf
description "cAdvisor"

start on filesystem and started docker
stop on runlevel [!2345]

#respawn

# @see https://github.com/google/cadvisor/blob/master/docs/running.md#standalone
script

    docker rm -f cadvisor  || true

    docker run  \
        --volume=/:/rootfs:ro          \
        --volume=/var/run:/var/run:rw  \
        --volume=/sys:/sys:ro          \
        --volume=/var/lib/docker/:/var/lib/docker:ro  \
        --publish=8080:8080  \
        --detach=true    \
        --restart=always \
        --name=cadvisor  \
        google/cadvisor:latest

end script
EOF_CADVISOR



# install weave
# @see https://github.com/zettio/weave
curl -o weave -L https://github.com/zettio/weave/releases/download/latest_release/weave
sudo chmod a+x  weave
sudo chown root weave
sudo chgrp root weave
sudo mv weave /usr/local/bin
# preload images
sudo weave setup



# install Docker-Host-Tools
# @see https://github.com/William-Yeh/docker-host-tools
DOCKER_HOST_TOOLS=( docker-rm-stopped  docker-rmi-repo  docker-inspect-attr )
for item in "${DOCKER_HOST_TOOLS[@]}"; do
  curl -o /usr/local/bin/$item  -sSL https://raw.githubusercontent.com/William-Yeh/docker-host-tools/master/$item
  chmod a+x /usr/local/bin/$item
done




#
# de-duplicate ID for Swarm
# @see https://github.com/docker/swarm/issues/563
# @see https://github.com/docker/swarm/issues/362
#
rm -f /etc/docker/key.json  || true


# clean up
sudo docker rm `sudo docker ps --no-trunc -a -q`  || true
sudo docker rmi -f busybox  || true

sudo rm -f \
  /var/log/messages   \
  /var/log/lastlog    \
  /var/log/auth.log   \
  /var/log/syslog     \
  /var/log/daemon.log \
  /var/log/docker.log \
  /home/vagrant/.bash_history \
  /var/mail/vagrant           \
  || true
