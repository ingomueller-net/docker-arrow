FROM ingomuellernet/boost:1.74.0 as boost-builder

FROM ubuntu:bionic
MAINTAINER Ingo Müller <ingo.mueller@inf.ethz.ch>

# Basics
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        bison \
        cmake \
        flex \
        pkg-config \
        python3-pip \
        wget \
        xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Clang+LLVM
RUN mkdir /opt/clang+llvm-9.0.0/ && \
    cd /opt/clang+llvm-9.0.0/ && \
    wget --progress=dot:giga http://releases.llvm.org/9.0.0/clang+llvm-9.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz -O - \
         | tar -x -I xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file)-9.0; \
    done && \
    cp /opt/clang+llvm-9.0.0/lib/libomp.so /opt/clang+llvm-9.0.0/lib/libomp.so.5

# Copy boost over from builder
COPY --from=boost-builder /opt/ /opt/

RUN for file in /opt/boost-1.74.0/include/*; do \
        ln -s $file /usr/include/; \
    done && \
    for file in /opt/boost-1.74.0/lib/*; do \
        ln -s $file /usr/lib/; \
    done

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/boost-1.74.0

# Build arrow and pyarrow
RUN mkdir -p /tmp/arrow && \
    cd /tmp/arrow && \
    wget --progress=dot:giga https://github.com/apache/arrow/archive/apache-arrow-0.14.0.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    pip3 install -r /tmp/arrow/python/requirements-build.txt && \
    mkdir -p /tmp/arrow/cpp/build && \
    cd /tmp/arrow/cpp/build && \
    CXX=clang++-9.0 CC=clang-9.0 \
        cmake \
            -DCMAKE_COLOR_MAKEFILE=OFF \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_CXX_STANDARD=17 \
            -DCMAKE_INSTALL_PREFIX=/tmp/arrow/dist \
            -DCMAKE_INSTALL_LIBDIR=lib \
            -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
            -DBUILD_WARNING_LEVEL=PRODUCTION \
            -DARROW_WITH_RAPIDJSON=ON \
            -DARROW_PARQUET=ON \
            -DARROW_PYTHON=ON \
            -DARROW_FLIGHT=OFF \
            -DARROW_GANDIVA=OFF \
            -DARROW_BUILD_UTILITIES=OFF \
            -DARROW_CUDA=OFF \
            -DARROW_ORC=OFF \
            -DARROW_JNI=OFF \
            -DARROW_TENSORFLOW=OFF \
            -DARROW_HDFS=OFF \
            -DARROW_BUILD_TESTS=OFF \
            -DARROW_RPATH_ORIGIN=ON \
            .. && \
    make -j$(nproc) install && \
    cd /tmp/arrow/python && \
    PYARROW_WITH_PARQUET=1 ARROW_HOME=/tmp/arrow/dist \
        python3 setup.py build_ext --bundle-arrow-cpp bdist_wheel && \
    mkdir -p /opt/arrow-0.14/share && \
    cp /tmp/arrow/python/dist/*.whl /opt/arrow-*/share &&\
    cp -r /tmp/arrow/dist/* /opt/arrow-*/ && \
    cd / && rm -rf /tmp/arrow
