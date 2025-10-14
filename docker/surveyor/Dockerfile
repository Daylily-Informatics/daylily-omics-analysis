# syntax=docker/dockerfile:1
FROM ubuntu:22.04

ARG SURVEYOR_VERSION=main
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        python3 \
        python3-pip \
        python3-venv \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libncurses5-dev \
        libncursesw5-dev \
        pkg-config \
        samtools \
        bcftools && \
    rm -rf /var/lib/apt/lists/*

ENV CFLAGS="-O3 -pipe -fPIC -mavx512f -mavx512dq -mavx512cd -mavx512bw -mavx512vl -mavx512ifma -mavx512vbmi2 -mavx512fp16 -mavx512vnni -mavx2 -mfma"
ENV CXXFLAGS="$CFLAGS"

RUN useradd --create-home --shell /bin/bash surveyor
USER surveyor
WORKDIR /opt/surveyor

RUN git clone --depth 1 --branch "${SURVEYOR_VERSION}" https://github.com/Mesh89/SurVeyor.git src
WORKDIR /opt/surveyor/src

RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir .

ENV PATH="/home/surveyor/.local/bin:${PATH}"
ENV PYTHONPATH="/opt/surveyor/src:${PYTHONPATH}"

ENTRYPOINT ["surveyor"]
CMD ["--help"]
