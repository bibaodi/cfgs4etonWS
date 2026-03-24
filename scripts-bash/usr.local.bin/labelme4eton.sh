#!/bin/bash

function v2(){
# Set folder: use first argument if provided, otherwise default
_folder=${1:-"/mnt/datas/42workspace/34-project_ML_data_models_UltrasoundIntelligence/10-datas4ML/3-thyroid/241207_all82AixThyroidNodules"}

# If argument was given and it's a relative path, convert to absolute
if [[ -n "$1" && "$_folder" != /* ]]; then
    _folder=$(realpath -m "$_folder")   # -m works even if path doesn't exist
fi

cd /home/eton/00-srcs/11-externals/labelme.wkentaro
conda activate base
source .venv/bin/activate

read -r -p "open '$_folder' ? (y/n): " ans

test ${ans} != 'y' && exit 0   # ⚠️ This line has a bug: should be `[ "$ans" != "y" ]`

python -m labelme ${_folder}
}

v2 $@

function v1(){

_folder=${1:-"/mnt/datas/42workspace/34-project_ML_data_models_UltrasoundIntelligence/10-datas4ML/3-thyroid/241207_all82AixThyroidNodules"}

cd /home/eton/00-srcs/11-externals/labelme.wkentaro
#conda activate base
/mnt/datas/miniconda3/bin/conda activate base
source .venv/bin/activate

read -r -p "open '$_folder' ? (y/n): " ans

test -ne 'y' && exit 0

python -m labelme ${_folder} 
}
