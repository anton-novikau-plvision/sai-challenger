FROM debian:buster

MAINTAINER andriy.kokhan@gmail.com

#COPY ["no-check-valid-until", "/etc/apt/apt.conf.d/"]

RUN echo "deb [arch=amd64] http://debian-archive.trafficmanager.net/debian/ buster main contrib non-free" >> /etc/apt/sources.list && \
        echo "deb-src [arch=amd64] http://debian-archive.trafficmanager.net/debian/ buster main contrib non-free" >> /etc/apt/sources.list && \
        echo "deb [arch=amd64] http://debian-archive.trafficmanager.net/debian-security/ buster/updates main contrib non-free" >> /etc/apt/sources.list && \
        echo "deb-src [arch=amd64] http://debian-archive.trafficmanager.net/debian-security/ buster/updates main contrib non-free" >> /etc/apt/sources.list && \
        echo "deb [arch=amd64] http://debian-archive.trafficmanager.net/debian buster-backports main" >> /etc/apt/sources.list

## Make apt-get non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Install generic packages
RUN apt-get update && apt-get install -y \
        apt-utils \
        vim \
        curl \
        wget \
        unzip \
        git \
        procps \
        build-essential \
        graphviz \
        doxygen \
        aspell \
        python \
        python-pip \
        python3-pip \
        rsyslog \
        supervisor

RUN python3 -m pip install redis pytest

# Install dependencies
RUN apt-get install -y redis-server libhiredis0.14

# Install sonic-swss-common & sonic-sairedis building dependencies
RUN apt-get install -y \
        make libtool m4 autoconf dh-exec debhelper automake cmake pkg-config \
        libhiredis-dev libnl-3-dev libnl-genl-3-dev libnl-route-3-dev swig3.0 \
        libpython2.7-dev libgtest-dev

RUN apt-get install -y \
        libnl-3-dev libnl-genl-3-dev libnl-route-3-dev libnl-nf-3-dev libzmq3-dev

RUN git clone --recursive https://github.com/Azure/sonic-swss-common \
        && cd sonic-swss-common \
        && git checkout 3ec30ef \
        && ./autogen.sh && ./configure && dpkg-buildpackage -us -uc -b

RUN dpkg -i libswsscommon_1.0.0_amd64.deb \
        && dpkg -i libswsscommon-dev_1.0.0_amd64.deb \
        && dpkg -i libswsscommon-dbg_1.0.0_amd64.deb \
        && dpkg -i python-swsscommon_1.0.0_amd64.deb \
        && dpkg -i python3-swsscommon_1.0.0_amd64.deb

RUN git clone https://github.com/Azure/sonic-sairedis.git \
        && cd sonic-sairedis \
        && git checkout 0bf336a \
        && git submodule update --init --recursive \
        && ./autogen.sh && ./configure --with-sai=vs && make -j4 \
        && make install && ldconfig

# Update Redis configuration
RUN sed -ri 's/^# unixsocket/unixsocket/' /etc/redis/redis.conf
RUN sed -ri 's/^unixsocketperm .../unixsocketperm 777/' /etc/redis/redis.conf
RUN sed -ri 's/redis-server.sock/redis.sock/' /etc/redis/redis.conf

# Enable keyspace notifications as per sonic-swss-common/README.md
RUN sed -ri 's/notify-keyspace-events ""/notify-keyspace-events AKE/' /etc/redis/redis.conf

# Do not daemonize redis-server since supervisord will manage it
RUN sed -ri 's/^daemonize yes/daemonize no/' /etc/redis/redis.conf

# Disable kernel logging support
RUN sed -ri '/imklog/s/^/#/' /etc/rsyslog.conf

COPY scripts/sai.profile /etc/sai.d/sai.profile
COPY scripts/lanemap.ini /usr/share/sonic/hwsku/lanemap.ini
COPY scripts/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY scripts/veth-create.sh /usr/bin/veth-create.sh

WORKDIR /sai-challenger/tests

CMD ["/usr/bin/supervisord"]

