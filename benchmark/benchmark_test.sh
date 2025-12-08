#!/bin/bash

# 性能测试脚本 - resolveS 软件基准测试
# 测试不同参数组合的时间和内存消耗

set -euo pipefail

# 配置路径
RESOLVE_SCRIPT="/home/dell/projects/estimate_strand4NGS/formal_program/resolveS/resolveS"
SINGULARITY_IMAGE="/home/dell/projects/estimate_strand4NGS/formal_program/resolveS/db/resolveS_singularity_v0.0.4.sif"
APPTAINER_IMAGE="/home/dell/projects/estimate_strand4NGS/formal_program/resolveS/db/resolveS_apptainer_v0.0.4.sif"

# 测试数据
SINGLE_INPUT="./1-1/1-1_1.fq.gz"
BATCH_INPUT="input.batch.run.txt"

# 输出文件
RESULTS_FILE="results.tsv"
TEMP_DIR="benchmark_temp"
LOG_DIR="benchmark_logs"

# 创建必要的目录
mkdir -p "$TEMP_DIR" "$LOG_DIR"

# 初始化结果文件
echo -e "Input_type\tApproach\tThreads_number\tMaximum_align_reads\tRepeat\tTime_cost_s\tMemory_cost_GiB" > "$RESULTS_FILE"

# 计数器
test_count=0
total_tests=$((2 * 3 * 2 * 2 * 3))  # 72个测试

# 测试函数
run_test() {
    local input_type=$1
    local approach=$2
    local threads=$3
    local max_reads=$4
    local repeat=$5

    test_count=$((test_count + 1))
    echo "=========================================="
    echo "测试进度: $test_count/$total_tests"
    echo "Input type: $input_type"
    echo "Approach: $approach"
    echo "Threads: $threads"
    echo "Max-reads: $max_reads"
    echo "Repeat: $repeat"
    echo "=========================================="

    # 准备输入参数
    local input_param=""
    if [ "$input_type" == "Single_gzip_fastq" ]; then
        input_param="-s $SINGLE_INPUT"
    else
        input_param="-b $BATCH_INPUT"
    fi

    # 准备输出文件名
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local test_id="${input_type}_${approach}_t${threads}_u${max_reads}_r${repeat}_${timestamp}"
    local time_log="$LOG_DIR/${test_id}_time.log"
    local stdout_log="$LOG_DIR/${test_id}_stdout.log"
    local stderr_log="$LOG_DIR/${test_id}_stderr.log"

    # 构建命令
    local cmd=""
    case "$approach" in
        "Bash_script")
            cmd="$RESOLVE_SCRIPT $input_param -p $threads -u $max_reads"
            ;;
        "Singularity_image")
            cmd="singularity run $SINGULARITY_IMAGE $input_param -p $threads -u $max_reads"
            ;;
        "Apptainer_image")
            cmd="apptainer run $APPTAINER_IMAGE $input_param -p $threads -u $max_reads"
            ;;
    esac

    # 运行测试并测量性能
    echo "运行命令: $cmd"

    # 使用 /usr/bin/time 测量时间和内存
    if /usr/bin/time -v $cmd > "$stdout_log" 2> "$time_log"; then
        echo "✓ 测试成功完成"
    else
        echo "✗ 测试失败"
        echo "0\t0" >> "$TEMP_DIR/${test_id}.result"
        return 1
    fi

    # 从 time 输出中提取时间和内存信息
    local elapsed_time=$(grep "Elapsed (wall clock) time" "$time_log" | awk '{print $NF}' | awk -F: '{
        if (NF == 3) {
            # h:mm:ss.ms 格式
            print $1*3600 + $2*60 + $3
        } else if (NF == 2) {
            # mm:ss.ms 格式
            print $1*60 + $2
        } else {
            # ss.ms 格式
            print $1
        }
    }')

    local max_memory_kb=$(grep "Maximum resident set size" "$time_log" | awk '{print $NF}')
    local max_memory_gib=$(echo "scale=3; $max_memory_kb / 1024 / 1024" | bc)

    # 如果提取失败，设置默认值
    if [ -z "$elapsed_time" ]; then
        elapsed_time="0"
    fi
    if [ -z "$max_memory_gib" ]; then
        max_memory_gib="0"
    fi

    echo "时间消耗: ${elapsed_time}s"
    echo "内存消耗: ${max_memory_gib}GiB"

    # 写入结果
    echo -e "${input_type}\t${approach}\t${threads}\t${max_reads}\t${repeat}\t${elapsed_time}\t${max_memory_gib}" >> "$RESULTS_FILE"

    # 清理临时文件（可选）
    # rm -f "$stdout_log"

    echo ""
}

# 主测试循环
echo "开始性能基准测试..."
echo "总测试数: $total_tests"
echo ""

# 遍历所有参数组合
for input_type in "Single_gzip_fastq" "Batch_gzip_fastq_5"; do
    for approach in "Bash_script" "Singularity_image" "Apptainer_image"; do
        for threads in 15 8; do
            for max_reads in 4000000 1000000; do
                for repeat in 1 2 3; do
                    # 运行测试
                    run_test "$input_type" "$approach" "$threads" "$max_reads" "$repeat" || true

                    # 短暂休息，避免系统过载
                    sleep 2
                done
            done
        done
    done
done

echo "=========================================="
echo "所有测试完成！"
echo "结果已保存到: $RESULTS_FILE"
echo "日志文件保存在: $LOG_DIR/"
echo "=========================================="

# 显示结果摘要
echo ""
echo "结果预览:"
head -20 "$RESULTS_FILE" | column -t -s $'\t'
