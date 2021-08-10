#!/bin/bash
# *****************************************************************
# (C) Copyright IBM Corp. 2021. All Rights Reserved.
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

rm -r cmake/external/onnx cmake/external/eigen cmake/external/cub cmake/external/onnx-tensorrt
mv onnx eigen cub onnx-tensorrt cmake/external/

pushd cmake/external/SafeInt/safeint
ln -s $PREFIX/include/SafeInt.hpp
popd

pushd cmake/external/json
ln -s $PREFIX/include single_include
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
  export CUDNN_HOME=$PREFIX
  CUDA_ARGS=" --use_cuda --cuda_home ${CUDA_HOME} --cudnn_home ${PREFIX} "
  CMAKE_CUDA_EXTRA_DEFINES="CMAKE_CUDA_COMPILER=${CUDA_HOME}/bin/nvcc CMAKE_CUDA_HOST_COMPILER=${CXX} CMAKE_CUDA_ARCHITECTURES=37;50;52;60;70 CMAKE_AR=${GCC_AR} CMAKE_RANLIB=${GCC_RANLIB} CMAKE_NM=${GCC_NM}"
fi

TRT_FLAG=""
if [[ $PY_VER > 3.8 ]];
then
  TRT_FLAG=" --use_tensorrt --tensorrt_home $PREFIX"
fi

export CUDACXX=$CUDA_HOME/bin/nvcc
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib"

python tools/ci_build/build.py \
    --enable_lto \
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
