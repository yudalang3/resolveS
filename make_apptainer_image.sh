#!/bin/bash
# Apptainer 镜像构建脚本
# 用法: ./make_apptainer_image.sh

set -e

# 定义变量
OUTPUT_DIR="db"
IMAGE_NAME="${OUTPUT_DIR}/resolveS_apptainer_v0.0.1.sif"
DEF_FILE="${OUTPUT_DIR}/resolveS_apptainer.def"

# 创建输出目录
mkdir -p ${OUTPUT_DIR}

# 创建 Apptainer 定义文件
cat > ${DEF_FILE} << 'EOF'
Bootstrap: docker
From: registry.cn-hangzhou.aliyuncs.com/acs/ubuntu:22.04

%files
    # 将当前目录下的文件复制到容器中
    align_by_bowtie2.sh /opt/BioInfo/align_by_bowtie2.sh
    check_strand.py /opt/BioInfo/check_strand.py
    count_sam.sh /opt/BioInfo/count_sam.sh
    resolveS /opt/BioInfo/resolveS
    ref_bowtie2 /opt/BioInfo/ref_bowtie2

%post
    # 设置环境变量避免交互式提示
    export DEBIAN_FRONTEND=noninteractive
    
    # 使用阿里云镜像源加速
    sed -i 's@http://.*archive.ubuntu.com@http://mirrors.aliyun.com@g' /etc/apt/sources.list
    sed -i 's@http://.*security.ubuntu.com@http://mirrors.aliyun.com@g' /etc/apt/sources.list
    
    # 最小化安装 Python3 和 Perl，清理 apt 缓存
    apt-get update && apt-get install -y --no-install-recommends \
        python3-minimal \
        perl \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*
    
    # 设置可执行权限
    chmod +x /opt/BioInfo/resolveS
    chmod +x /opt/BioInfo/align_by_bowtie2.sh
    chmod +x /opt/BioInfo/check_strand.py
    chmod +x /opt/BioInfo/count_sam.sh
    
    # 确保 bowtie2 可执行文件有执行权限
    if [ -d "/opt/BioInfo/ref_bowtie2/bowtie2" ]; then
        chmod +x /opt/BioInfo/ref_bowtie2/bowtie2/*
    fi
    
    # 清理不必要的文件和缓存（在最后执行）
    rm -rf /var/cache/apt/* \
        /var/log/*.log \
        /usr/share/doc/* \
        /usr/share/man/*

%environment
    # 将 bowtie2 添加到 PATH
    export PATH="/opt/BioInfo/ref_bowtie2/bowtie2:$PATH"
    export LC_ALL=C

%runscript
    # 默认运行 resolveS
    exec /opt/BioInfo/resolveS "$@"

%labels
    Author resolveS
    Version v0.0.1
    Description resolveS: Resolve RNA-Seq Strand Specificity

%help
    这是 resolveS 的 Apptainer 容器镜像。
    
    使用方法:
        apptainer run ${IMAGE_NAME}
        apptainer exec ${IMAGE_NAME} resolveS
        
    resolveS 是一个快速检测 RNA-Seq 链特异性的工具。
EOF

echo "========================================"
echo "开始构建 Apptainer 镜像..."
echo "========================================"

# 检查必要文件是否存在
echo "检查必要文件..."
for file in align_by_bowtie2.sh check_strand.py count_sam.sh resolveS; do
    if [ ! -f "$file" ]; then
        echo "错误: 找不到文件 $file"
        exit 1
    fi
done

if [ ! -d "ref_bowtie2" ]; then
    echo "错误: 找不到目录 ref_bowtie2"
    exit 1
fi

echo "所有必要文件检查完成！"

# 构建镜像（可能需要 sudo 权限）
echo "开始构建镜像（这可能需要几分钟时间）..."
apptainer build ${IMAGE_NAME} ${DEF_FILE}

if [ $? -eq 0 ]; then
    echo "========================================"
    echo "镜像构建成功: ${IMAGE_NAME}"
    echo "========================================"
    echo "测试镜像:"
    echo "  apptainer run ${IMAGE_NAME}"
    echo "  apptainer exec ${IMAGE_NAME} resolveS"
else
    echo "镜像构建失败！"
    exit 1
fi

# 可选：删除定义文件
# rm ${DEF_FILE}
echo "定义文件保留为: ${DEF_FILE}"
