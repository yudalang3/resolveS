#!/bin/bash
# Singularity 镜像构建脚本
# 用法: ./make_singularity_image.sh

set -e

# 定义变量
OUTPUT_DIR="db"
IMAGE_NAME="${OUTPUT_DIR}/resolveS_singularity_v0.0.6.sif"
DEF_FILE="${OUTPUT_DIR}/resolveS.def"

# 创建输出目录
mkdir -p ${OUTPUT_DIR}

# 创建 Singularity 定义文件，这个意思是把EOF中间的文本写入到resolveS.def文件中
cat > ${DEF_FILE} << 'EOF'
Bootstrap: docker
From: registry.cn-hangzhou.aliyuncs.com/acs/ubuntu:22.04

%files
    # 将 resolveS 目录复制到容器中
    resolveS/bin/resolveS /opt/BioInfo/resolveS/resolveS
    resolveS/bin/align_by_bowtie2.sh /opt/BioInfo/resolveS/align_by_bowtie2.sh
    resolveS/bin/check_strand.py /opt/BioInfo/resolveS/check_strand.py
    resolveS/bin/count_sam.sh /opt/BioInfo/resolveS/count_sam.sh
    resolveS/bowtie2 /opt/BioInfo/bowtie2
    resolveS/ref_default /opt/BioInfo/ref_default

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
    chmod +x /opt/BioInfo/resolveS/resolveS
    chmod +x /opt/BioInfo/resolveS/align_by_bowtie2.sh
    chmod +x /opt/BioInfo/resolveS/check_strand.py
    chmod +x /opt/BioInfo/resolveS/count_sam.sh

    # 确保 bowtie2 可执行文件有执行权限
    if [ -d "/opt/BioInfo/bowtie2" ]; then
        chmod +x /opt/BioInfo/bowtie2/bowtie2*
        # 删除 bowtie2 中不必要的文件以减小镜像体积
        cd /opt/BioInfo/bowtie2
        rm -f *-debug
        rm -rf example doc scripts
        rm -f MANUAL MANUAL.markdown README.md NEWS TUTORIAL AUTHORS
    fi

    # 清理不必要的文件和缓存（在最后执行）
    rm -rf /var/cache/apt/* \
        /var/log/*.log \
        /usr/share/doc/* \
        /usr/share/man/*

%environment
    # 将 bowtie2 添加到 PATH
    export PATH="/opt/BioInfo/bowtie2:$PATH"
    export LC_ALL=C

%runscript
    # 默认运行 resolveS
    exec /opt/BioInfo/resolveS/resolveS "$@"

%labels
    Author resolveS
    Version v0.0.6
    Description resolveS: Resolve RNA-Seq Strand Specificity

%help
    这是 resolveS 的 Singularity 容器镜像 v0.0.6。

    使用方法:
        singularity run resolveS_singularity_v0.0.6.sif
        singularity exec resolveS_singularity_v0.0.6.sif resolveS

    resolveS 是一个快速检测 RNA-Seq 链特异性的工具。
EOF

echo "========================================"
echo "开始构建 Singularity 镜像 v0.0.6..."
echo "========================================"

# 检查必要文件是否存在
echo "检查必要文件..."
if [ ! -d "resolveS" ]; then
    echo "错误: 找不到目录 resolveS"
    exit 1
fi

for file in resolveS/bin/resolveS resolveS/bin/align_by_bowtie2.sh resolveS/bin/check_strand.py resolveS/bin/count_sam.sh; do
    if [ ! -f "$file" ]; then
        echo "错误: 找不到文件 $file"
        exit 1
    fi
done

if [ ! -d "resolveS/bowtie2" ]; then
    echo "错误: 找不到目录 resolveS/bowtie2"
    exit 1
fi

if [ ! -d "resolveS/ref_default" ]; then
    echo "错误: 找不到目录 resolveS/ref_default"
    exit 1
fi

echo "所有必要文件检查完成！"

# 构建镜像（需要 sudo 权限）
echo "开始构建镜像（这可能需要几分钟时间）..."
sudo singularity build ${IMAGE_NAME} ${DEF_FILE}

if [ $? -eq 0 ]; then
    echo "========================================"
    echo "镜像构建成功: ${IMAGE_NAME}"
    echo "========================================"
    echo "测试镜像:"
    echo "  singularity run ${IMAGE_NAME}"
    echo "  singularity exec ${IMAGE_NAME} resolveS"
else
    echo "镜像构建失败！"
    exit 1
fi

# 可选：删除定义文件
# rm ${DEF_FILE}
echo "定义文件保留为: ${DEF_FILE}"
