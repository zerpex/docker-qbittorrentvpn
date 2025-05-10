# ----------- Stage 1: Build environment -----------
FROM debian:bookworm-slim AS builder

ARG QBITTORRENT_VERSION=5.1.0
ARG LIBTORRENT_VERSION=2.0.11
ARG BOOST_VERSION=1.86.0
ARG QT_VERSION=6.9.0

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    automake \
    libtool \
    git \
    cmake \
    ninja-build \
    python3 \
    perl \
    curl \
    ca-certificates \
    libxkbcommon-x11-dev \
    libxcb1-dev \
    libx11-dev \
    libxext-dev \
    libxrender-dev \
    libxi-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libjpeg-dev \
    libssl-dev \
    libdbus-1-dev \
    zlib1g-dev \
    libgl1-mesa-dev \
    libdrm-dev \
    libsqlite3-dev \
    libxcb-keysyms1-dev \
    libxcb-image0-dev \
    libxcb-shm0-dev \
    libxcb-icccm4-dev \
    libxcb-sync-dev \
    libxcb-render-util0-dev \
    libxcb-xfixes0-dev \
    libxcb-shape0-dev \
    libxcb-randr0-dev \
    libxcb-glx0-dev \
    libxcb-xinerama0-dev \
    libxcb-util-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# ----------- Boost -----------
RUN BOOST_VERSION_UNDERSCORE=$(echo $BOOST_VERSION | sed 's/\./_/g') && \
    curl -L https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_UNDERSCORE}.tar.gz | tar xz && \
    cd boost_${BOOST_VERSION_UNDERSCORE} && \
    ./bootstrap.sh --prefix=/usr/local && \
    ./b2 install -j$(nproc) && \
    cd .. && rm -rf boost_${BOOST_VERSION_UNDERSCORE}

# ----------- Qt -----------
    RUN curl -L https://download.qt.io/official_releases/qt/6.9/${QT_VERSION}/single/qt-everywhere-src-${QT_VERSION}.tar.xz | tar xJ && \
    cd qt-everywhere-src-${QT_VERSION} && \
    ./configure -prefix /opt/Qt-${QT_VERSION} -opensource -confirm-license -nomake examples -nomake tests && \
    cmake --build . --parallel $(nproc) && \
    cmake --install . && \
    cd .. && rm -rf qt-everywhere-src-${QT_VERSION}

ENV CMAKE_PREFIX_PATH=/opt/Qt-${QT_VERSION}/lib/cmake

# ----------- Libtorrent -----------
RUN curl -L https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_VERSION}/libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz | tar xz && \
    cd libtorrent-rasterbar-${LIBTORRENT_VERSION} && \
    cmake -G Ninja -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_CXX_STANDARD=17 \
        -Dpython-bindings=OFF \
        -Dbuild_tests=OFF \
        -Ddeprecated-functions=OFF && \
    cmake --build build --parallel $(nproc) && \
    cmake --install build && \
    cd .. && rm -rf libtorrent-rasterbar-${LIBTORRENT_VERSION}

# ----------- qBittorrent-nox -----------
RUN curl -L https://github.com/qbittorrent/qBittorrent/archive/refs/tags/release-${QBITTORRENT_VERSION}.tar.gz | tar xz && \
    cd qBittorrent-release-${QBITTORRENT_VERSION} && \
    cmake -G Ninja -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DGUI=OFF \
        -DCMAKE_CXX_STANDARD=17 && \
    cmake --build build --parallel $(nproc) && \
    cmake --install build && \
    cd .. && rm -rf qBittorrent-release-${QBITTORRENT_VERSION}


# ----------- Stage 2: Runtime image -----------
FROM debian:bookworm-slim

LABEL maintainer="zerpex <zerpex@jayjay.pm>"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libqt5network5 \
    libqt5xml5 \
    libqt5sql5 \
    libbrotli1 \
    openvpn \
    wireguard-tools \
    unrar-free \
    p7zip-full \
    nano \
    iproute2 \
    iptables \
    openresolv \
    ipcalc \
    kmod \
    dos2unix \
    net-tools \
    iputils-ping \
    moreutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create user and directories
RUN mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent && \
    chown -R nobody:nogroup /downloads /config /etc/openvpn /etc/qbittorrent

# Remove src_valid_mark from wg-quick
RUN sed -i /net\.ipv4\.conf\.all\.src_valid_mark/d `which wg-quick`

# Copy only the built binaries and essential files
COPY --from=builder /usr/local/bin/qbittorrent-nox /usr/local/bin/
COPY --from=builder /usr/local/lib/libtorrent* /usr/local/lib/
COPY --from=builder /usr/lib/libtorrent* /usr/lib/
COPY --from=builder /usr/local/lib/libboost* /usr/local/lib/
COPY --from=builder /usr/lib/libboost* /usr/lib/
COPY --from=builder /opt/Qt-6.9.0 /opt/Qt-6.9.0

# Copy config files and custom scripts
COPY openvpn/ /etc/openvpn/
COPY qbittorrent/ /etc/qbittorrent/
COPY bashrc/ /root/
COPY speedtest/ /usr/bin/
RUN chmod +x /etc/qbittorrent/*.sh \
             /etc/qbittorrent/*.init \
             /etc/openvpn/*.sh \
             /usr/bin/speedtest
RUN echo "/opt/Qt-6.9.0/lib" > /etc/ld.so.conf.d/qt6.conf && ldconfig

VOLUME /config /downloads

EXPOSE 8080
EXPOSE 8999
EXPOSE 8999/udp

CMD ["/bin/bash", "/etc/openvpn/start.sh"]
