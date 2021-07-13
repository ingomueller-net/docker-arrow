FROM ingomuellernet/boost:1.76.0 as boost-builder

FROM ubuntu:focal AS builder
MAINTAINER Ingo Müller <ingo.mueller@inf.ethz.ch>

# Basics
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        bison \
        cmake \
        flex \
        libtinfo5 \
        pkg-config \
        python3-pip \
        wget \
        xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Clang+LLVM
RUN mkdir /opt/clang+llvm-11.1.0/ && \
    cd /opt/clang+llvm-11.1.0/ && \
    wget --progress=dot:giga https://github.com/llvm/llvm-project/releases/download/llvmorg-11.1.0/clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-16.04.tar.xz -O - \
         | tar -x -I xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file)-11.1; \
    done && \
    ln -s libomp.so /opt/clang+llvm-11.1.0/lib/libomp.so.5 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-11.1 100 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-11.1 100

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/clang+llvm-11.1.0

# Copy boost over from builder
COPY --from=boost-builder /opt/ /opt/

RUN for file in /opt/boost-1.76.0/include/*; do \
        ln -s $file /usr/include/; \
    done && \
    for file in /opt/boost-1.76.0/lib/*; do \
        ln -s $file /usr/lib/; \
    done

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/boost-1.76.0

# Build arrow and pyarrow
RUN mkdir -p /tmp/arrow && \
    cd /tmp/arrow && \
    wget --progress=dot:giga https://github.com/apache/arrow/archive/apache-arrow-0.14.1.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    { \
        echo 'diff --git a/cpp/CMakeLists.txt b/cpp/CMakeLists.txt'; \
        echo 'index d4b90c7bc..7075310a6 100644'; \
        echo '--- a/cpp/CMakeLists.txt'; \
        echo '+++ b/cpp/CMakeLists.txt'; \
        echo '@@ -648,8 +648,8 @@ if(ARROW_STATIC_LINK_LIBS)'; \
        echo '   add_dependencies(arrow_dependencies ${ARROW_STATIC_LINK_LIBS})'; \
        echo ' endif()'; \
        echo ''; \
        echo '-set(ARROW_SHARED_PRIVATE_LINK_LIBS ${ARROW_STATIC_LINK_LIBS} ${BOOST_SYSTEM_LIBRARY}'; \
        echo '-                                   ${BOOST_FILESYSTEM_LIBRARY} ${BOOST_REGEX_LIBRARY})'; \
        echo '+set(ARROW_SHARED_PRIVATE_LINK_LIBS ${ARROW_STATIC_LINK_LIBS} ${BOOST_FILESYSTEM_LIBRARY}'; \
        echo '+                                   ${BOOST_SYSTEM_LIBRARY} ${BOOST_REGEX_LIBRARY})'; \
        echo ''; \
        echo ' list(APPEND ARROW_STATIC_LINK_LIBS ${BOOST_SYSTEM_LIBRARY} ${BOOST_FILESYSTEM_LIBRARY}'; \
        echo '             ${BOOST_REGEX_LIBRARY})'; \
        echo 'diff --git a/cpp/thirdparty/versions.txt b/cpp/thirdparty/versions.txt'; \
        echo 'index d960cb0d0..397a4bd98 100644'; \
        echo '--- a/cpp/thirdparty/versions.txt'; \
        echo '+++ b/cpp/thirdparty/versions.txt'; \
        echo '@@ -28,7 +28,7 @@ BROTLI_VERSION=v1.0.7'; \
        echo ' BZIP2_VERSION=1.0.6'; \
        echo ' CARES_VERSION=1.15.0'; \
        echo ' DOUBLE_CONVERSION_VERSION=v3.1.4'; \
        echo '-FLATBUFFERS_VERSION=v1.10.0'; \
        echo '+FLATBUFFERS_VERSION=v1.12.0'; \
        echo ' GBENCHMARK_VERSION=v1.4.1'; \
        echo ' GFLAGS_VERSION=v2.2.0'; \
        echo ' GLOG_VERSION=v0.3.5'; \
    } | patch -p1 && \
    pip3 install -r /tmp/arrow/python/requirements-build.txt && \
    mkdir -p /tmp/arrow/cpp/build && \
    cd /tmp/arrow/cpp/build && \
    CXX=clang++-11.1 CC=clang-11.1 \
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

# Main image
FROM ubuntu:focal

COPY --from=builder /opt/arrow-0.14 /opt/arrow-0.14
COPY --from=builder /opt/boost-1.76.0 /opt/boost-1.76.0
