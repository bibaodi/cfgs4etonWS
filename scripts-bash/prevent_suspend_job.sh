# Job: YOLO26 segmentation training.
# Only this file changes when you add/swap a task.

JOB_NAME="yolo26-seg-train"
JOB_LOG_PREFIX="yolo_train"
JOB_CONDA_ENV="trainLinkNet18_env"
JOB_WORKDIR="$HOME/00-srcs/ml_dl2linkNet"
JOB_GPU_INDEX=0

_basemodelHome="/mnt/datas/42workspace/34-pj_ML_data_models_UltrasoundIntelligence/44-ML.Models/32-carotidPlaque/26-trainWithV9.1-full/260812.model_segCAPlaque_22yl26_S256-v03/model_segCAPlaque_yolo26n-seg_260812T1116/weights"
_basemodelName="model_segCAPlaque_22yl26_S256-v03.pt"
_baseWeight="${_basemodelHome}/${_basemodelName}"
_ds="/train/data/carotidplaque_yolo_v9.1full/dataset.yaml"

[[ -f "$_baseWeight" ]] || { echo "ERROR: weights not found: $_baseWeight" >&2; exit 1; }
[[ -f "$_ds" ]]         || { echo "ERROR: dataset yaml not found: $_ds" >&2; exit 1; }

JOB_COMMAND=(
    python yolo26_seg/train_yolo26.py
    --img_size 320
    --batch    50
    --epochs   100
    --data     "$_ds"
    --no_cache
    --patience 0
    --workers  4
    --device   "$JOB_GPU_INDEX"
    --resume   "$_baseWeight"
    --finetune
)
