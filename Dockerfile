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
RUN mkdir /opt/clang+llvm-7.0.1/ && \
    cd /opt/clang+llvm-7.0.1/ && \
    wget http://releases.llvm.org/7.0.1/clang+llvm-7.0.1-x86_64-linux-gnu-ubuntu-16.04.tar.xz -O - \
         | tar -x -I xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file)-7.0; \
    done && \
    cp /opt/clang+llvm-7.0.1/lib/libomp.so /opt/clang+llvm-7.0.1/lib/libomp.so.5

# Build arrow and pyarrow
RUN mkdir -p /tmp/arrow && \
    cd /tmp/arrow && \
    wget https://github.com/apache/arrow/archive/apache-arrow-0.14.0.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    pip3 install -r /tmp/arrow/python/requirements-build.txt && \
    mkdir -p /tmp/arrow/cpp/build && \
    cd /tmp/arrow/cpp/build && \
    CXX=clang++-7.0 CC=clang-7.0 \
        cmake \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_CXX_STANDARD=17 \
            -DCMAKE_INSTALL_PREFIX=/tmp/arrow/dist \
            -DCMAKE_INSTALL_LIBDIR=lib \
            -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
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
    make install && \
    cd /tmp/arrow/python && \
    PYARROW_WITH_PARQUET=1 ARROW_HOME=/tmp/arrow/dist \
        python3 setup.py build_ext --bundle-arrow-cpp bdist_wheel && \
    mkdir -p /opt/arrow-0.14/share && \
    cp /tmp/arrow/python/dist/*.whl /opt/arrow-*/share &&\
    cp -r /tmp/arrow/dist/* /opt/arrow-*/ && \
    cd / && rm -rf /tmp/arrow
