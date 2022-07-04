#!/bin/bash
# *****************************************************************
# (C) Copyright IBM Corp. 2021, 2022. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************

set -ex

rm -r cmake/external/onnx cmake/external/eigen cmake/external/cub cmake/external/pytorch_cpuinfo
mv onnx eigen cub json cmake/external/
mkdir -p cmake/external/pytorch_cpuinfo
cp -r cpuinfo/* cmake/external/pytorch_cpuinfo/

rm -r cmake/external/protobuf

pushd cmake/external/SafeInt/safeint
ln -s $BUILD_PREFIX/include/SafeInt.hpp
popd

pushd cmake/external/json
ln -s $BUILD_PREFIX/include single_include
popd

# Needs eigen 3.4
# rm -rf cmake/external/eigen
# pushd cmake/external
# ln -s $PREFIX/include/eigen3 eigen
# popd

CUDA_ARGS=""
CMAKE_CUDA_EXTRA_DEFINES=""
if [[ $build_type == "cuda" ]]
then
  export CUDNN_HOME=$BUILD_PREFIX
  CUDA_ARGS=" --use_cuda --cuda_home ${CUDA_HOME} --cudnn_home ${BUILD_PREFIX} "
  CMAKE_CUDA_EXTRA_DEFINES="CMAKE_CUDA_COMPILER=${CUDA_HOME}/bin/nvcc CMAKE_CUDA_HOST_COMPILER=${CXX} CMAKE_AR=${GCC_AR} CMAKE_RANLIB=${GCC_RANLIB} CMAKE_NM=${GCC_NM}"

  ONNX_CUDA_ARCH="${cuda_levels//,/;}"
  ONNX_CUDA_ARCH="${ONNX_CUDA_ARCH//./}"

  CUDA_VERSION="${cudatoolkit%.*}"
  if [[ $CUDA_VERSION == '10' ]]; then
    ONNX_CUDA_ARCH="${ONNX_CUDA_ARCH//;75/}"     # Onnxruntime fails with cudatoolkit 10.2 for cuda compute 75
  fi
  echo $ONNX_CUDA_ARCH
  CMAKE_CUDA_EXTRA_DEFINES+=" CMAKE_CUDA_ARCHITECTURES=${ONNX_CUDA_ARCH} "
fi

export CUDACXX=$CUDA_HOME/bin/nvcc
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib -L${BUILD_PREFIX}/lib -lre2 "
export CXXFLAGS="${CXXFLAGS} -I${PREFIX}/include -Wno-unused-parameter -Wno-unused"
export CFLAGS="${CFLAGS} -Wno-unused-parameter -Wno-unused"

ARCH=`uname -p`
if [[ "${ARCH}" == 'ppc64le' ]]; then
    export CXXFLAGS="${CXXFLAGS} -mcpu=power9"
    export CFLAGS="${CFLAGS} -mcpu=power9"
fi

if [[ $ppc_arch == "p10" ]]
then
    export CXXFLAGS="${CXXFLAGS} -mtune=power10 -fplt"
    export CFLAGS="${CFLAGS} -mtune=power10 -fplt"
    LTO=""
else
    LTO="--enable_lto"
fi

python tools/ci_build/build.py \
    $LTO \
    --build_dir build-ci \
    --use_full_protobuf \
    ${CUDA_ARGS} \
    --cmake_extra_defines ${CMAKE_CUDA_EXTRA_DEFINES} Protobuf_PROTOC_EXECUTABLE=$BUILD_PREFIX/bin/protoc Protobuf_INCLUDE_DIR=$PREFIX/include "onnxruntime_PREFER_SYSTEM_LIB=ON" onnxruntime_USE_COREML=OFF CMAKE_PREFIX_PATH=$PREFIX CMAKE_INSTALL_PREFIX=$PREFIX ONNXRUNTIME_VERSION=$(cat ./VERSION_NUMBER) \
    --cmake_generator Ninja \
    --build_wheel \
    --build_shared_lib \
    --config Release \
    --update \
    --build \
    --skip_submodule_sync

if [[ $build_type == "cuda" ]]
then
  cp build-ci/Release/dist/onnxruntime_gpu-*.whl onnxruntime_gpu-${PKG_VERSION}-py3-none-any.whl
else
  cp build-ci/Release/dist/onnxruntime-*.whl onnxruntime-${PKG_VERSION}-py3-none-any.whl
fi
python -m pip install onnxruntime*-${PKG_VERSION}-py3-none-any.whl

#Restore PATH variable
export PATH="$PATH_VAR"

