#!/bin/bash
# *****************************************************************
# (C) Copyright IBM Corp. 2021, 2023. All Rights Reserved.
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
  echo $ONNX_CUDA_ARCH
  CMAKE_CUDA_EXTRA_DEFINES+=" CMAKE_CUDA_ARCHITECTURES=${ONNX_CUDA_ARCH} "
fi

export CUDACXX=$CUDA_HOME/bin/nvcc
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib -L${BUILD_PREFIX}/lib "
export CXXFLAGS="${CXXFLAGS} -I${PREFIX}/include -Wno-unused-parameter -Wno-unused"
export CFLAGS="${CFLAGS} -Wno-unused-parameter -Wno-unused"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${PREFIX}/lib"

ARCH=`uname -p`

if [[ -z "${cpu_opt_arch}" ]]; then
     CPU_ARCH_FLAG='';
else
     if [[ "${ARCH}" == 'x86_64' || "${ARCH}" == 's390x' ]]; then
          CPU_ARCH_FLAG="-march=${cpu_opt_arch}"
     fi
     if [[ "${ARCH}" == 'ppc64le' ]]; then
          if [[ $ppc_arch == "p10" ]]; then
              CPU_ARCH_FLAG="-mcpu=${cpu_opt_arch}"
          else
              # We can't use mcpu=power8 here because onnxruntime doesn't build for it.
              # Error: lto1: "error: builtin function '__builtin_altivec_stxvl' requires
              # the '-mcpu=power9' and '-m64' options"
              # This is the reason why onnxruntime built on P9 won't work on P8 systems.
              CPU_ARCH_FLAG="-mcpu=power9"
          fi
     fi
fi

if [[ -z "${cpu_opt_tune}" ]]; then
     CPU_TUNE_FLAG='';
else
     CPU_TUNE_FLAG="-mtune=${cpu_opt_tune}";
fi

if [[ -z "${vector_settings}" ]]; then
     VEC_OPTIONS='';
else
     vecs=$(echo ${vector_settings} | tr "," "\n")
     for setting in $vecs
     do
          VEC_OPTIONS+="-m${setting} ${NL}"
     done
fi

export CXXFLAGS="${CXXFLAGS} $CPU_ARCH_FLAG $CPU_TUNE_FLAG $VEC_OPTIONS"
export CFLAGS="${CFLAGS} $CPU_ARCH_FLAG $CPU_TUNE_FLAG $VEC_OPTIONS"
export LDFLAGS="${LDFLAGS} -L${PREFIX} -lre2"
export CXXFLAGS="${CXXFLAGS} -fplt"
export CFLAGS="${CFLAGS} -fplt"

if [[ $ppc_arch == "p10" ]]
then
    # Removing these libs so that libonnxruntime.so links against libstdc++.so present on
    # the system provided by gcc-toolset-11
    rm ${PREFIX}/lib/libstdc++.so*
    rm ${BUILD_PREFIX}/lib/libstdc++.so*
    LTO=""
else
    LTO="--enable_lto"
fi

python tools/ci_build/build.py \
    $LTO \
    --build_dir build-ci \
    --use_full_protobuf \
    ${CUDA_ARGS} \
    --cmake_extra_defines ${CMAKE_CUDA_EXTRA_DEFINES} Protobuf_PROTOC_EXECUTABLE=$PREFIX/bin/protoc Protobuf_INCLUDE_DIR=$PREFIX/include "onnxruntime_PREFER_SYSTEM_LIB=ON" onnxruntime_USE_COREML=OFF CMAKE_PREFIX_PATH=$PREFIX CMAKE_INSTALL_PREFIX=$PREFIX ONNXRUNTIME_VERSION=$(cat ./VERSION_NUMBER) \
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

